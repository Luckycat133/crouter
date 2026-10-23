#!/bin/sh
# Isolated migration contracts: no real config, credentials, network, or models.
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export ROOT_DIR TEST_SHELL=${TEST_SHELL:-sh}
node <<'JS'
'use strict';
const fs = require('fs'), path = require('path'), os = require('os'), cp = require('child_process'), crypto = require('crypto');
const tmp = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(),'crouter-migration-')));
const root = process.env.ROOT_DIR;
const shell = cp.spawnSync('/bin/sh',['-c','command -v "$1"','test',process.env.TEST_SHELL],{encoding:'utf8'}).stdout.trim();
const password = '迁移🔑 test passphrase " \\ $ newline\nsecond line';
const secret = 'api-test-quote-\'"-\\-$value';
const assert = (ok, message) => { if (!ok) throw new Error(message); };
function put(file, text) { fs.mkdirSync(path.dirname(file),{recursive:true}); fs.writeFileSync(file,text,{mode:0o600}); }
function fixture(name) {
    const repo = path.join(tmp,name,'repo'), home = path.join(tmp,name,'home'), keys = path.join(tmp,name,'keys');
    fs.mkdirSync(repo,{recursive:true}); fs.mkdirSync(home); fs.mkdirSync(keys);
    for (const dir of ['bin','lib']) fs.cpSync(path.join(root,dir),path.join(repo,dir),{recursive:true});
    fs.mkdirSync(path.join(repo,'providers'));
    put(path.join(repo,'VERSION'),'test\n');
    return {repo,home,keys};
}
const source = fixture('source'), target = fixture('target');
const tools = path.join(tmp,'tools'); fs.mkdirSync(tools);
put(path.join(tools,'security'),`#!/usr/bin/env node
const fs=require('fs'),path=require('path');const args=process.argv.slice(2),service=args[args.indexOf('-s')+1];
fs.appendFileSync(process.env.ARGV_LOG,JSON.stringify(args)+'\\n');
const file=path.join(process.env.FAKE_KEYS,service);
if(args[0]==='find-generic-password'){if(!fs.existsSync(file)||(!args.includes('-w')&&process.env.METADATA_FAIL_SERVICE===service))process.exit(44);if(args.includes('-w'))process.stdout.write(fs.readFileSync(file));}
else if(args[0]==='delete-generic-password'){if(fs.existsSync(file))fs.unlinkSync(file);else process.exit(44);}
else process.exit(2);
`);
put(path.join(tools,'expect'),`#!/usr/bin/env node
const fs=require('fs'),path=require('path');
const s=process.env.CR_KEYCHAIN_SERVICE,v=process.env.CR_KEYCHAIN_SECRET;
if(process.env.DROP_SERVICE===s)process.exit(0);
if(process.env.FAIL_SERVICE===s&&!fs.existsSync(process.env.FAIL_ONCE)){fs.writeFileSync(process.env.FAIL_ONCE,'failed');process.exit(1);}
fs.writeFileSync(path.join(process.env.FAKE_KEYS,s),process.env.WRONG_SERVICE===s?'wrong-persisted-key':v,{mode:0o600});
`);
fs.chmodSync(path.join(tools,'security'),0o700); fs.chmodSync(path.join(tools,'expect'),0o700);
function env(f, extra={}) { return {...process.env, HOME:f.home, XDG_STATE_HOME:path.join(f.home,'state'), STATE_DIR:'', PATH:tools+path.delimiter+process.env.PATH, USER:'migration-test', FAKE_KEYS:f.keys, ARGV_LOG:path.join(tmp,'argv.log'), FAIL_ONCE:path.join(tmp,'fail-once'), ...extra}; }
function run(f,args,extra={},expectOK=true,input=password) {
    const e=env(f,extra); delete e.STATE_DIR;
    const r=cp.spawnSync(shell,[path.join(f.repo,'bin/crouter'),'migrate',...args,'--password-stdin'],{env:e,input,encoding:'utf8'});
    assert(expectOK ? r.status===0 : r.status!==0,'unexpected migration status: '+r.stdout+r.stderr);
    return r;
}
try {
    const provider=`PROVIDER_NAME='demo'\nBASE_URL='https://api.example.invalid/custom'\nMODEL='test-model'\nAUTH_MODE='surfaces'\nPLAN_URL='https://plan.example.invalid/custom'\nPLAN_AUTH_TYPE='bearer'\nPLAN_KEYS='demo-plan'\nAPI_URL="\${CUSTOM_ENDPOINT:-https://api.example.invalid/custom}"\nAPI_AUTH_TYPE='x-api-key'\nAPI_KEY_ENV='DEMO_API_KEY'\nif [ -z "\${DEMO_API_KEY:-}" ]; then export DEMO_API_KEY="\$ALIAS_API_KEY"; fi\nAPI_KEYS='demo-api'\nPRE_START='touch ${path.join(tmp,'HOOK-RAN')}'\n`;
    put(path.join(source.repo,'providers/demo.local.sh'),provider);
    put(path.join(source.repo,'providers/literal.sh'),"BASE_URL='https://literal.invalid'\nMODEL='literal'\nAUTH_MODE='env'\nAUTH_REFERENCE='LITERAL_API_KEY'\n");
    put(path.join(source.repo,'providers/unconfigured.sh'),"BASE_URL='https://unused.invalid'\nMODEL='unused'\nAUTH_MODE='keychain'\nAUTH_REFERENCE='unused-missing'\n");
    put(path.join(source.repo,'config.sh'),`# all bytes are preserved\nexport LITERAL_API_KEY='literal$HOME\\key'\nBYPASS_PERMISSIONS=1\nSTATE_DIR='${source.repo}/private-state'\nCLAUDE_BIN='${source.home}/bin/claude'\ntouch '${path.join(tmp,'CONFIG-RAN')}'\n`);
    put(path.join(source.repo,'private-state/keypools/demo.local.tsv'),'api\tdemo-extra\n');
    put(path.join(source.home,'state/crouter/selection'),'demo.local\n');
    put(path.join(source.home,'state/crouter/last-model-demo.local'),'test-model:latest\n');
    for (const [k,v] of [['demo-plan',secret],['demo-api','key-api'],['demo-extra','key-extra']]) put(path.join(source.keys,k),v);
    const archive=path.join(tmp,'migration.crm');
    const exportOutput=run(source,['export',archive],{DEMO_API_KEY:'env-quote-\'"-\\-\nline', CUSTOM_ENDPOINT:'https://custom.example.invalid', ALIAS_API_KEY:'alias-only'});
    assert(!fs.existsSync(path.join(tmp,'CONFIG-RAN'))&&!fs.existsSync(path.join(tmp,'HOOK-RAN')),'export executed source');
    assert(!fs.readFileSync(archive).includes(Buffer.from(secret)),'encrypted archive leaked key');
    assert((fs.statSync(archive).mode&0o777)===0o600,'archive mode');
    run(source,['export',archive],{},false);
    // Wrong passwords and authenticated corruption cannot create destination state.
    run(target,['import',archive,'--yes'],{},false,'incorrect-passphrase');
    assert(!fs.existsSync(path.join(target.repo,'.state')),'bad password created state');
    const damaged=path.join(tmp,'damaged.crm'),bytes=fs.readFileSync(archive); bytes[bytes.length-1]^=1; fs.writeFileSync(damaged,bytes);
    run(target,['import',damaged,'--yes'],{},false);
    assert(!fs.existsSync(path.join(target.repo,'.state')),'tampering created state');
    // A colliding Keychain item is backed up; failure restores ALL touched keys.
    put(path.join(target.keys,'demo-plan'),'old-plan'); put(path.join(target.repo,'config.sh'),'# original target\n');
    run(target,['import',archive,'--yes'],{FAIL_SERVICE:'demo-api'},false);
    assert(fs.readFileSync(path.join(target.keys,'demo-plan'),'utf8')==='old-plan','rollback lost old key');
    assert(!fs.existsSync(path.join(target.keys,'demo-api')),'rollback left new key');
    assert(fs.readFileSync(path.join(target.repo,'config.sh'),'utf8')==='# original target\n','rollback changed config');
    const imported=run(target,['import',archive,'--yes']);
    assert(imported.stdout.includes('permission bypass'),'permission state was silent');
    for (const k of ['demo-plan','demo-api','demo-extra']) assert(fs.readFileSync(path.join(target.keys,k),'utf8')===fs.readFileSync(path.join(source.keys,k),'utf8'),'key changed');
    const config=fs.readFileSync(path.join(target.repo,'config.sh'),'utf8');
    assert(config.includes(target.home)&&config.includes(target.repo)&&!config.includes(source.home)&&!config.includes(source.repo),'root/home rebase');
    assert(fs.readFileSync(path.join(target.repo,'providers/demo.local.sh'),'utf8')===provider,'provider/header/endpoint binding changed');
    assert(fs.readFileSync(path.join(target.repo,'.state/keypools/demo.local.tsv'),'utf8')==='api\tdemo-extra\n','registry binding');
    assert(fs.readFileSync(path.join(target.home,'state/crouter/selection'),'utf8')==='demo.local\n','selection');
    assert(!fs.existsSync(path.join(tmp,'CONFIG-RAN'))&&!fs.existsSync(path.join(tmp,'HOOK-RAN')),'import executed source');
    const envFile=path.join(target.repo,'.state/migration-env.sh');
    const restoredEnv=cp.spawnSync('sh',['-c','. "$1"; printf "%s" "$DEMO_API_KEY"','test',envFile],{env:{PATH:process.env.PATH},encoding:'utf8'});
    const restoredMetadata=JSON.parse(fs.readFileSync(path.join(target.repo,'.state/migration-environment.json')));
    assert(restoredMetadata.LITERAL_API_KEY==='literal$HOME\\key','single-quoted credential expanded');
    assert(restoredMetadata.CUSTOM_ENDPOINT==='https://custom.example.invalid'&&restoredMetadata.ALIAS_API_KEY==='alias-only','endpoint/alias environment lost');
    assert(restoredEnv.stdout==='env-quote-\'"-\\-\nline','quoted/multiline env changed');
    assert((fs.statSync(envFile).mode&0o777)===0o600,'secret environment mode');
    const verified=run(target,['verify',archive]);
    assert(verified.stdout.includes('all match.'),'installed configuration/credential verification');
    const originalEnvShell=fs.readFileSync(envFile);
    fs.unlinkSync(envFile);
    const missingLoader=run(target,['verify',archive],{},false);
    assert(missingLoader.stdout.includes('environment loader'),'missing runtime environment loader passed verification');
    put(envFile,originalEnvShell);
    put(path.join(target.keys,'demo-api'),'incorrect-target-key');
    const wrongKey=run(target,['verify',archive],{},false);
    assert(wrongKey.stdout.includes('credential: demo-api')&&wrongKey.stdout.includes('demo.local'),'verify did not identify credential/provider');
    put(path.join(target.keys,'demo-api'),'key-api');
    const wrongCheckout=fixture('wrong-checkout');
    const missing=run(wrongCheckout,['verify',archive],{},false);
    assert(missing.stdout.includes('file: root/config.sh'),'wrong checkout was not detected');
    // A native writer can acknowledge a write without persisting it. Readback
    // must fail the transaction and restore the previously touched keys.
    const discarded=fixture('discarded');
    const discardedResult=run(discarded,['import',archive,'--yes'],{DROP_SERVICE:'demo-api'},false);
    assert(!discardedResult.stdout.includes('Imported.'),'silent native discard reported success');
    assert(fs.readdirSync(discarded.keys).length===0,'readback failure left partial credentials');
    assert(!fs.existsSync(path.join(discarded.repo,'config.sh')),'readback failure changed configuration');
    for (const [name,extra] of [['wrong-native-value',{WRONG_SERVICE:'demo-api'}],['missing-native-metadata',{METADATA_FAIL_SERVICE:'demo-api'}]]) {
        const broken=fixture(name);
        run(broken,['import',archive,'--yes'],extra,false);
        assert(fs.readdirSync(broken.keys).length===0&&!fs.existsSync(path.join(broken.repo,'config.sh')),'native verification failure was not rolled back');
    }
    // Explicit portable mode avoids ALL native Keychain calls on a host where
    // both security and expect are present, and normal verification works.
    const forced=fixture('forced-portable');
    const previousCalls=fs.readFileSync(path.join(tmp,'argv.log'),'utf8');
    const forcedResult=run(forced,['import',archive,'--yes','--portable']);
    assert(forcedResult.stdout.includes('Keychain is neither read nor written'),'portable mode was not explicit');
    assert(fs.readFileSync(path.join(tmp,'argv.log'),'utf8')===previousCalls&&fs.readdirSync(forced.keys).length===0,'portable import accessed native Keychain');
    run(forced,['verify',archive,'--portable']);
    assert(fs.readFileSync(path.join(tmp,'argv.log'),'utf8')===previousCalls,'portable verify accessed native Keychain');
    const forcedStore=JSON.parse(fs.readFileSync(path.join(forced.repo,'.state/migration-credentials.json')));
    assert(forcedStore['demo-plan']===secret,'forced portable key changed');
    assert((fs.statSync(path.join(forced.repo,'.state/migration-credentials.json')).mode&0o777)===0o600,'forced portable credential mode');
    forcedStore['demo-api']='wrong-portable-key';
    put(path.join(forced.repo,'.state/migration-credentials.json'),JSON.stringify(forcedStore));
    run(forced,['verify',archive,'--portable'],{},false);
    assert(!fs.existsSync(path.join(tmp,'CONFIG-RAN'))&&!fs.existsSync(path.join(tmp,'HOOK-RAN')),'verify executed imported source');
    assert(!fs.readFileSync(path.join(tmp,'argv.log'),'utf8').includes(secret),'secret reached security argv');
    assert(!exportOutput.stdout.includes(secret)&&!imported.stdout.includes(secret),'secret in summary');
    // Missing a registered key is an error, unlike an unused catalog slot.
    fs.unlinkSync(path.join(source.keys,'demo-extra'));
    run(source,['export',path.join(tmp,'missing.crm')],{},false);
    assert(!fs.existsSync(path.join(tmp,'missing.crm')),'incomplete export wrote archive');
    put(path.join(source.keys,'demo-extra'),'key-extra');
    fs.unlinkSync(path.join(source.repo,'private-state/keypools/demo.local.tsv'));
    fs.unlinkSync(path.join(source.keys,'demo-plan')); fs.unlinkSync(path.join(source.keys,'demo-api'));
    run(source,['export',path.join(tmp,'alias-only.crm')],{ALIAS_API_KEY:'only-alias'});
    const dynamic=fixture('dynamic');put(path.join(dynamic.repo,'config.sh'),"STATE_DIR=$(printf '%s' /not-evaluated)\n");
    run(dynamic,['export',path.join(tmp,'dynamic.crm')],{},false);
    run(dynamic,['export',path.join(tmp,'dynamic-override.crm'),'--state-dir',path.join(dynamic.home,'explicit-state')]);
    const alias=fixture('builtin-alias');fs.copyFileSync(path.join(root,'providers/dashscope.sh'),path.join(alias.repo,'providers/dashscope.sh'));
    put(path.join(alias.home,'state/crouter/selection'),'dashscope\n');
    run(alias,['export',path.join(tmp,'builtin-alias.crm')],{ALIBABA_API_KEY:'real-builtin-alias',DASHSCOPE_API_URL:'https://workspace.example.invalid/apps/anthropic'});
    // Destination links are rejected before ANY Keychain writes or source writes.
    const linked=fixture('linked'); fs.symlinkSync(path.join(tmp,'outside-config'),path.join(linked.repo,'config.sh'));
    run(linked,['import',archive,'--yes'],{},false);
    assert(fs.readdirSync(linked.keys).length===0,'linked destination wrote keys');
    // Authenticate malicious manifests with the known TEST password to prove
    // schema validation, rather than relying only on AEAD failure.
    function mutate(fn,name) {
        const encrypted=fs.readFileSync(archive), n=18;
        const salt=encrypted.subarray(n,n+16),iv=encrypted.subarray(n+16,n+28),tag=encrypted.subarray(n+28,n+44);
        const key=crypto.scryptSync(password,salt,32,{N:32768,r:8,p:1,maxmem:64*1024*1024});
        const d=crypto.createDecipheriv('aes-256-gcm',key,iv);d.setAAD(encrypted.subarray(0,n));d.setAuthTag(tag);
        const p=JSON.parse(Buffer.concat([d.update(encrypted.subarray(n+44)),d.final()]));fn(p);
        const c=crypto.createCipheriv('aes-256-gcm',key,iv);c.setAAD(encrypted.subarray(0,n));
        const data=Buffer.concat([c.update(JSON.stringify(p)),c.final()]);
        const file=path.join(tmp,name+'.crm');fs.writeFileSync(file,Buffer.concat([encrypted.subarray(0,n+28),c.getAuthTag(),data]));return file;
    }
    for (const [name,fn] of [['traversal',p=>p.files[0].name='../escape'],['duplicate',p=>p.files.push(p.files[0])],['duplicate-key',p=>p.keys.push(p.keys[0])],['nul-key',p=>p.keys[0].value='a\x00b']]) {
        const bad=fixture(name);run(bad,['import',mutate(fn,name),'--yes'],{},false);assert(!fs.existsSync(path.join(bad.repo,'.state')),'invalid payload wrote state');
    }
    // Host without security(1): simulate with a tiny PATH, keeping Node + sh.
    const portable=fixture('portable'),bare=path.join(tmp,'bare');fs.mkdirSync(bare);
    for (const [name,exe] of [['node',process.execPath],['sh','/bin/sh'],['dirname','/usr/bin/dirname'],['cat','/bin/cat'],['rm','/bin/rm'],['awk','/usr/bin/awk'],['chmod','/bin/chmod'],['mv','/bin/mv']]) fs.symlinkSync(exe,path.join(bare,name));
    const r=run(portable,['import',archive,'--yes'],{PATH:bare});
    assert(r.stdout.includes('fallback'),'non-Mac fallback not reported');
    const store=JSON.parse(fs.readFileSync(path.join(portable.repo,'.state/migration-credentials.json')));
    assert(store['demo-plan']===secret,'portable key changed');
    const getter=cp.spawnSync(process.execPath,[path.join(portable.repo,'lib/device-migration.js'),portable.repo,'_get','demo-plan'],{encoding:'utf8'});
    assert(getter.stdout===secret,'fallback runtime key lookup');
    // Roundtrip a newline key in the portable store, even with an old native item.
    store['demo-plan']='line one\nline two\n';put(path.join(portable.repo,'.state/migration-credentials.json'),JSON.stringify(store));
    put(path.join(portable.keys,'demo-plan'),'stale-native');
    const second=path.join(tmp,'second.crm');run(portable,['export',second],{PATH:bare});
    const final=fixture('final');run(final,['import',second,'--yes']);
    const multiline=JSON.parse(fs.readFileSync(path.join(final.repo,'.state/migration-credentials.json')));
    assert(multiline['demo-plan']==='line one\nline two\n','multiline key roundtrip');
    put(path.join(portable.repo,'config.sh'),'# no executable fixture source\n');
    const removeEnv=env(portable,{PATH:bare,NODE_BIN:process.execPath});delete removeEnv.STATE_DIR;
    const removed=cp.spawnSync(shell,[path.join(portable.repo,'bin/crouter'),'remove','demo.local','--surface','plan','--name','demo-plan','-y'],{env:removeEnv,encoding:'utf8'});
    assert(removed.status===0,'fallback remove failed: '+removed.stderr);
    assert(!Object.hasOwn(JSON.parse(fs.readFileSync(path.join(portable.repo,'.state/migration-credentials.json'))),'demo-plan'),'fallback remove retained key');
    console.log('ok    encrypted migration: exact credentials, endpoints, state, rebase, no execution, wrong password/tamper, rollback, links, schema, portable fallback, native readback, installed verification');
} finally { fs.rmSync(tmp,{recursive:true,force:true}); }
JS

if command -v python3 >/dev/null 2>&1; then
    python3 "$ROOT_DIR/test/device-migration-tty.py"
fi
