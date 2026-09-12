# media-downmixer container
#
# Everything the tool needs, isolated from the host OS:
#   - python3          runs the tool
#   - ffmpeg/ffprobe   Alpine's ffmpeg (6.1.2 on alpine:3.21) includes
#                      dialoguenhance (needs ffmpeg >= 6.0)
#   - mkvtoolnix       provides `mkvmerge` for the VLC-friendly re-mux step
#
# Build:   docker build -t media-downmixer .
# Run:     docker run --rm \
#            -v /mnt/Plex/TV:/media:ro -v /mnt/Plex/nightmix_output:/output \
#            media-downmixer /media --output /output
FROM alpine:3.21

RUN apk add --no-cache \
        python3 \
        ffmpeg \
        mkvtoolnix \
    && ffmpeg -hide_banner -filters 2>/dev/null | grep -q dialoguenhance \
    && ffprobe -version >/dev/null && mkvmerge --version >/dev/null

COPY audio_downmix.py /usr/local/bin/media-downmixer

WORKDIR /work
ENTRYPOINT ["python3", "/usr/local/bin/media-downmixer"]
CMD ["--help"]