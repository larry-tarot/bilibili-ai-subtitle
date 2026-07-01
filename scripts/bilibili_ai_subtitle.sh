#!/usr/bin/env bash
# Bilibili AI字幕下载脚本 v2.1
# 下载 B 站 AI 自动字幕；可选在无 AI 字幕时使用 faster-whisper 转写音频。

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="2.1"
DEFAULT_OUTPUT_DIR="${BILIBILI_SUBTITLE_OUTPUT_DIR:-$HOME/.openclaw/workspace/Bilibili transcript}"
YTDLP_BIN="${YTDLP_BIN:-yt-dlp}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

VIDEO_URL=""
OUTPUT_DIR=""
LANG_PRIORITY="zh,en,ja,es,ar,pt,ko,de,fr"
COOKIE_FILE=""
BROWSER_COOKIES=""
AUTO_BROWSER_COOKIES=1
AUTO_BROWSERS="chrome,chromium,edge,safari,firefox"
OUTPUT_FORMAT="txt"
WITH_TIMESTAMPS=0
KEEP_SRT=0
ASR_FALLBACK=0
ASR_LANGUAGE="zh"
WHISPER_MODEL="small"
FORCE=0

COOKIE_ARGS=()
COOKIE_SOURCE="无 Cookie"
TMP_DIR=""

log() { printf '%s\n' "$*"; }
info() { printf 'ℹ️  %s\n' "$*"; }
ok() { printf '✅ %s\n' "$*"; }
warn() { printf '⚠️  %s\n' "$*" >&2; }
die() { printf '❌ %s\n' "$*" >&2; exit 1; }

cleanup() {
    if [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

show_help() {
    cat << EOF
Bilibili AI字幕下载器 v${VERSION}

用法:
  $0 [选项] <B站视频链接|BV号|AV号> [输出目录]

常用选项:
  -l, --lang LANG_LIST              指定 AI 字幕语言优先级
                                    默认: zh,en,ja,es,ar,pt,ko,de,fr
  -o, --output-dir DIR              指定输出目录
  -c, --cookies FILE                指定 cookies.txt (Netscape 格式)
      --cookies-from-browser NAME   使用浏览器 Cookie，例如 chrome、edge、safari、firefox
      --no-browser-cookies          禁止自动尝试浏览器 Cookie
      --timestamps                  完整原文保留时间戳
      --keep-srt                    同时保留下载/转换后的字幕文件
      --format txt|md               输出格式，默认 txt
      --force                       输出文件已存在时直接覆盖

无 AI 字幕时的可选 fallback:
      --asr-fallback                没有 AI 字幕时下载音频并用 faster-whisper 转写
      --asr-language LANG           ASR 语言，默认 zh；可用 auto 自动识别
      --whisper-model MODEL         faster-whisper 模型，默认 small

依赖:
  必需: yt-dlp, python3
  建议: ffmpeg（字幕格式转换和 ASR 都会用到）
  仅 --asr-fallback 需要: faster-whisper

示例:
  $0 "https://www.bilibili.com/video/BVxxxxx/"
  $0 -l en,zh "BVxxxxx"
  $0 --cookies-from-browser chrome --timestamps "BVxxxxx"
  $0 --asr-fallback --asr-language zh "BVxxxxx" "./Bilibili transcript"

支持的 AI 语言:
  zh(中文), en(英文), ja(日文), es(西班牙文), ar(阿拉伯文),
  pt(葡萄牙文), ko(韩文), de(德文), fr(法文)
EOF
}

need_value() {
    local option="$1"
    local value="${2:-}"
    if [ -z "$value" ]; then
        die "$option 需要一个参数"
    fi
}

trim_spaces() {
    printf '%s' "$1" | tr -d '[:space:]'
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "缺少依赖：$1"
}

lang_name() {
    case "$1" in
        ai-zh|zh) printf '中文' ;;
        ai-en|en) printf '英文' ;;
        ai-ja|ja) printf '日文' ;;
        ai-es|es) printf '西班牙文' ;;
        ai-ar|ar) printf '阿拉伯文' ;;
        ai-pt|pt) printf '葡萄牙文' ;;
        ai-ko|ko) printf '韩文' ;;
        ai-de|de) printf '德文' ;;
        ai-fr|fr) printf '法文' ;;
        auto) printf '自动识别' ;;
        *) printf '%s' "$1" ;;
    esac
}

