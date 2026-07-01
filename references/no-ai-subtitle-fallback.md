# Bilibili videos with no AI subtitles: audio-transcription fallback

Use this when the Bilibili subtitle API / `yt-dlp --list-subs` returns no `ai-*` subtitles, but the user still wants a transcript.

## Key observations

- Some Bilibili multi-part videos have no subtitle tracks at all (`subtitles_count: 0`) but the audio streams are available through Bilibili player APIs.
- For multi-P videos, one BVID can contain many `pages`; each page has its own `cid` and should become its own transcript section/file.
- If `yt-dlp` hits Bilibili HTTP 412, direct Bilibili APIs with browser-like headers can still work.

## Workflow

1. Fetch metadata and pages:

```python
import json, urllib.request
bvid = "BV..."
headers = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
    "Referer": f"https://www.bilibili.com/video/{bvid}/",
}
req = urllib.request.Request(
    f"https://api.bilibili.com/x/web-interface/view?bvid={bvid}",
    headers=headers,
)
view = json.loads(urllib.request.urlopen(req, timeout=30).read().decode())["data"]
for page in view["pages"]:
    print(page["page"], page["part"], page["cid"])
```

2. For each `cid`, fetch audio URL:

```python
url = f"https://api.bilibili.com/x/player/playurl?bvid={bvid}&cid={cid}&qn=16&fnval=16&fourk=0"
req = urllib.request.Request(url, headers=headers)
data = json.loads(urllib.request.urlopen(req, timeout=30).read().decode())["data"]
audios = (data.get("dash") or {}).get("audio") or []
audio_url = sorted(audios, key=lambda x: x.get("bandwidth", 0))[0]["baseUrl"]
```

3. Download audio with the same headers. Save one audio file per page.

4. Transcribe with `faster-whisper` if available, or install it when appropriate:

```bash
python3 -m pip install --user faster-whisper
```

Example transcription loop:

```python
from faster_whisper import WhisperModel
model = WhisperModel("small", device="cpu", compute_type="int8")
segments, info = model.transcribe(audio_file, language="zh", beam_size=1, vad_filter=True)
for seg in segments:
    print(f"[{seg.start:.1f} - {seg.end:.1f}] {seg.text.strip()}")
```

5. Emit:
   - one combined Markdown transcript with `## Pxx title` sections;
   - optionally one file per P for easier reading;
   - an index/README with links to each part.

## Verification

Before reporting success, verify:

```bash
python3 - <<'PY'
from pathlib import Path
for p in Path('/path/to/output').glob('*.md'):
    text = p.read_text(encoding='utf-8')
    print(p.name, 'lines', len(text.splitlines()), 'chars', len(text))
PY
```

Report clearly whether the transcript came from Bilibili subtitles or from audio ASR; ASR output may contain recognition errors.
