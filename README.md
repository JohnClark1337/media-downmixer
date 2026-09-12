# media-downmixer

`audio_downmix.py` — add nightmode (dialogue-boosted) **stereo** audio tracks to
videos that contain **5.1 / 7.1** (or other multichannel) surround sound.

Designed for headless media servers: it accepts whole directories, recurses
through the tree, queues every video file, and processes them through `ffmpeg`.
Video and subtitles are **stream-copied** (no re-encode), so only the new stereo
audio track is actually encoded — fast even for large libraries.

## What it does to each file

1. **Dialog boost ("nightmode")** — the ffmpeg `dialoguenhance` filter lifts
   dialogue relative to the rest of the mix.
2. **Downmix to stereo** — the `pan` filter folds the centre (0.707) and
   surround (0.707) channels into left/right, dropping the LFE.
3. **New track** — the result is encoded as a stereo AAC track
   (`libopus` for `.webm`) and muxed into the file.

By default the original surround track is **kept** and the stereo track is
**added** alongside it. A file is only skipped when it already has an
**English** stereo track — if the only stereo tracks present are in other
languages (or untagged), the English downmix is still added.

## Requirements

- Python 3.5+
- `ffmpeg` and `ffprobe` on `PATH` (or pass `--ffmpeg` / `--ffprobe`)
- `mkvmerge` (from [MKVToolNix](https://mkvtoolnix.download)) — used once matroska
  output is written to re-mux it into VLC-friendly clusters/cues. This avoids an
  ffmpeg muxer quirk where long seeks on DVD-era MPEG-2 files can freeze VLC.
  Pass `--no-remux` if you want to skip it.

## Usage

```text
python audio_downmix.py PATH [PATH ...] [options]
```

`PATH` can be a video file or a directory (searched recursively, including
subdirectories). Multiple paths may be given.

### Examples

```sh
# Add stereo tracks, mirroring the input tree into ./nightmix_output
python audio_downmix.py /media/movies

# Same, but overwrite the originals in place
python audio_downmix.py /media/movies --in-place

# Replace the surround track with just the stereo version
python audio_downmix.py /media/movies --replace

# Preview everything the tool would do without touching any files
python audio_downmix.py /media/movies --dry-run

# Process 4 files in parallel and log to a file
python audio_downmix.py /media/movies --jobs 4 --log downmix.log

# Process files even if they already have an English stereo track
python audio_downmix.py /media/movies --force

# Stronger dialog boost, full volume
python audio_downmix.py /media/movies --enhance 2.0 --voice 2

# Skip the mkvmerge re-mux step (matroska output may seek poorly in VLC)
python audio_downmix.py /media/movies --no-remux
```

### Options

| Option | Default | Description |
| --- | --- | --- |
| `-o, --output DIR` | `./nightmix_output` | Output directory mirroring the input tree |
| `--in-place` | off | Overwrite each original file with the result |
| `--replace` | off | Drop the original surround track(s), keep only the stereo ones |
| `--force` | off | Process files even if they already have an English stereo track |
| `--enhance N` | `1.5` | Dialog boost factor, `0..3` (`0` disables the filter) |
| `--voice N` | `2` | Dialog voice-detection sensitivity, `2..32` |
| `--bitrate K` | `192k` | Bitrate of the new stereo AAC track |
| `--ext EXT [...]` | `.mkv .mp4 .avi .mov .m4v .webm` | Extensions to scan for |
| `--jobs N` | `1` | Number of files processed in parallel |
| `--dry-run` | off | Print the ffmpeg commands without running them |
| `--ffmpeg P` / `--ffprobe P` | `ffmpeg` / `ffprobe` | Paths to tools |
| `--mkvmerge P` | `mkvmerge` | Path to mkvmerge |
| `--no-remux` | off | Disable the mkvmerge re-mux step |
| `--log FILE` | - | Also write log output to a file |
| `-q, --quiet` | off | Only errors and the summary |
| `-v, --verbose` | off | Print ffmpeg commands and details |

## Behavior notes

- **Skipped files** are reported and counted — nothing is silently dropped.
- **In-place mode** writes to a temporary file first, then atomically replaces
  the original; a failed run leaves the original untouched.
- Any file that fails keeps its original intact and is listed in the final
  summary. The exit code is non-zero if any file failed (handy for scripts).
- **Subtitles** are preserved (`.mkv` keeps all tracks; `.mp4`/`.mov` keep
  `mov_text` tracks).
- **Attachments** (embedded fonts/cover art) are not preserved.
- The new track is tagged `title=Nightmix Stereo` **and** `language=eng`, so a
  file never gets a duplicate English downmix on a re-run. Both tags survive the
  mkvmerge re-mux. In add mode the original surround track stays the default;
  use `--replace` if you want the stereo track to be the only/first one (e.g. so
  your player or Plex/Jellyfin picks it by default).
- Chapter markers are preserved by ffmpeg for formats that support them, and the
  mkvmerge re-mux keeps them.
- Matroska (`.mkv`/`.webm`) output is re-muxed with `mkvmerge` after ffmpeg so
  clusters/cues are laid out the way VLC expects. The re-mux is a full
  stream-copy (no re-encode) and is atomic: the temp file replaces the ffmpeg
  output only after mkvmerge succeeds.

## Supported layouts

5.1, 5.1(side), 5.0, 7.1, 7.1(wide), 7.0, 6.1 and any other multichannel
layout with 6+ channels (unknown layouts fall back to a sensible mapping).
Files with only mono/stereo audio are left unchanged.