normalize_video_url() {
    local raw="$1"
    case "$raw" in
        BV*|bv*)
            printf 'https://www.bilibili.com/video/%s/' "$raw"
            ;;
        AV*|av*)
            printf 'https://www.bilibili.com/video/%s/' "$raw"
            ;;
        *)
            printf '%s' "$raw"
            ;;
    esac
}

set_cookie_file_args() {
    [ -f "$COOKIE_FILE" ] || die "指定的 cookies 文件不存在：$COOKIE_FILE"
    COOKIE_ARGS=(--cookies "$COOKIE_FILE")
    COOKIE_SOURCE="cookies 文件: $COOKIE_FILE"
}

set_browser_cookie_args() {
    local browser="$1"
    COOKIE_ARGS=(--cookies-from-browser "$browser")
    COOKIE_SOURCE="浏览器 Cookie: $browser"
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -l|--lang)
                need_value "$1" "${2:-}"
                LANG_PRIORITY="$2"
                shift 2
                ;;
            -o|--output-dir)
                need_value "$1" "${2:-}"
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -c|--cookies)
                need_value "$1" "${2:-}"
                COOKIE_FILE="$2"
                shift 2
                ;;
            --cookies-from-browser|--browser-cookies)
                need_value "$1" "${2:-}"
                BROWSER_COOKIES="$2"
                AUTO_BROWSER_COOKIES=0
                shift 2
                ;;
            --no-browser-cookies)
                AUTO_BROWSER_COOKIES=0
                shift
                ;;
            --auto-browsers)
                need_value "$1" "${2:-}"
                AUTO_BROWSERS="$2"
                shift 2
                ;;
            --timestamps)
                WITH_TIMESTAMPS=1
                shift
                ;;
            --keep-srt)
                KEEP_SRT=1
                shift
                ;;
            --format)
                need_value "$1" "${2:-}"
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --asr-fallback)
                ASR_FALLBACK=1
                shift
                ;;
            --asr-language)
                need_value "$1" "${2:-}"
                ASR_LANGUAGE="$2"
                shift 2
                ;;
            --whisper-model)
                need_value "$1" "${2:-}"
                WHISPER_MODEL="$2"
                shift 2
                ;;
            --force)
                FORCE=1
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                die "未知选项：$1"
                ;;
            *)
                if [ -z "$VIDEO_URL" ]; then
                    VIDEO_URL="$1"
                elif [ -z "$OUTPUT_DIR" ]; then
                    OUTPUT_DIR="$1"
                else
                    die "多余的位置参数：$1"
                fi
                shift
                ;;
        esac
    done

    [ -n "$VIDEO_URL" ] || { show_help; exit 1; }

    case "$OUTPUT_FORMAT" in
        txt|md) ;;
        *) die "--format 只支持 txt 或 md" ;;
    esac

    if [ -n "$COOKIE_FILE" ] && [ -n "$BROWSER_COOKIES" ]; then
        die "--cookies 和 --cookies-from-browser 不能同时使用"
    fi
}

fetch_video_info() {
    "$YTDLP_BIN" --dump-single-json "${COOKIE_ARGS[@]}" "$VIDEO_URL"
}

try_auto_cookies_for_info() {
    [ "$AUTO_BROWSER_COOKIES" -eq 1 ] || return 1
    [ "${#COOKIE_ARGS[@]}" -eq 0 ] || return 1

    local browsers browser trimmed output err_file
    browsers="$AUTO_BROWSERS"
    IFS=',' read -r -a browser_list <<< "$browsers"
    for browser in "${browser_list[@]}"; do
        trimmed="$(trim_spaces "$browser")"
        [ -n "$trimmed" ] || continue
        err_file="$TMP_DIR/info_${trimmed}.err"
        info "无 Cookie 获取失败，尝试浏览器 Cookie：$trimmed"
        if output="$("$YTDLP_BIN" --dump-single-json --cookies-from-browser "$trimmed" "$VIDEO_URL" 2>"$err_file")"; then
            VIDEO_INFO="$output"
            set_browser_cookie_args "$trimmed"
            ok "已使用 $COOKIE_SOURCE 获取视频信息"
            return 0
        fi
    done

    return 1
}

