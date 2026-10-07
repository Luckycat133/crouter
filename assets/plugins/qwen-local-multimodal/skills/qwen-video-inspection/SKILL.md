---
name: qwen-video-inspection
description: Inspect a local video or image with the active Qwen3.8 MLX-VLM session. Use when the user supplies an image/video path or asks Claude Code to look at visual media.
allowed-tools: Bash, Read
---

# Qwen local visual inspection

Images are native inputs for this session. Use the Read tool on the image file and base claims on visible content.

Claude Code does not send an MP4 as a native Anthropic video block. When the user supplies a video path, call the bundled native bridge first. It sends the file to the active MLX-VLM server as an OpenAI-compatible `video_url` content block, so Qwen3.8 uses its video processor:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/qwen-video-inspection/scripts/analyze_video_native.py" "/absolute/path/to/video.mp4" --prompt "Describe the video and answer the user's question."
```

Base the answer on the bridge output. Do not also read extracted frames when the native request succeeds.

If the native bridge exits non-zero, use the bundled storyboard fallback before answering:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/qwen-video-inspection/scripts/extract_video_storyboard.sh" "/absolute/path/to/video.mp4" "/tmp/qwen-video-review" 16
```

Read `storyboard-001.jpg` first. Then read individual frames from the same output directory when a detail, transition, object, or timestamp needs closer inspection. For videos longer than ten minutes, start with 24–32 frames; refine only the relevant interval instead of extracting every frame.

Treat storyboard coverage as sampled visual evidence and state that fallback was used. Neither path proves audio content or frame-perfect timing. If audio or exact transition timing matters, inspect it with appropriate local tools and say what was actually checked.
