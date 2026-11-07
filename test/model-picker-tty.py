#!/usr/bin/env python3
"""Bounded PTY driver; reports the child status for shell assertions."""
import argparse, os, pty, select, signal, subprocess, sys, time
p=argparse.ArgumentParser()
p.add_argument('--timeout',type=float,default=20)
p.add_argument('--eof-after',type=float)
p.add_argument('--hangup-after',type=float)
p.add_argument('--stdin')
p.add_argument('--keys',default='')
p.add_argument('command',nargs=argparse.REMAINDER)
a=p.parse_args(); cmd=a.command[1:] if a.command and a.command[0]=='--' else a.command
if not cmd: p.error('command required')
m,s=pty.openpty(); fin=open(a.stdin,'rb') if a.stdin else None
proc=subprocess.Popen(cmd,stdin=fin or s,stdout=s,stderr=s,close_fds=True)
os.close(s)
if fin: fin.close()
if a.keys: os.write(m,a.keys.encode())
start=time.monotonic(); chunks=[]; hung=False; closed=False; timed=False
try:
    while True:
        age=time.monotonic()-start
        if age>a.timeout: timed=True; break
        if a.hangup_after is not None and age>=a.hangup_after and not hung:
            hung=True
            if proc.poll() is None: proc.send_signal(signal.SIGHUP)
        if a.eof_after is not None and age>=a.eof_after and not closed:
            os.close(m);closed=True
            break
        readable,_,_=select.select([m],[],[],0.1)
        if readable:
            try: data=os.read(m,65536)
            except OSError: break
            if not data: break
            chunks.append(data)
        elif proc.poll() is not None: break
    try: proc.wait(timeout=3)
    except subprocess.TimeoutExpired: timed=True;proc.kill();proc.wait()
finally:
    if proc.poll() is None: proc.kill();proc.wait()
    if not closed: os.close(m)
sys.stdout.write(b''.join(chunks).decode('utf-8','replace'))
print('\n[pty-helper] '+('TIMEOUT' if timed else 'exit='+str(proc.returncode)))
sys.exit(124 if timed else 0)