load_video_info() {
    local err_file="$TMP_DIR/video_info.err"
    info "获取视频信息..."
    if VIDEO_INFO="$(fetch_video_info 2>"$err_file")"; then
        return 0
    fi

    if try_auto_cookies_for_info; then
        return 0
    fi

    warn "yt-dlp 错误信息："
    sed 's/^/   /' "$err_file" >&2 || true
    die "无法获取视频信息，请检查链接、网络或 Cookie"
}

extract_video_meta() {
    local meta_file="$TMP_DIR/video_meta.txt"
    printf '%s' "$VIDEO_INFO" | "$PYTHON_BIN" -c '
import json
import sys

def clean(value, default="未知"):
    if value is None:
        value = default
    value = str(value).replace("\r", " ").replace("\n", " ").strip()
    return value or default

data = json.load(sys.stdin)
title = clean(data.get("title"), "未知标题")
author = clean(data.get("uploader"), "未知作者")
upload_date = clean(data.get("upload_date"), "")
if len(upload_date) == 8 and upload_date.isdigit():
    date_display = f"{upload_date[:4]}-{upload_date[4:6]}-{upload_date[6:8]}"
    date_short = upload_date
else:
    date_display = upload_date or "未知"
    date_short = "".join(ch for ch in date_display if ch.isdigit()) or "unknown"

duration = int(data.get("duration") or 0)
if duration:
    h, rem = divmod(duration, 3600)
    m, s = divmod(rem, 60)
    duration_label = f"{h}时{m}分{s}秒" if h else f"{m}分{s}秒"
    duration_file = f"{h}h{m}m{s}s" if h else f"{m}m{s}s"
else:
    duration_label = "未知"
    duration_file = "unknown"

bvid = clean(data.get("id") or data.get("display_id"), "unknown")
webpage_url = clean(data.get("webpage_url"), "")

for item in (title, author, date_display, date_short, duration_label, duration_file, bvid, webpage_url):
    print(item)
' > "$meta_file"

    VIDEO_TITLE="$(sed -n '1p' "$meta_file")"
    VIDEO_AUTHOR="$(sed -n '2p' "$meta_file")"
    VIDEO_DATE="$(sed -n '3p' "$meta_file")"
    DATE_SHORT="$(sed -n '4p' "$meta_file")"
    VIDEO_DURATION="$(sed -n '5p' "$meta_file")"
    DURATION_SIMPLE="$(sed -n '6p' "$meta_file")"
    BVID="$(sed -n '7p' "$meta_file")"
    WEBPAGE_URL="$(sed -n '8p' "$meta_file")"
    [ -n "$WEBPAGE_URL" ] || WEBPAGE_URL="$VIDEO_URL"
}

safe_base_name() {
    "$PYTHON_BIN" -c '
import re
import sys

title = sys.argv[1]
author = sys.argv[2]

def clean(part, limit):
    part = re.sub(r"[\/\\:*?\"<>|]+", "_", part)
    part = re.sub(r"[。？！，、；：\"“”'\''（）【】《》]", "_", part)
    part = re.sub(r"\s+", " ", part).strip(" ._")
    return (part[:limit].strip(" ._") or "unknown")

print(f"{clean(title, 42)}_{clean(author, 18)}")
' "$VIDEO_TITLE" "$VIDEO_AUTHOR"
}

build_output_path() {
    local ext="$1"
    local base candidate i
    base="${SAFE_NAME}_${DATE_SHORT}_${DURATION_SIMPLE}_${BVID}"
    candidate="${OUTPUT_DIR}/${base}.${ext}"

    if [ "$FORCE" -eq 1 ]; then
        printf '%s' "$candidate"
        return 0
    fi

    i=2
    while [ -e "$candidate" ]; do
        candidate="${OUTPUT_DIR}/${base}_${i}.${ext}"
        i=$((i + 1))
    done
    printf '%s' "$candidate"
}

