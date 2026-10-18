#!/usr/bin/env node
'use strict';
// Device migration is data-only: never source config/provider files or run hooks.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const cp = require('child_process');
const MAX = 16 * 1024 * 1024;
const NAME = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/;
const SERVICE = /^[A-Za-z0-9][A-Za-z0-9._:@+-]{0,255}$/;
const ENV = /^[A-Z][A-Z0-9_]{0,127}$/;
const MAGIC = Buffer.from('CROUTER-MIGRATE-1\n');
const root = fs.realpathSync(process.argv[2]);
const fail = message => { throw new Error(message); };
const own = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
function regular(file, optional = false) {
    let st;
    try { st = fs.lstatSync(file); } catch (e) { if (optional && e.code === 'ENOENT') return null; throw e; }
    if (!st.isFile() || st.nlink !== 1 || st.size > MAX) fail('expected a bounded regular file (no links)');
    return fs.readFileSync(file);
}
function base(input) {
    if (!path.isAbsolute(input)) fail('storage directories must be absolute');
    let p = input, rest = [];
    while (!fs.existsSync(p)) { rest.unshift(path.basename(p)); p = path.dirname(p); }
    return path.join(fs.realpathSync(p), ...rest);
}
function safe(file) {
    let p = path.parse(file).root;
    for (const part of file.slice(p.length).split(path.sep).filter(Boolean)) {
        p = path.join(p, part);
        try {
            const st = fs.lstatSync(p);
            if (st.isSymbolicLink() || (!st.isDirectory() && p !== file)) fail('linked/non-directory storage path');
        } catch (e) { if (e.code !== 'ENOENT') throw e; }
    }
    if (fs.existsSync(file)) regular(file);
    return file;
}
function atomic(file, bytes, exclusive = false) {
    safe(file);
    fs.mkdirSync(path.dirname(file), {recursive: true, mode: 0o700});
    const tmp = path.join(path.dirname(file), '.migration-' + crypto.randomBytes(12).toString('hex'));
    try {
        fs.writeFileSync(tmp, bytes, {mode: 0o600, flag: 'wx'});
        if (exclusive) { fs.linkSync(tmp, file); fs.unlinkSync(tmp); }
        else fs.renameSync(tmp, file);
    } finally { try { fs.unlinkSync(tmp); } catch (_) {} }
}
async function ttyLine(prompt, hidden = false) {
    const fd = fs.openSync('/dev/tty', 'r+');
    // Let the shell own terminal state and signals; a Node read stream leaves a
    // pending TTY worker read when closed between the two password prompts.
    const script = `
set +x
_old=$(stty -g) || exit 1
trap 'stty "$_old" 2>/dev/null' 0
trap 'exit 130' INT TERM HUP
if [ "$2" = hidden ]; then stty -echo || exit 1; fi
printf '%s' "$1" >&2
IFS= read -r _value || exit 1
if [ "$2" = hidden ]; then printf '\\n' >&2; fi
printf '%s' "$_value"
`;
    const child = cp.spawn('/bin/sh',['-c',script,'migration-prompt',prompt,hidden ? 'hidden' : 'visible'],{stdio:[fd,'pipe',fd]});
    const chunks = []; let length = 0;
    const interrupt = () => child.kill('SIGTERM');
    process.once('SIGINT',interrupt); process.once('SIGTERM',interrupt);
    try {
        return await new Promise((resolve,reject) => {
            child.stdout.on('data',chunk => { chunks.push(chunk); length += chunk.length; if (length > 4096) child.kill('SIGTERM'); });
            child.once('error',reject);
            child.once('close',code => code === 0 && length <= 4096 ? resolve(Buffer.concat(chunks).toString('utf8')) : reject(new Error('input cancelled or terminal input unavailable')));
        });
    } finally {
        process.removeListener('SIGINT',interrupt); process.removeListener('SIGTERM',interrupt);
        fs.closeSync(fd);
    }
}
function seal(payload, password) {
    const salt = crypto.randomBytes(16), iv = crypto.randomBytes(12);
    const key = crypto.scryptSync(password, salt, 32, {N: 32768, r: 8, p: 1, maxmem: 64 * 1024 * 1024});
    const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
    cipher.setAAD(MAGIC);
    const bytes = Buffer.concat([cipher.update(JSON.stringify(payload)), cipher.final()]);
    key.fill(0);
    return Buffer.concat([MAGIC, salt, iv, cipher.getAuthTag(), bytes]);
}
function open(bytes, password) {
    if (bytes.length < MAGIC.length + 44 || !bytes.subarray(0, MAGIC.length).equals(MAGIC)) fail('not a crouter migration package');
    const start = MAGIC.length;
    const key = crypto.scryptSync(password, bytes.subarray(start, start + 16), 32, {N: 32768, r: 8, p: 1, maxmem: 64 * 1024 * 1024});
    try {
        const decipher = crypto.createDecipheriv('aes-256-gcm', key, bytes.subarray(start + 16, start + 28));
        decipher.setAAD(MAGIC);
        decipher.setAuthTag(bytes.subarray(start + 28, start + 44));
        return JSON.parse(Buffer.concat([decipher.update(bytes.subarray(start + 44)), decipher.final()]).toString('utf8'));
    } catch (_) { fail('incorrect password or damaged package; nothing imported'); }
    finally { key.fill(0); }
}
// Literal shell assignments only. Conditional/dynamic assignments are inventoried,
// not evaluated. Raw bytes still travel in the authenticated package unchanged.
function assignments(text) {
    const result = Object.create(null);
    const rx = /^(?:export\s+)?([A-Z][A-Z0-9_]*)=(?:"((?:[^"\\]|\\[\s\S])*)"|'([^']*)'|([^\s;#]+))\s*(?:#.*)?$/gm;
    let m;
    while ((m = rx.exec(text))) result[m[1]] = {text:m[2] !== undefined ? m[2] : m[3] !== undefined ? m[3] : m[4], quote:m[3] !== undefined ? 'single' : m[2] !== undefined ? 'double' : 'bare', original:m[0]};
    return result;
}
function expand(value, vars) {
    if (value === undefined) return null;
    if (value.quote === 'single') return value.text;
    let text = value.text;
    if (/[`]|\$\(/.test(text)) return null;
    text = text.replace(/\\([\s\S])/g, (_, char) => {
        if (char === '$') return '\x00DOLLAR\x00';
        if (['"','\\','`','\n'].includes(char) || value.quote === 'bare') return char === '\n' ? '' : char;
        return '\\' + char;
    });
    let unresolved = false;
    const out = text.replace(/\$\{([A-Z][A-Z0-9_]*)(?::([-+])([^}]*))?\}|\$([A-Z][A-Z0-9_]*)|(\$)/g, (_, k, op, fallback, bare, unknown) => {
        if (unknown) { unresolved = true; return ''; }
        k = k || bare;
        if (own(vars, k) && vars[k] !== '') return op === '+' ? fallback : vars[k];
        if (op === '-') return fallback;
        if (op === '+') return '';
        unresolved = true; return '';
    });
    return unresolved ? null : out.replace(/\x00DOLLAR\x00/g,'$');
}
function remapPaths(text, source, destination) {
    const selected = new Set(['STATE_DIR','LOG_DIR','CLAUDE_BIN','NODE_BIN','INSTALL_DIR','ANTIGRAVITY_PROXY_DIR','AWS_SHARED_CREDENTIALS_FILE','AWS_CONFIG_FILE','GOOGLE_APPLICATION_CREDENTIALS','CLAUDE_CONFIG_DIR']);
    const parsed = assignments(text);
    for (const [key, item] of Object.entries(parsed)) {
        if (!selected.has(key) || item.quote !== 'single' && /[$`\\]/.test(item.text)) continue;
        for (const [oldDir,newDir] of [[source.root,destination.root],[source.home,destination.home],[source.state,destination.state],[source.userState,destination.userState]].sort((a,b) => b[0].length-a[0].length)) {
            if (oldDir !== newDir && (item.text === oldDir || item.text.startsWith(oldDir + '/'))) {
                const replacement = (item.original.startsWith('export ') ? 'export ' : '') + key + '=' + quote(newDir + item.text.slice(oldDir.length));
                text = text.replace(item.original,replacement); break;
            }
        }
    }
    return text;
}
function portableKeys() {
    const b = regular(safe(path.join(root, '.state/migration-credentials.json')), true);
    if (!b) return Object.create(null);
    const obj = JSON.parse(b);
    if (!obj || Array.isArray(obj) || typeof obj !== 'object' || Object.entries(obj).some(([k,v]) => !SERVICE.test(k) || typeof v !== 'string')) fail('invalid portable credential store');
    return Object.assign(Object.create(null),obj);
}
function readKey(service, nativeOnly = false) {
    const portable = nativeOnly ? null : portableKeys()[service];
    if (portable) return portable;
    const r = cp.spawnSync('security', ['find-generic-password', '-a', process.env.USER || '', '-s', service, '-w'], {encoding: 'utf8', maxBuffer: MAX, stdio: ['ignore', 'pipe', 'ignore']});
    if (r.status === 0) return r.stdout.replace(/\r?\n$/, '');
    if (r.error && r.error.code !== 'ENOENT') fail('cannot read crouter Keychain item');
    if (!r.error && ![44, 45].includes(r.status)) fail('Keychain access failed; unlock it and retry');
    return null;
}
function writeKey(service, value) {
    // Existing helper sends the secret through an expect-controlled PTY. Neither
    // the security child argv nor its environment contains the secret.
    const script = '. "$1/lib/key-mgmt.sh"; IFS= read -r _migration_secret; _keychain_put "$2" "$_migration_secret"';
    const r = cp.spawnSync('sh', ['-c', script, 'migration', root, service], {input: value + '\n', env: {...process.env, CROUTER_MIGRATING:'1'}, stdio: ['pipe', 'ignore', 'ignore']});
    if (r.status !== 0) fail('Keychain write failed');
}
function hasSecurity() {
    return cp.spawnSync('sh', ['-c', 'command -v security >/dev/null 2>&1 && command -v expect >/dev/null 2>&1']).status === 0;
}
function collect(stateOverride) {
    const home = fs.realpathSync(process.env.HOME);
    const payload = {format: 1, source: {root, home}, files: [], keys: [], env: [], notes: []};
    const config = regular(safe(path.join(root, 'config.sh')), true);
    const configText = config ? config.toString('utf8') : '';
    const configVars = assignments(configText);
    const vars = {...process.env, HOME: home, ROOT_DIR: root};
    for (const [k, v] of Object.entries(configVars)) {
        const resolved = expand(v, vars);
        if (resolved !== null) vars[k] = resolved;
    }
    const state = stateOverride || expand(configVars.STATE_DIR, vars) || process.env.STATE_DIR || path.join(root, '.state');
    if (/^\s*(?:export\s+)?STATE_DIR=/m.test(configText) && !stateOverride && expand(configVars.STATE_DIR, vars) === null) fail('dynamic STATE_DIR: pass --state-dir /absolute/path');
    const stateDir = base(state), userDir = base(path.join(process.env.XDG_STATE_HOME || path.join(home, '.local/state'), 'crouter'));
    payload.source.state = stateDir;
    payload.source.userState = userDir;
    const add = (area, name, file) => {
        const b = regular(safe(file), true);
        if (b) payload.files.push({area, name, data: b.toString('base64')});
        return b;
    };
    if (config) payload.files.push({area: 'root', name: 'config.sh', data: config.toString('base64')});
    const refs = new Set(), requiredRefs = new Set(), envs = new Set(), providerAuth = Object.create(null);
    const importedEnv = regular(safe(path.join(root, '.state/migration-environment.json')), true);
    if (importedEnv) {
        // Generated env is deliberately simple; use its metadata, never source it.
        const old = importedEnv;
        if (old) for (const [k,v] of Object.entries(JSON.parse(old))) if (ENV.test(k) && typeof v === 'string' && !own(vars,k)) vars[k] = v;
    }
    for (const filename of fs.readdirSync(path.join(root, 'providers')).filter(x => x.endsWith('.sh')).sort()) {
        const name = filename.slice(0, -3);
        if (!NAME.test(name)) fail('invalid provider filename');
        const b = add('provider', filename, path.join(root, 'providers', filename));
        const providerText = b.toString('utf8');
        const referencedAuth = [];
        const declared = assignments(providerText);
        for (const match of providerText.replace(/^[ \t]*#.*$/gm,'').matchAll(/\$\{?([A-Z][A-Z0-9_]*)/g)) {
            if (!['HOME','ROOT_DIR','STATE_DIR','LOG_DIR','NODE_BIN','CLAUDE_BIN','PATH','USER','TMPDIR','XDG_STATE_HOME'].includes(match[1]) && !own(declared,match[1])) { envs.add(match[1]); if (/(?:KEY|TOKEN|SECRET|CREDENTIAL)/.test(match[1])) referencedAuth.push(match[1]); }
        }
        const get = k => expand(declared[k], vars) || '';
        providerAuth[name] = {mode:get('AUTH_MODE'), refs:[], env:referencedAuth};
        const addRef = ref => { refs.add(ref); providerAuth[name].refs.push(ref); };
        const addEnv = key => { envs.add(key); providerAuth[name].env.push(key); };
        for (const field of ['PLAN_KEYS', 'API_KEYS', 'AUTH_KEYS', 'PLUS_KEYS', 'AUTH_KEYCHAIN_FALLBACK', 'API_KEY_REF']) {
            for (const ref of get(field).split(/\s+/).filter(Boolean)) { if (!SERVICE.test(ref)) fail('invalid registered Keychain service'); addRef(ref); }
        }
        if (get('AUTH_MODE') === 'keychain') addRef(get('AUTH_REFERENCE'));
        if (get('AUTH_MODE') === 'env' && get('AUTH_REFERENCE')) addEnv(get('AUTH_REFERENCE'));
        for (const field of ['PLAN_KEY_ENV', 'API_KEY_ENV', 'DEFAULT_TOKEN_ENV', 'DEFAULT_TOKEN_ENV_FALLBACK']) if (get(field)) addEnv(get(field));
        // Native cloud env credentials are included; external SDK/login files are not.
        for (const field of get('PASSTHROUGH_ENV').split(/\s+/).filter(Boolean)) if (ENV.test(field)) envs.add(field);
        if (get('AUTH_MODE') === 'command') payload.notes.push('provider ' + name + ': authentication command output is not executed or captured');
        for (const field of ['AUTH_MODE','AUTH_REFERENCE','PLAN_KEYS','API_KEYS','AUTH_KEYS','PLUS_KEYS','API_KEY_REF']) {
            if (new RegExp('^\\s*(?:export\\s+)?' + field + '=', 'm').test(providerText) && expand(declared[field], vars) === null) payload.notes.push('provider ' + name + ': dynamic ' + field + ' requires review');
        }
        const registry = add('registry', name + '.tsv', path.join(stateDir, 'keypools', name + '.tsv'));
        if (registry) for (const line of registry.toString('utf8').split('\n').filter(Boolean)) {
            const pair = line.split('\t');
            if (pair.length !== 2 || !['plan','api','main','plus'].includes(pair[0]) || !SERVICE.test(pair[1])) fail('invalid key registry');
            addRef(pair[1]); requiredRefs.add(pair[1]);
        }
    }
    if (fs.existsSync(userDir)) for (const filename of fs.readdirSync(userDir).sort()) {
        if (filename === 'selection' || /^last-model-[A-Za-z0-9][A-Za-z0-9._-]*$/.test(filename)) add('user', filename, path.join(userDir, filename));
    }
    for (const service of refs) {
        if (!SERVICE.test(service)) fail('invalid Keychain service declaration');
        const value = readKey(service);
        if (value !== null) payload.keys.push({service, value});
        else if (requiredRefs.has(service)) fail('Keychain item registered in a keypool is missing; repair it before export');
    }
    for (const name of envs) {
        if (!ENV.test(name)) fail('invalid credential environment name');
        if (own(vars, name) && vars[name]) payload.env.push({name, value: vars[name]});
    }
    const selectedFile = payload.files.find(f => f.area === 'user' && f.name === 'selection');
    const selected = selectedFile ? Buffer.from(selectedFile.data,'base64').toString().trim() : '';
    const auth = providerAuth[selected];
    if (auth && !['none','static','native','command'].includes(auth.mode) && !auth.refs.some(ref => payload.keys.some(k => k.service === ref)) && !auth.env.some(key => own(vars,key) && vars[key])) fail('selected provider has no available credential; repair it before export');
    payload.notes.push('Current shell environment takes precedence over imported environment values.');
    payload.notes.push('Native CLI logins, browser/OAuth sessions, external AWS/Google/Azure SDK credential files, and command/password-manager outputs need their own login or transfer.');
    payload.notes.push('Configuration and provider source is preserved byte-for-byte, including execution hooks and permission switches. Import never executes it; review it before the first launch.');
    return payload;
}
function validate(p) {
    if (!p || p.format !== 1 || !p.source || !Array.isArray(p.files) || !Array.isArray(p.keys) || !Array.isArray(p.env) || !Array.isArray(p.notes) || p.files.length > 1024 || p.keys.length > 4096 || p.env.length > 1024) fail('invalid migration manifest');
    for (const k of ['root','home','state','userState']) if (typeof p.source[k] !== 'string' || !path.isAbsolute(p.source[k])) fail('invalid source directories');
    const seen = new Set(); let total = 0;
    for (const f of p.files) {
        if (!f || typeof f.name !== 'string' || !((f.area === 'root' && f.name === 'config.sh') || (f.area === 'provider' && /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.sh$/.test(f.name)) || (f.area === 'registry' && /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.tsv$/.test(f.name)) || (f.area === 'user' && (f.name === 'selection' || /^last-model-[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(f.name))))) fail('invalid migration file path');
        if (seen.has(f.area + '/' + f.name)) fail('duplicate migration file'); seen.add(f.area + '/' + f.name);
        if (typeof f.data !== 'string' || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(f.data)) fail('invalid file encoding');
        const bytes = Buffer.from(f.data, 'base64'); total += bytes.length;
        if (total > MAX) fail('migration content is too large');
        if (f.area === 'registry') for (const line of bytes.toString().split('\n').filter(Boolean)) if (!/^(plan|api|main|plus)\t[A-Za-z0-9][A-Za-z0-9._:@+-]{0,255}$/.test(line)) fail('invalid registry entry');
        if (f.area === 'user' && !/^[A-Za-z0-9][A-Za-z0-9._:/@\[\]-]{0,1023}\n$/.test(bytes.toString())) fail('invalid selection/model state');
    }
    for (const [items, field, rx] of [[p.keys,'service',SERVICE],[p.env,'name',ENV]]) {
        const identities = new Set();
        for (const item of items) {
            if (!item || !rx.test(item[field]) || identities.has(item[field]) || typeof item.value !== 'string' || !item.value || item.value.length > 65536 || /[\x00]/.test(item.value)) fail('invalid/duplicate credential record');
            identities.add(item[field]);
        }
    }
    if (p.notes.some(n => typeof n !== 'string' || n.length > 4096)) fail('invalid handoff note');
}
const quote = value => "'" + value.replace(/'/g, "'\\''") + "'";
async function importPackage(p, password, yes, stateOverride) {
    validate(p);
    const home = fs.realpathSync(process.env.HOME);
    const state = base(stateOverride || process.env.STATE_DIR || path.join(root, '.state'));
    const user = base(path.join(process.env.XDG_STATE_HOME || path.join(home, '.local/state'), 'crouter'));
    const dest = {root, provider: path.join(root,'providers'), registry: path.join(state,'keypools'), user};
    const writes = p.files.map(f => ({file: safe(path.join(dest[f.area],f.name)), data: Buffer.from(f.data,'base64')}));
    // Rebase known machine roots in shell text. Arbitrary absolute paths remain
    // visible in the report; no command, hostname, endpoint, or model is guessed.
    const mapped = [];
    for (const w of writes) if (w.file.endsWith('.sh')) {
        const original = w.data.toString('utf8');
        const text = remapPaths(original,p.source,{root,home,state,userState:user});
        if (text !== original) mapped.push(path.basename(w.file));
        if (text !== original) w.data = Buffer.from(text);
    }
    const keychain = hasSecurity();
    const nativeKeys = keychain ? p.keys.filter(k => !/[\r\n]/.test(k.value)) : [];
    const fallbackKeys = p.keys.filter(k => !nativeKeys.includes(k));
    const envObject = Object.fromEntries(p.env.map(x => [x.name,x.value]));
    const envShell = p.env.map(x => 'if [ "${' + x.name + '+set}" != set ]; then export ' + x.name + '=' + quote(x.value) + '; fi\n').join('');
    const privateDir = path.join(root,'.state');
    if (p.env.length) {
        writes.push({file: safe(path.join(privateDir,'migration-env.sh')), data: Buffer.from(envShell)});
        writes.push({file: safe(path.join(privateDir,'migration-environment.json')), data: Buffer.from(JSON.stringify(envObject))});
    }
    const existingPortable = portableKeys();
    if (fallbackKeys.length || nativeKeys.some(k => own(existingPortable,k.service))) {
        const existing = existingPortable;
        for (const k of nativeKeys) delete existing[k.service];
        for (const k of fallbackKeys) existing[k.service] = k.value;
        writes.push({file: safe(path.join(privateDir,'migration-credentials.json')), data: Buffer.from(JSON.stringify(existing))});
    }
    const duplicates = new Set();
    for (const w of writes) { if (duplicates.has(w.file)) fail('duplicate destination'); duplicates.add(w.file); }
    const before = writes.map(w => ({file:w.file, data:regular(w.file,true), mode:fs.existsSync(w.file) ? fs.statSync(w.file).mode & 0o777 : null}));
    const previousKeys = nativeKeys.map(k => ({service:k.service, value:readKey(k.service,true)}));
    const conflicts = before.filter((v,i) => v.data && !v.data.equals(writes[i].data)).length + previousKeys.filter((k,i) => k.value !== null && k.value !== nativeKeys[i].value).length;
    console.log('Import: ' + p.files.length + ' files, ' + p.keys.length + ' keys (' + (keychain ? 'Keychain' : 'private mode-600 fallback') + '), ' + p.env.length + ' environment values.');
    if (p.files.some(f => /(?:BYPASS_PERMISSIONS\s*=\s*["']?1|dangerously-skip-permissions)/.test(Buffer.from(f.data,'base64').toString()))) console.log('REVIEW: source configuration enables permission bypass; it is preserved, not executed.');
    console.log('REVIEW: config/provider shell source will execute only on a later normal launch. Check local binaries, external paths, endpoints and services before launching.');
    if (keychain && fallbackKeys.length) console.log('Note: multiline keys use the private fallback, because security(1) uses line prompts.');
    console.log('Paths rebased to this checkout/home/state: ' + new Set(mapped).size + ' files.');
    for (const n of p.notes) console.log('Note: ' + n);
    if (conflicts && !yes && (await ttyLine('Replace ' + conflicts + ' conflicting files/keys (encrypted backup first)? [y/N] ')).toLowerCase() !== 'y') fail('import cancelled; nothing changed');
    const backup = path.join(privateDir,'migration-backups',new Date().toISOString().replace(/[:.]/g,'-') + '-' + crypto.randomBytes(4).toString('hex') + '.crm');
    const rollback = {format: 'crouter-rollback-1', files: before.map(x => ({file:x.file, mode:x.mode, data:x.data === null ? null : x.data.toString('base64')})), keys: previousKeys};
    atomic(backup, seal(rollback,password), true);
    let keyWrites = 0, fileWrites = 0;
    try {
        for (const k of nativeKeys) { keyWrites++; writeKey(k.service,k.value); }
        for (const w of writes) { fileWrites++; atomic(w.file,w.data); }
    } catch (e) {
        const errors = [];
        for (const original of before.slice(0,fileWrites).reverse()) try {
            if (original.data === null) { if (fs.existsSync(original.file)) fs.unlinkSync(original.file); }
            else { atomic(original.file,original.data); fs.chmodSync(original.file,original.mode); }
        } catch (_) { errors.push('file'); }
        for (const original of previousKeys.slice(0,keyWrites).reverse()) try {
            if (original.value === null) {
                const r = cp.spawnSync('security',['delete-generic-password','-a',process.env.USER || '', '-s',original.service],{stdio:'ignore'});
                if (![0,44].includes(r.status)) fail('delete failed');
            } else writeKey(original.service,original.value);
        } catch (_) { errors.push('Keychain'); }
        fail('import failed; ' + (errors.length ? 'rollback needs attention: ' + errors.join(', ') : 'original files/keys restored') + '. Encrypted backup: ' + backup);
    }
    console.log('Imported. Encrypted backup: ' + backup);
    console.log('No provider, hook, proxy, model, or login was started. Run crouter doctor <provider> after reviewing configuration.');
}
async function main() {
    const [command,...args] = process.argv.slice(3);
    if (command === '_get' || command === '_has' || command === '_forget') {
        if (args.length !== 1 || !SERVICE.test(args[0])) fail('invalid service');
        if (command === '_forget') {
            const entries = portableKeys();
            delete entries[args[0]];
            atomic(path.join(root,'.state/migration-credentials.json'),Buffer.from(JSON.stringify(entries)));
            return;
        }
        const value = portableKeys()[args[0]];
        if (!value) process.exitCode = 1; else if (command === '_get') process.stdout.write(value);
        return;
    }
    if (!command || ['-h','--help'].includes(command) || args.includes('--help') || args.includes('-h')) {
        console.log('usage: crouter migrate export <file> [--password-stdin] [--state-dir <path>]');
        console.log('       crouter migrate import <file> [--password-stdin] [--yes] [--state-dir <path>]');
        console.log('Passphrase is requested without echo. --password-stdin reads stdin (one trailing line ending removed).');
        console.log('AES-256-GCM encrypted; API keys included. Keep the passphrase separately.');
        return;
    }
    if (!['export','import'].includes(command) || !args[0] || args[0].startsWith('-')) fail('use migrate export|import <file>; see --help');
    const requestedFile = path.resolve(args.shift());
    const file = path.join(base(path.dirname(requestedFile)),path.basename(requestedFile));
    let stdin = false, yes = false, state;
    while (args.length) {
        const arg = args.shift();
        if (arg === '--password-stdin') stdin = true;
        else if (arg === '--yes' && command === 'import') yes = true;
        else if (arg === '--state-dir' && args[0]) state = args.shift();
        else fail('unknown migration option');
    }
    let password = stdin ? fs.readFileSync(0,'utf8') : await ttyLine('Migration passphrase: ',true);
    if (stdin) { password = password.replace(/\r?\n$/,''); }
    if (password.length < 12 || password.length > 4096) fail('passphrase must contain 12 to 4096 characters');
    if (command === 'export') {
        if (!stdin && password !== await ttyLine('Repeat passphrase: ',true)) fail('passphrases do not match');
        const p = collect(state); validate(p);
        const encrypted = seal(p,password);
        if (encrypted.length > MAX) fail('migration package exceeds 16 MiB; reduce custom provider/config size');
        atomic(file,encrypted,true);
        console.log('Exported: ' + p.files.length + ' files, ' + p.keys.length + ' keys, ' + p.env.length + ' environment values (encrypted, mode 600).');
        for (const n of p.notes) console.log('Note: ' + n);
    } else await importPackage(open(regular(file),password),password,yes,state);
}
main().catch(e => {
    // Never echo raw JSON, source lines, process stderr or secret-bearing errors.
    const safeErrors = /^(?:expected|storage|linked|cannot|input|not a|incorrect|dynamic|invalid|duplicate|migration|Keychain|import|use migrate|unknown migration|pass|source)/;
    console.error('crouter: ' + (safeErrors.test(e.message) ? e.message : 'migration failed; check paths, permissions and package format'));
    process.exitCode = 1;
});
