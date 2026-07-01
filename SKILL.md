---
name: bilibili-ai-subtitle
description: "Download Bilibili AI-generated subtitles and produce clean transcript files. Use when the user provides a Bilibili URL, BV ID, or AV ID and asks for subtitles, transcript text, timestamped transcript, txt/md output, or optional faster-whisper ASR fallback when no AI subtitles are available. Supports language priority for Chinese, English, Japanese, Spanish, Arabic, Portuguese, Korean, German, and French."
---

# Bilibili AI Subtitle Downloader v2.1

Download Bilibili `ai-*` auto-subtitles, clean them into readable transcript text, and write a structured output file.

## Core Workflow

Use the helper script first:

```bash
./scripts/bilibili_ai_subtitle.sh "https://www.bilibili.com/video/BVxxxxx/"
```

The script will:

- Accept a Bilibili URL, BV ID, or AV ID.
- Fetch video metadata with `yt-dlp`.
- Detect available Bilibili AI subtitle tracks.
- Select the first matching language from the priority list.
- Download and convert subtitles to a parseable format.
- Write a structured `.txt` or `.md` transcript with video info, content preview, and full text.

## Common Commands

```bash
# Prefer English, fallback to Chinese
./scripts/bilibili_ai_subtitle.sh -l en,zh "BVxxxxx"

# Preserve timestamps in the transcript
./scripts/bilibili_ai_subtitle.sh --timestamps "BVxxxxx"

# Use browser cookies explicitly
./scripts/bilibili_ai_subtitle.sh --cookies-from-browser chrome "BVxxxxx"

# Use a cookies.txt file
./scripts/bilibili_ai_subtitle.sh -c /path/to/cookies.txt "BVxxxxx"

# Markdown output and keep the converted subtitle file
./scripts/bilibili_ai_subtitle.sh --format md --keep-srt "BVxxxxx"

# No AI subtitles: optionally download audio and transcribe with faster-whisper
./scripts/bilibili_ai_subtitle.sh --asr-fallback --asr-language zh "BVxxxxx"
```

## Supported AI Subtitle Languages

Bilibili uses an `ai-` prefix for AI-generated subtitles:

| Code | Language |
|------|----------|
| `ai-zh` | Chinese |
| `ai-en` | English |
| `ai-ja` | Japanese |
| `ai-es` | Spanish |
| `ai-ar` | Arabic |
| `ai-pt` | Portuguese |
| `ai-ko` | Korean |
| `ai-de` | German |
| `ai-fr` | French |

Default priority:

```text
zh,en,ja,es,ar,pt,ko,de,fr
```

## Cookie Handling

- If `--cookies FILE` is provided, use that cookies file.
- If `--cookies-from-browser NAME` is provided, use that browser profile through `yt-dlp`.
- If neither is provided, try without cookies first. When metadata or AI subtitle detection fails, the script can automatically try common browsers: `chrome,chromium,edge,safari,firefox`.
- Use `--no-browser-cookies` to disable automatic browser-cookie attempts.

## ASR Fallback

The main path is still Bilibili AI subtitles. If no matching AI subtitle exists, the script exits with guidance unless `--asr-fallback` is set.

When `--asr-fallback` is set, the script downloads audio with `yt-dlp` and transcribes it with `faster-whisper`. This requires:

```bash
python3 -m pip install faster-whisper
```

Use `--asr-language auto` to let Whisper detect language, or pass a language such as `zh`, `en`, or `ja`.

For complex multi-part videos where per-P audio and combined Markdown files are needed, consult `references/no-ai-subtitle-fallback.md`.

## Output

Default file name:

```text
VideoTitle_Author_Date_Duration_BVid.txt
```

The document contains:

```text
第一部分：视频信息
第二部分：内容预览
第三部分：完整原文
```

Use `--format md` for Markdown output. Use `--timestamps` when the full transcript should retain `[HH:MM:SS]` markers.

## Requirements

- Required: `yt-dlp`, `python3`
- Recommended: `ffmpeg`
- Only for `--asr-fallback`: `faster-whisper`

Report clearly whether the final transcript came from Bilibili AI subtitles or audio ASR. ASR output may contain recognition errors.