list_subtitles() {
    "$YTDLP_BIN" --list-subs --write-auto-subs "${COOKIE_ARGS[@]}" "$VIDEO_URL" 2>&1
}

find_ai_lang() {
    local list="$1"
    local lang code trimmed
    IFS=',' read -r -a lang_list <<< "$LANG_PRIORITY"
    for lang in "${lang_list[@]}"; do
        trimmed="$(trim_spaces "$lang")"
        [ -n "$trimmed" ] || continue
        code="ai-$trimmed"
        if printf '%s\n' "$list" | grep -Eiq "^[[:space:]]*${code}[[:space:]]"; then
            printf '%s' "$code"
            return 0
        fi
    done
    return 1
}

show_ai_subtitle_preview() {
    local available
    available="$(printf '%s\n' "$SUB_LIST" | grep -Ei '^[[:space:]]*ai-[a-z]+' | head -20 || true)"
    if [ -n "$available" ]; then
        log "   可用 AI 字幕："
        printf '%s\n' "$available" | sed 's/^/   /'
    else
        log "   未在字幕列表中看到 ai-* 字幕。"
    fi
}

try_auto_cookies_for_subs() {
    [ "$AUTO_BROWSER_COOKIES" -eq 1 ] || return 1
    [ "${#COOKIE_ARGS[@]}" -eq 0 ] || return 1

    local browsers browser trimmed output status
    browsers="$AUTO_BROWSERS"
    IFS=',' read -r -a browser_list <<< "$browsers"
    for browser in "${browser_list[@]}"; do
        trimmed="$(trim_spaces "$browser")"
        [ -n "$trimmed" ] || continue
        info "未发现 AI 字幕，尝试浏览器 Cookie：$trimmed"
        if output="$("$YTDLP_BIN" --list-subs --write-auto-subs --cookies-from-browser "$trimmed" "$VIDEO_URL" 2>&1)"; then
            status=0
        else
            status=$?
        fi

        if AI_LANG_FOUND="$(find_ai_lang "$output" || true)"; [ -n "$AI_LANG_FOUND" ]; then
            SUB_LIST="$output"
            set_browser_cookie_args "$trimmed"
            ok "已使用 $COOKIE_SOURCE 发现 AI 字幕"
            return 0
        fi

        if [ "$status" -ne 0 ]; then
            printf '%s\n' "$output" | tail -3 | sed 's/^/   /' >&2 || true
        fi
    done

    return 1
}

detect_ai_subtitle() {
    info "检测 AI 字幕..."
    log "   语言优先级: $LANG_PRIORITY"

    if SUB_LIST="$(list_subtitles)"; then
        :
    else
        warn "字幕列表获取失败，继续检查输出内容。"
    fi

    AI_LANG_FOUND="$(find_ai_lang "$SUB_LIST" || true)"
    if [ -z "$AI_LANG_FOUND" ]; then
        try_auto_cookies_for_subs || true
    fi

    show_ai_subtitle_preview

    if [ -n "$AI_LANG_FOUND" ]; then
        LANG_NAME="$(lang_name "$AI_LANG_FOUND")"
        ok "发现 AI 字幕：$AI_LANG_FOUND ($LANG_NAME)"
        return 0
    fi

    return 1
}

download_ai_subtitle() {
    local download_log="$TMP_DIR/download_subtitle.log"
    info "下载 AI 字幕 ($AI_LANG_FOUND)..."

    if "$YTDLP_BIN" --skip-download --write-subs --write-auto-subs \
        "${COOKIE_ARGS[@]}" \
        --sub-langs "$AI_LANG_FOUND" \
        --sub-format "srt/vtt/best" \
        --convert-subs srt \
        -o "$TMP_DIR/subtitle.%(ext)s" \
        "$VIDEO_URL" >"$download_log" 2>&1; then
        tail -8 "$download_log" | sed 's/^/   /' || true
    else
        warn "AI 字幕下载命令失败："
        tail -30 "$download_log" | sed 's/^/   /' >&2 || true
        return 1
    fi

    SUB_FILE="$(find "$TMP_DIR" -type f \( -name 'subtitle*.srt' -o -name 'subtitle*.vtt' \) 2>/dev/null | head -1 || true)"
    if [ -z "$SUB_FILE" ] || [ ! -s "$SUB_FILE" ]; then
        warn "未找到可解析的 srt/vtt 字幕文件。"
        find "$TMP_DIR" -type f -print | sed 's/^/   临时文件: /' >&2 || true
        return 1
    fi

    ok "AI 字幕下载成功"
    TRANSCRIPT_SOURCE="B站AI字幕 (${LANG_NAME})"
    return 0
}

