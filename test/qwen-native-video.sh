#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
HELPER="$ROOT/assets/plugins/qwen-local-multimodal/skills/qwen-video-inspection/scripts/analyze_video_native.py"
TMPDIR_QWEN=$(mktemp -d)
trap 'rm -rf "$TMPDIR_QWEN"' EXIT HUP INT TERM

VIDEO="$TMPDIR_QWEN/video sample.mp4"
PORT_FILE="$TMPDIR_QWEN/port"
CAPTURE="$TMPDIR_QWEN/request.json"
EVIDENCE="$TMPDIR_QWEN/evidence.json"
: >"$VIDEO"

python3 - "$PORT_FILE" "$CAPTURE" <<'PY' &
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

port_file, capture = sys.argv[1:]

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        size = int(self.headers.get("content-length", "0"))
        body = json.loads(self.rfile.read(size))
        with open(capture, "w", encoding="utf-8") as handle:
            json.dump(body, handle)
        payload = json.dumps({
            "choices": [{"message": {"content": "red|green|blue"}}],
            "usage": {"prompt_tokens": 42, "completion_tokens": 5},
        }).encode()
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *_args):
        pass

server = HTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w", encoding="utf-8") as handle:
    handle.write(str(server.server_port))
server.handle_request()
PY
MOCK_PID=$!

i=0
while [ ! -s "$PORT_FILE" ]; do
  i=$((i + 1))
  [ "$i" -lt 100 ] || { echo "mock server did not start" >&2; exit 1; }
  sleep 0.02
done

OUTPUT=$(python3 "$HELPER" "$VIDEO" \
  --base-url "http://127.0.0.1:$(cat "$PORT_FILE")" \
  --prompt "List the colors." \
  --evidence "$EVIDENCE")
wait "$MOCK_PID"
[ "$OUTPUT" = "red|green|blue" ]

python3 - "$CAPTURE" "$EVIDENCE" "$VIDEO" <<'PY'
import json
import pathlib
import sys

capture, evidence, video = map(pathlib.Path, sys.argv[1:])
request = json.loads(capture.read_text())
content = request["messages"][0]["content"]
assert content[0]["type"] == "video_url"
assert content[0]["video_url"]["url"] == video.resolve().as_uri()
assert content[1] == {"type": "text", "text": "List the colors."}
assert request["stream"] is False
proof = json.loads(evidence.read_text())
assert proof["status"] == "success"
assert proof["transport"] == "video_url"
assert proof["usage"]["prompt_tokens"] == 42
PY

if python3 "$HELPER" "$TMPDIR_QWEN/missing.mp4" --prompt nope >/dev/null 2>&1; then
  echo "missing video unexpectedly succeeded" >&2
  exit 1
fi

echo "qwen native video bridge: ok"
