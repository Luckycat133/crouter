#!/usr/bin/env python3
"""Drive an interactive command on a pseudo terminal.

The model picker needs a terminal on stdout and reads its keys from stdin, so a
plain pipe cannot exercise it. This helper gives the test four input kinds:

  keys        write bytes into the terminal (Esc, a filter character, ...)
  --stdin     give the child a file as stdin instead of the terminal, so the
              input stream ends without the terminal going away
  --eof-after close the terminal master, which the child sees as stdin EOF
  --timeout   kill the child and report a timeout instead of hanging the suite

The captured output is printed, followed by the exit code of the child, so the
caller can assert on both.
"""
from __future__ import annotations

import argparse
import os
import pty
import select
import signal
import subprocess
import sys
import time


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=20.0)
    parser.add_argument("--eof-after", type=float, default=None,
                        help="close the terminal master after this many seconds")
    parser.add_argument("--hangup-after", type=float, default=None,
                        help="send SIGHUP to the child after this many seconds")
    parser.add_argument("--stdin", default=None,
                        help="file used as the child's stdin instead of the terminal")
    parser.add_argument("--keys", default="",
                        help="bytes written to the terminal (\\x1b for Esc)")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    command = args.command
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        print("no command given", file=sys.stderr)
        return 2

    master, slave = pty.openpty()
    stdin_file = open(args.stdin, "rb") if args.stdin else None
    proc = subprocess.Popen(command, stdin=stdin_file if stdin_file else slave,
                            stdout=slave, stderr=slave, close_fds=True)
    if stdin_file is not None:
        stdin_file.close()
    os.close(slave)

    if args.keys:
        os.write(master, args.keys.encode())

    closed = False
    eof_deadline = None
    if args.eof_after is not None:
        eof_deadline = time.monotonic() + args.eof_after
    hangup_deadline = None
    if args.hangup_after is not None:
        hangup_deadline = time.monotonic() + args.hangup_after
    hangup_sent = False

    chunks = []
    deadline = time.monotonic() + args.timeout
    timed_out = False
    while True:
        if hangup_deadline is not None and not hangup_sent and time.monotonic() >= hangup_deadline:
            hangup_sent = True
            try:
                os.kill(proc.pid, signal.SIGHUP)
            except (OSError, ProcessLookupError):
                pass
        if eof_deadline is not None and not closed and time.monotonic() >= eof_deadline:
            closed = True
            try:
                os.close(master)
            except OSError:
                pass
        timeout = deadline - time.monotonic()
        if timeout <= 0:
            timed_out = True
            break
        try:
            readable, _, _ = select.select([master], [], [], min(timeout, 0.2))
        except OSError:
            break
        if readable:
            try:
                data = os.read(master, 65536)
            except OSError:
                break
            if not data:
                break
            chunks.append(data)
        elif proc.poll() is not None:
            # The child is gone; drain whatever is left in the terminal.
            try:
                while True:
                    data = os.read(master, 65536)
                    if not data:
                        break
                    chunks.append(data)
            except OSError:
                pass
            break

    if timed_out:
        proc.kill()
        proc.wait(timeout=5)
        sys.stdout.write(b"".join(chunks).decode("utf-8", "replace"))
        print("\n[pty-helper] TIMEOUT")
        return 124

    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)
    if not closed:
        try:
            os.close(master)
        except OSError:
            pass

    sys.stdout.write(b"".join(chunks).decode("utf-8", "replace"))
    sys.stdout.flush()
    print("\n[pty-helper] exit=%d" % proc.returncode)
    return 0


if __name__ == "__main__":
    sys.exit(main())