extract_subtitle_text() {
    PLAIN_TEXT_FILE="$TMP_DIR/transcript_plain.txt"
    TIMESTAMP_TEXT_FILE="$TMP_DIR/transcript_timestamps.txt"

    "$PYTHON_BIN" - "$SUB_FILE" "$PLAIN_TEXT_FILE" "$TIMESTAMP_TEXT_FILE" <<'PY'
import html
import re
import sys
from pathlib import Path

subtitle_path = Path(sys.argv[1])
plain_path = Path(sys.argv[2])
timestamp_path = Path(sys.argv[3])

raw = subtitle_path.read_text(encoding="utf-8-sig", errors="ignore")

def normalize_time(value):
    value = value.strip().split()[0].replace(",", ".")
    value = value.split(".")[0]
    parts = value.split(":")
    if len(parts) == 2:
        return f"00:{parts[0].zfill(2)}:{parts[1].zfill(2)}"
    if len(parts) == 3:
        return f"{parts[0].zfill(2)}:{parts[1].zfill(2)}:{parts[2].zfill(2)}"
    return value

def clean_text(line):
    line = re.sub(r"<[^>]+>", "", line)
    line = re.sub(r"\{\\.*?\}", "", line)
    line = html.unescape(line)
    line = re.sub(r"\s+", " ", line).strip()
    return line

cues = []
for block in re.split(r"\n\s*\n", raw):
    lines = [line.strip() for line in block.splitlines()]
    if not lines:
        continue

    start = ""
    text_lines = []
    for line in lines:
        if not line:
            continue
        if line.upper() == "WEBVTT" or line.startswith(("NOTE", "STYLE", "REGION", "Kind:", "Language:")):
            continue
        if re.fullmatch(r"\d+", line):
            continue
        if "-->" in line:
            start = normalize_time(line.split("-->", 1)[0])
            continue

        text = clean_text(line)
        if text:
            text_lines.append(text)

    text = clean_text(" ".join(text_lines))
    if text and (not cues or cues[-1][1] != text):
        cues.append((start, text))

if not cues:
    fallback_lines = []
    for line in raw.splitlines():
        line = line.strip()
        if not line or "-->" in line or re.fullmatch(r"\d+", line):
            continue
        text = clean_text(line)
        if text:
            fallback_lines.append(text)
    cues = [("", text) for text in fallback_lines]

plain_path.write_text("\n".join(text for _, text in cues).strip() + "\n", encoding="utf-8")
timestamp_path.write_text(
    "\n".join(f"[{start}] {text}" if start else text for start, text in cues).strip() + "\n",
    encoding="utf-8",
)
PY
}

ensure_faster_whisper() {
    if "$PYTHON_BIN" -c 'import faster_whisper' >/dev/null 2>&1; then
        return 0
    fi

    die "未安装 faster-whisper，无法启用 ASR fallback。可先运行：$PYTHON_BIN -m pip install faster-whisper"
}

