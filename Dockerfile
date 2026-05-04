# Cross-compile Syncthing .spk packages for Synology devices using SynoCommunity's spksrc.
#
# Targets in this project:
#   - DS213j (armv7l, armada370, DSM 6.x max)
#   - DS216j (armv7l, armada38x, up to DSM 7.2)
#
# Using the SynoCommunity spksrc image gives us the toolchain + a Go version that
# spksrc has chosen to be compatible with the older Synology kernels (3.2 / 3.10),
# avoiding the runtime crash from upstream syncthing builds (golang/go#77930).
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

# Pin Go 1.24.x. The current spksrc tree builds Syncthing with Go 1.25, which
# regressed futex handling on old Linux kernels (golang/go#77930) — the runtime
# crashes at startup with "futexwakeup ... returned -22 / SIGSEGV" on DSM 6 boxes
# (kernel 3.2 / 3.10). Go 1.24 is the last unaffected line; Syncthing 2.0.14
# declares `go 1.24.0` in go.mod so it builds cleanly against it.
ARG GO_VERSION=1.24.13
ARG GO_SHA1=8adda2a5d050fba0eb92db2c1ae38b934b683c37
ARG GO_SHA256=1fc94b57134d51669c72173ad5d49fd62afb0f1db9bf3f798fd98ee423f8d730
ARG GO_MD5=5dea5e9a4ddbc7101daf0293b778b480
RUN set -eu; cd /spksrc/native/go; \
    sed -i "s/^PKG_VERS = .*/PKG_VERS = ${GO_VERSION}/" Makefile; \
    { \
      echo "go${GO_VERSION}.linux-amd64.tar.gz SHA1 ${GO_SHA1}"; \
      echo "go${GO_VERSION}.linux-amd64.tar.gz SHA256 ${GO_SHA256}"; \
      echo "go${GO_VERSION}.linux-amd64.tar.gz MD5 ${GO_MD5}"; \
    } > digests

WORKDIR /spksrc

CMD ["bash"]
