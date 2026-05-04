# Cross-compile Syncthing .spk packages for Synology devices using SynoCommunity's spksrc.
#
# Targets in this project:
#   - DS213j (armv7l, armada370, kernel 3.2, running DSM 7.1.1 — custom firmware)
#   - DS216j (armv7l, armada38x, kernel 3.10)
#
# spksrc only publishes a linux/amd64 image. On Apple Silicon hosts this runs
# under emulation (slower, but functional).
FROM --platform=linux/amd64 ghcr.io/synocommunity/spksrc:latest

# The base image provides every build dependency listed in spksrc/README, plus
# an empty /spksrc that's expected to hold the source tree. Populate it with a
# fresh shallow clone. (The default WORKDIR is /spksrc, so we cd out first to
# avoid "cannot read cwd" errors on operations that touch the directory.)
WORKDIR /
RUN git clone --depth 1 https://github.com/SynoCommunity/spksrc.git /spksrc

# ---------------------------------------------------------------------------
# Patched Go toolchain
# ---------------------------------------------------------------------------
# Stock Go 1.24+ uses futex_time64 (syscall 422 on 32-bit ARM Linux) for
# Y2038-safe time arguments. Synology's kernel fork added proprietary syscalls
# in the 402–427 range; on the kernels shipped with these NAS units, syscall
# 422 means sys_SYNONotifyInit, not futex_time64, so every futex call from a
# Go binary either crashes outright or returns an error the runtime treats as
# fatal (golang/go#77930).
#
# The fix — upstream Go CL 751340, slated for Go 1.27 (unreleased) — switches
# the runtime from "try futex_time64, fall back on ENOSYS" to a uname version
# check up-front, so it never issues syscall 422 on kernels that predate it.
# Tailscale cherry-picked the CL into their public Go fork on the
# tailscale.go1.26 branch (PR tailscale/go#163, merged 2026-03-25). We build
# Go from that commit and repackage the result so spksrc can consume it as
# though it were the official tarball.
ARG TAILSCALE_GO_COMMIT=f4de14a515221e27c0d79446b423849a6546e3a6
ARG GO_PKG_VERS=1.26.2

# Bootstrap compiler for building Go from source. Any recent stable Go works;
# 1.24.13 has known-good hashes from earlier in this project's history.
ARG BOOTSTRAP_GO_VERSION=1.24.13
ARG BOOTSTRAP_GO_SHA256=1fc94b57134d51669c72173ad5d49fd62afb0f1db9bf3f798fd98ee423f8d730
RUN set -eu; \
    curl -sSL -o /tmp/bootstrap.tgz \
      "https://go.dev/dl/go${BOOTSTRAP_GO_VERSION}.linux-amd64.tar.gz"; \
    echo "${BOOTSTRAP_GO_SHA256}  /tmp/bootstrap.tgz" | sha256sum -c -; \
    mkdir -p /opt/go-bootstrap; \
    tar -xzf /tmp/bootstrap.tgz --strip-components=1 -C /opt/go-bootstrap; \
    rm /tmp/bootstrap.tgz

# Build the patched Go toolchain. Fetching a single commit by SHA keeps this
# reproducible regardless of where the tailscale.go1.26 branch tip moves.
RUN set -eu; \
    mkdir -p /build/go; cd /build/go; \
    git init -q; \
    git remote add origin https://github.com/tailscale/go.git; \
    git fetch -q --depth 1 origin "${TAILSCALE_GO_COMMIT}"; \
    git checkout -q FETCH_HEAD; \
    cd src; \
    GOROOT_BOOTSTRAP=/opt/go-bootstrap \
    GOROOT_FINAL=/usr/local/go \
    ./make.bash; \
    rm -rf /build/go/.git /build/go/pkg/obj /build/go/test

# Repackage the build output to look like an official go.dev tarball, drop it
# into spksrc's distrib cache, and rewrite native/go's Makefile + digests so
# spksrc skips the wget step and uses our local file. PKG_VERS just controls
# the filename and the cached path; the actual `go version` string still
# carries tailscale's commit suffix.
RUN set -eu; \
    TARBALL="go${GO_PKG_VERS}.linux-amd64.tar.gz"; \
    mkdir -p /spksrc/distrib; \
    tar -czf "/spksrc/distrib/${TARBALL}" -C /build go; \
    rm -rf /build; \
    SHA1=$(sha1sum   "/spksrc/distrib/${TARBALL}" | awk '{print $1}'); \
    SHA256=$(sha256sum "/spksrc/distrib/${TARBALL}" | awk '{print $1}'); \
    MD5=$(md5sum    "/spksrc/distrib/${TARBALL}" | awk '{print $1}'); \
    sed -i "s/^PKG_VERS = .*/PKG_VERS = ${GO_PKG_VERS}/" /spksrc/native/go/Makefile; \
    { \
      echo "${TARBALL} SHA1 ${SHA1}"; \
      echo "${TARBALL} SHA256 ${SHA256}"; \
      echo "${TARBALL} MD5 ${MD5}"; \
    } > /spksrc/native/go/digests

WORKDIR /spksrc

CMD ["bash"]
