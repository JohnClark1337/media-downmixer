# media-downmixer

`audio_downmix.py` — add nightmode (dialogue-boosted) **stereo** audio tracks to
videos that contain **5.1 / 7.1** (or other multichannel) surround sound.

Designed for headless media servers: it accepts whole directories, recurses
through the tree, queues every video file, and processes them through `ffmpeg`.
A live progress bar shows overall completion and the file currently being
processed (disabled with `--no-progress` or when output is not a TTY).
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
subdirectories). Multiple paths may be given. Use `--no-recursive` to only
process the immediate files of each directory.

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

# Only the immediate files of each directory, no recursion
python audio_downmix.py /media/movies --no-recursive

# Stronger dialog boost, full volume
python audio_downmix.py /media/movies --enhance 2.0 --voice 2

# Skip the mkvmerge re-mux step (matroska output may seek poorly in VLC)
python audio_downmix.py /media/movies --no-remux
```

## Docker

A `Dockerfile` bundles the tool with a **modern ffmpeg** (includes
`dialoguenhance`), ffprobe, and mkvmerge — so what Ubuntu/Debian's old apt
ffmpeg ships can never break it. The image is Alpine-based and self-contained;
no dependencies are installed on the host.

**Build** (on the media server or any machine with Docker):

```sh
docker build -t media-downmixer .
```

**Run** — mount your library **read-only** and a writable output dir:

```sh
docker run --rm \
  -v /mnt/Plex/TV:/media:ro \
  -v /mnt/Plex/nightmix_output:/output \
  media-downmixer /media --output /output
```

Everything after the image name is a normal `audio_downmix.py` argument, so
`--jobs`, `--replace`, `--dry-run`, `--log`, etc. all work. Run inside
`tmux`/`screen` for long queues.

```sh
# Preview first
docker run --rm -v /mnt/Plex/TV:/media:ro -v /mnt/Plex/nightmix_output:/output \
  media-downmixer /media --output /output --dry-run

# Parallel
docker run --rm -v /mnt/Plex/TV:/media:ro -v /mnt/Plex/nightmix_output:/output \
  media-downmixer /media --output /output --jobs 4
```

Or use the included `docker-compose.yml` (edit the host paths, then
`docker compose up --build`). `--in-place` won't work in the container because
the library is mounted read-only — use `--output` instead.

If the output files should be owned by your user rather than root, add
`--user "$(id -u):$(id -g)"` to the `docker run` command.

The Dockerfile verifies at build time that `dialoguenhance`, `ffprobe`, and
`mkvmerge` are all present, so a broken intermediate image fails fast during
the build instead of on the first video file.

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
| `--recursive` / `--no-recursive` | recursive | Scan directories recursively (or only the immediate files) |
| `--no-progress` | off | Disable the live progress bar |
| `--jobs N` | `1` | Number of files processed in parallel |
| `--dry-run` | off | Print the ffmpeg commands without running them |
| `--ffmpeg P` / `--ffprobe P` | `ffmpeg` / `ffprobe` | Paths to tools |
| `--mkvmerge P` | `mkvmerge` | Path to mkvmerge |
| `--no-remux` | off | Disable the mkvmerge re-mux step |
| `--log FILE` | - | Also write log output to a file |
| `-q, --quiet` | off | Only errors and the summary |
| `-v, --verbose` | off | Print ffmpeg commands and details |

## Behavior notes

- **Progress**: on an interactive terminal a live bar shows completion
  (`[####----] 13/27 48%`) plus the file currently being processed; it's
  updated as each file finishes and redrawn on every change. When output is not
  a TTY (piped, Docker without `-t`, or with `-q`/`--no-progress`), the bar is
  skipped and each file is instead reported as it starts and completes. In
  parallel mode, "currently processing" shows the most recently dispatched
  file while other workers keep running.
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