run_asr_fallback() {
    warn "$1"
    [ "$ASR_FALLBACK" -eq 1 ] || die "没有可用 AI 字幕。需要音频转写时请加 --asr-fallback"

    require_cmd ffmpeg
    ensure_faster_whisper

    local audio_log="$TMP_DIR/download_audio.log"
    info "启动 ASR fallback：下载音频..."
    if "$YTDLP_BIN" -x --audio-format m4a --audio-quality 0 --no-playlist \
        "${COOKIE_ARGS[@]}" \
        -o "$TMP_DIR/audio.%(ext)s" \
        "$VIDEO_URL" >"$audio_log" 2>&1; then
        tail -8 "$audio_log" | sed 's/^/   /' || true
    else
        warn "音频下载失败："
        tail -30 "$audio_log" | sed 's/^/   /' >&2 || true
        die "ASR fallback 失败"
    fi

    AUDIO_FILE="$(find "$TMP_DIR" -type f \( -name 'audio.*' -o -name '*.m4a' -o -name '*.mp3' -o -name '*.webm' -o -name '*.wav' \) 2>/dev/null | head -1 || true)"
    [ -n "$AUDIO_FILE" ] && [ -s "$AUDIO_FILE" ] || die "未找到下载后的音频文件"

    PLAIN_TEXT_FILE="$TMP_DIR/transcript_plain.txt"
    TIMESTAMP_TEXT_FILE="$TMP_DIR/transcript_timestamps.txt"

    info "使用 faster-whisper 转写音频（model=$WHISPER_MODEL, language=$ASR_LANGUAGE）..."
    "$PYTHON_BIN" - "$AUDIO_FILE" "$ASR_LANGUAGE" "$WHISPER_MODEL" "$PLAIN_TEXT_FILE" "$TIMESTAMP_TEXT_FILE" <<'PY'
import sys
from pathlib import Path
from faster_whisper import WhisperModel

audio_file = sys.argv[1]
language = sys.argv[2]
model_name = sys.argv[3]
plain_path = Path(sys.argv[4])
timestamp_path = Path(sys.argv[5])

language_arg = None if language.lower() in {"", "auto"} else language

def fmt_time(seconds):
    seconds = int(seconds)
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    return f"{h:02d}:{m:02d}:{s:02d}"

model = WhisperModel(model_name, device="cpu", compute_type="int8")
segments, info = model.transcribe(
    audio_file,
    language=language_arg,
    beam_size=1,
    vad_filter=True,
)

plain = []
timestamped = []
for seg in segments:
    text = seg.text.strip()
    if not text:
        continue
    plain.append(text)
    timestamped.append(f"[{fmt_time(seg.start)}] {text}")

plain_path.write_text("\n".join(plain).strip() + "\n", encoding="utf-8")
timestamp_path.write_text("\n".join(timestamped).strip() + "\n", encoding="utf-8")
PY

    LANG_NAME="$(lang_name "$ASR_LANGUAGE")"
    TRANSCRIPT_SOURCE="音频 ASR (faster-whisper ${WHISPER_MODEL}, ${LANG_NAME})"
    ok "ASR 转写完成"
}

prepare_transcript_text() {
    if [ "$WITH_TIMESTAMPS" -eq 1 ]; then
        TRANSCRIPT_TEXT="$(cat "$TIMESTAMP_TEXT_FILE")"
    else
        TRANSCRIPT_TEXT="$(cat "$PLAIN_TEXT_FILE")"
    fi

    [ -n "$(printf '%s' "$TRANSCRIPT_TEXT" | tr -d '[:space:]')" ] || die "转录文本为空"
    PREVIEW_TEXT="$(printf '%s\n' "$TRANSCRIPT_TEXT" | head -10 | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g' | cut -c1-500)"
    DISCORD_PREVIEW="$(printf '%s\n' "$TRANSCRIPT_TEXT" | head -5 | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g' | cut -c1-220)"
}

write_document() {
    CURRENT_TIME="$(date '+%Y-%m-%d %H:%M')"

    if [ "$OUTPUT_FORMAT" = "md" ]; then
        cat > "$OUTPUT_FILE" << EOF
# ${VIDEO_TITLE}

## 第一部分：视频信息

- 视频标题：${VIDEO_TITLE}
- B站链接：${WEBPAGE_URL}
- 作者：${VIDEO_AUTHOR}
- 发布时间：${VIDEO_DATE}
- 视频时长：${VIDEO_DURATION}
- 字幕/转录语言：${LANG_NAME}
- 转录来源：${TRANSCRIPT_SOURCE}
- 转录时间：${CURRENT_TIME}
- Cookie 来源：${COOKIE_SOURCE}

## 第二部分：内容预览

本视频由 UP 主 ${VIDEO_AUTHOR} 发布。以下为转录开头内容预览：

${PREVIEW_TEXT}...

## 第三部分：完整原文

${TRANSCRIPT_TEXT}
EOF
    else
        cat > "$OUTPUT_FILE" << EOF
================================================================================
第一部分：视频信息
================================================================================

视频标题：${VIDEO_TITLE}
B站链接：${WEBPAGE_URL}
作者：${VIDEO_AUTHOR}
发布时间：${VIDEO_DATE}
视频时长：${VIDEO_DURATION}
字幕/转录语言：${LANG_NAME}
转录来源：${TRANSCRIPT_SOURCE}
转录时间：${CURRENT_TIME}
Cookie 来源：${COOKIE_SOURCE}

================================================================================
第二部分：内容预览
================================================================================

本视频由UP主${VIDEO_AUTHOR}发布。以下为转录开头内容预览：

${PREVIEW_TEXT}...

================================================================================
第三部分：完整原文
================================================================================

${TRANSCRIPT_TEXT}

================================================================================
文件结束
================================================================================
EOF
    fi
}

