# bilibili-ai-subtitle

Bilibili AI subtitle downloader and transcript exporter.

This project downloads Bilibili `ai-*` auto-subtitles, cleans them into readable text, and writes a structured `.txt` or `.md` transcript. It can also fall back to audio transcription with `faster-whisper` when a video has no matching AI subtitle track.

## Features

- Accepts Bilibili URLs, BV IDs, and AV IDs.
- Detects available Bilibili AI subtitle tracks.
- Supports language priority: Chinese, English, Japanese, Spanish, Arabic, Portuguese, Korean, German, and French.
- Exports clean transcript text as `.txt` or `.md`.
- Optional timestamp preservation.
- Optional browser-cookie support through `yt-dlp`.
- Optional ASR fallback with `faster-whisper`.
- Can be used as a standalone shell tool or as a Codex skill.

## Requirements

Required:

- `bash`
- `python3`
- `yt-dlp`

Recommended:

- `ffmpeg`

Optional, only for `--asr-fallback`:

- `faster-whisper`

## Install Dependencies

macOS with Homebrew:

```bash
brew install yt-dlp ffmpeg
```

Optional ASR fallback:

```bash
python3 -m pip install faster-whisper
```

If your Python is externally managed, create a virtual environment first:

```bash
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install faster-whisper
```

## Usage

Basic:

```bash
./scripts/bilibili_ai_subtitle.sh "https://www.bilibili.com/video/BVxxxxx/"
```

Prefer English, then Chinese:

```bash
./scripts/bilibili_ai_subtitle.sh -l en,zh "BVxxxxx"
```

Keep timestamps:

```bash
./scripts/bilibili_ai_subtitle.sh --timestamps "BVxxxxx"
```

Write Markdown:

```bash
./scripts/bilibili_ai_subtitle.sh --format md "BVxxxxx"
```

Use browser cookies:

```bash
./scripts/bilibili_ai_subtitle.sh --cookies-from-browser chrome "BVxxxxx"
```

Use a cookies file:

```bash
./scripts/bilibili_ai_subtitle.sh -c /path/to/cookies.txt "BVxxxxx"
```

Fallback to audio transcription when no AI subtitle exists:

```bash
./scripts/bilibili_ai_subtitle.sh --asr-fallback --asr-language zh "BVxxxxx"
```

Show all options:

```bash
./scripts/bilibili_ai_subtitle.sh --help
```

## Output

By default, transcripts are written to:

```text
~/.openclaw/workspace/Bilibili transcript
```

You can pass an output directory as the final positional argument or use `--output-dir`:

```bash
./scripts/bilibili_ai_subtitle.sh "BVxxxxx" "./output"
./scripts/bilibili_ai_subtitle.sh --output-dir "./output" "BVxxxxx"
```

The generated document contains:

```text
第一部分：视频信息
第二部分：内容预览
第三部分：完整原文
```

## Codex Skill

This repository can also be used as a Codex skill because `SKILL.md` lives at the repository root.

To install manually, copy or symlink this folder into your Codex skills directory:

```bash
ln -s /path/to/bilibili-ai-subtitle "$CODEX_HOME/skills/bilibili-ai-subtitle"
```

Then restart Codex.

## Notes

- This tool downloads Bilibili AI-generated subtitles, not manually uploaded creator captions.
- Some videos do not expose AI subtitle tracks.
- Member-only or region-limited videos may require cookies.
- ASR fallback is slower and may contain recognition errors.
- For complex multi-part videos, see `references/no-ai-subtitle-fallback.md`.

## License

All rights reserved unless you replace `LICENSE` with an open-source license.
