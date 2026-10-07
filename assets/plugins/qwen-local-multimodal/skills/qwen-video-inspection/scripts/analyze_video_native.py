#!/usr/bin/env python3
"""Send a local video to the active Qwen3.8 MLX-VLM OpenAI endpoint."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser()
    value.add_argument("video", type=Path)
    value.add_argument("--prompt", required=True)
    value.add_argument(
        "--base-url",
        default=os.environ.get("MLX_VLM_BASE_URL", "http://10.211.55.2:18080"),
    )
    value.add_argument(
        "--model",
        default=os.environ.get("QWEN_VLM_MODEL", "qwen3.8-27b"),
    )
    value.add_argument("--max-tokens", type=int, default=1024)
    value.add_argument("--timeout", type=int, default=1800)
    value.add_argument("--evidence", type=Path)
    return value


def write_evidence(path: Path | None, payload: dict[str, object]) -> None:
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
    temporary.replace(path)


def main() -> int:
    args = parser().parse_args()
    video = args.video.expanduser().resolve()
    if not video.is_file():
        print(f"video not found: {video}", file=sys.stderr)
        return 2
    if args.max_tokens < 1 or args.max_tokens > 8192:
        print("--max-tokens must be between 1 and 8192", file=sys.stderr)
        return 2
    if args.timeout < 1:
        print("--timeout must be positive", file=sys.stderr)
        return 2

    endpoint = args.base_url.rstrip("/") + "/v1/chat/completions"
    body = {
        "model": args.model,
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "video_url", "video_url": {"url": video.as_uri()}},
                    {"type": "text", "text": args.prompt},
                ],
            }
        ],
        "temperature": 0.0,
        "max_tokens": args.max_tokens,
        "stream": False,
    }
    request = urllib.request.Request(
        endpoint,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    evidence: dict[str, object] = {
        "schema_version": 1,
        "status": "failed",
        "transport": "video_url",
        "endpoint": endpoint,
        "model": args.model,
        "video": str(video),
        "video_uri": video.as_uri(),
    }
    try:
        with urllib.request.urlopen(request, timeout=args.timeout) as response:
            payload = json.load(response)
        message = payload["choices"][0]["message"]
        answer = message.get("content") or message.get("reasoning_content") or message.get("reasoning")
        if not isinstance(answer, str) or not answer.strip():
            raise ValueError("MLX-VLM response did not contain text")
        evidence.update({"status": "success", "usage": payload.get("usage", {})})
        write_evidence(args.evidence, evidence)
        print(answer.strip())
        return 0
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, ValueError, KeyError, json.JSONDecodeError) as exc:
        evidence["error"] = f"{type(exc).__name__}: {exc}"
        write_evidence(args.evidence, evidence)
        print(f"native video request failed: {exc}", file=sys.stderr)
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
