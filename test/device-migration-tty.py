"""Exercise the default hidden UTF-8 passphrase flow in an isolated real PTY."""
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import tempfile
import time


with tempfile.TemporaryDirectory(prefix="crouter-migration-tty-") as directory:
    temporary = Path(directory).resolve()
    project = Path(os.environ["ROOT_DIR"])

    def fixture(name: str) -> tuple[Path, dict[str, str]]:
        repo, home = temporary / name / "repo", temporary / name / "home"
        repo.mkdir(parents=True)
        home.mkdir()
        for part in ("bin", "lib"):
            shutil.copytree(project / part, repo / part)
        (repo / "providers").mkdir()
        (repo / "providers/demo.sh").write_text(
            "BASE_URL='https://offline.invalid'\nMODEL='demo'\nAUTH_MODE='none'\n"
        )
        environment = dict(os.environ, HOME=str(home), XDG_STATE_HOME=str(home / "state"))
        environment.pop("STATE_DIR", None)
        return repo, environment

    source, source_env = fixture("source")
    target, target_env = fixture("target")
    archive = temporary / "unicode.crm"
    password = "中文迁移🔑口令验证abcdefghijklmnopqrstuvwxyz"
    pid, master = pty.fork()
    if pid == 0:
        os.execve("/bin/sh", ["sh", str(source / "bin/crouter"), "migrate", "export", str(archive)], source_env)
    output, sent = b"", 0
    reaped = False
    try:
        deadline = time.monotonic() + 25
        while time.monotonic() < deadline:
            if select.select([master], [], [], 0.2)[0]:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                output += chunk
                if sent == 0 and b"Migration passphrase:" in output:
                    os.write(master, password.encode() + b"\n")
                    sent = 1
                if sent == 1 and b"Repeat passphrase:" in output:
                    os.write(master, password.encode() + b"\n")
                    sent = 2
            child, status = os.waitpid(pid, os.WNOHANG)
            if child:
                reaped = True
                assert status == 0, "interactive export failed"
                break
        assert archive.exists() and sent == 2, "interactive passphrase flow stalled"
        assert password.encode() not in output, "terminal echoed the passphrase"
        result = subprocess.run(
            ["/bin/sh", str(target / "bin/crouter"), "migrate", "import", str(archive), "--yes", "--password-stdin"],
            env=target_env, input=password + "\n", capture_output=True, text=True, timeout=20,
        )
        assert result.returncode == 0, "interactive UTF-8 password differed from stdin password"
        print("ok    hidden PTY Chinese/emoji passphrase exports twice and imports through stdin")
    finally:
        if not reaped:
            child, _ = os.waitpid(pid, os.WNOHANG)
            if not child:
                os.kill(pid, 15)
                os.waitpid(pid, 0)
        os.close(master)