keep_subtitle_file_if_requested() {
    [ "$KEEP_SRT" -eq 1 ] || return 0
    [ -n "${SUB_FILE:-}" ] && [ -f "$SUB_FILE" ] || return 0

    local sub_ext sub_output
    sub_ext="${SUB_FILE##*.}"
    sub_output="${OUTPUT_FILE%.*}.${sub_ext}"
    cp "$SUB_FILE" "$sub_output"
    ok "已保留字幕文件：$sub_output"
}

main() {
    parse_args "$@"
    require_cmd "$YTDLP_BIN"
    require_cmd "$PYTHON_BIN"
    if ! command -v ffmpeg >/dev/null 2>&1; then
        warn "未检测到 ffmpeg。若字幕格式转换失败，请先安装 ffmpeg。"
    fi

    VIDEO_URL="$(normalize_video_url "$VIDEO_URL")"
    OUTPUT_DIR="${OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}"
    mkdir -p "$OUTPUT_DIR"
    TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bilibili-ai-subtitle.XXXXXX")"

    if [ -n "$COOKIE_FILE" ]; then
        set_cookie_file_args
    elif [ -n "$BROWSER_COOKIES" ]; then
        set_browser_cookie_args "$BROWSER_COOKIES"
    fi

    log "=========================================="
    log "🎬 Bilibili AI字幕下载器 v${VERSION}"
    log "=========================================="
    log "🌐 视频链接: $VIDEO_URL"
    log "🌐 语言优先级: $LANG_PRIORITY"
    log "🍪 Cookie 来源: $COOKIE_SOURCE"
    log "📁 输出目录: $OUTPUT_DIR"
    log ""

    load_video_info
    extract_video_meta

    log "📋 视频信息"
    log "   标题: $VIDEO_TITLE"
    log "   作者: $VIDEO_AUTHOR"
    log "   时间: $VIDEO_DATE"
    log "   时长: $VIDEO_DURATION"
    log ""

    SAFE_NAME="$(safe_base_name)"
    OUTPUT_FILE="$(build_output_path "$OUTPUT_FORMAT")"

    if detect_ai_subtitle; then
        if download_ai_subtitle; then
            extract_subtitle_text
        else
            run_asr_fallback "AI 字幕存在但下载失败。"
        fi
    else
        run_asr_fallback "该视频没有匹配的 AI 字幕（指定语言：$LANG_PRIORITY）。"
    fi

    prepare_transcript_text
    write_document
    keep_subtitle_file_if_requested

    WORD_COUNT="$(wc -m < "$OUTPUT_FILE" | tr -d '[:space:]')"
    FILENAME="$(basename "$OUTPUT_FILE")"

    log ""
    log "=========================================="
    ok "字幕/转录文件生成成功"
    log "=========================================="
    log ""
    log "📄 文件：$FILENAME"
    log "📍 位置：$OUTPUT_FILE"
    log "📝 字数：约${WORD_COUNT}字"
    log "🌐 语言：$LANG_NAME"
    log "🧾 来源：$TRANSCRIPT_SOURCE"
    log ""
    log "💡 内容预览："
    log "$DISCORD_PREVIEW..."
    log ""
    log "📎 完整内容请查看输出文件"
}

main "$@"
