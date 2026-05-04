# synology-syncthing

Build runnable Syncthing `.spk` packages for old ARMv7 Synology NAS devices that
the official Syncthing release binaries crash on.

## The problem

Syncthing 2.0.x is built with Go 1.24+. Starting in Go 1.24 the runtime issues
the `futex_time64` syscall (number 422 on 32-bit ARM Linux) for Y2038-safe
futex operations, with a "try the new syscall, fall back on `ENOSYS`" pattern.

Synology's kernel fork added proprietary syscalls in the 402–427 range. On
those kernels, syscall 422 is **`sys_SYNONotifyInit`**, not `futex_time64`.
Synology's kernel doesn't return `ENOSYS` — it dispatches the call to its own
handler, which either returns nonsense the Go runtime treats as fatal or hard
faults the process. Any Go ≥ 1.24 binary running on these NAS units crashes
at startup with something like:

```
futexwakeup addr=0x... returned -22
SIGSEGV: segmentation violation
runtime.futexwakeup runtime/os_linux.go:98
```

This is tracked upstream as [golang/go#77930]. The fix is Go CL 751340 —
replace the runtime fallback dance with an up-front `uname` version check so
the syscall is never issued on kernels that predate it. The CL is slated for
Go 1.27, which isn't released yet (1.26.2 is current latest).

[Tailscale cherry-picked the CL][tspr] into their public Go fork on the
`tailscale.go1.26` branch so they can ship Tailscale binaries that run on
Synology and old Android. We use that fork as the build toolchain.

[golang/go#77930]: https://github.com/golang/go/issues/77930
[tspr]: https://github.com/tailscale/go/pull/163

## What this repo does

`run.sh` builds a Docker image (from `Dockerfile`) that:

1. Pulls the [SynoCommunity spksrc][spksrc] image, which carries every native
   build dep and Synology toolchain spksrc supports.
2. Builds the patched Go 1.26 from `tailscale/go` (commit `f4de14a`) and drops
   the resulting tarball into spksrc's distrib cache so spksrc compiles
   Syncthing against it instead of the stock Go from go.dev.
3. Invokes `make arch-...` inside `spk/syncthing` for each target arch + DSM
   combination and copies the resulting `.spk` files into `./output/`.

[spksrc]: https://github.com/SynoCommunity/spksrc

Nothing is installed on the host — everything runs inside the container.

## Targets

The build produces three packages, tuned for the devices in this household:

| File | Device | Arch | DSM |
|---|---|---|---|
| `syncthing_armada370-7.1_2.0.16-34.spk` | DS213j ("silos") | armada370 | 7.1 |
| `syncthing_armada38x-7.0_2.0.16-34.spk` | DS216j ("twardziel") | armada38x | 7.0 |
| `syncthing_armada38x-6.1_2.0.16-34.spk` | DS216j fallback | armada38x | 6.1 |

To build for different devices, edit the `make arch-...` lines in `run.sh`.
Supported toolchains live under `/spksrc/toolchain/` inside the image
(`syno-<arch>-<dsm>`).

## Usage

Requires Docker (or OrbStack on macOS).

```sh
./run.sh
```

The first run is slow — it builds Go from source under `linux/amd64`
emulation on Apple Silicon (~4 min) and downloads the Synology toolchain
tarballs. Subsequent runs reuse the image cache.

Install the resulting `.spk` from DSM Package Center → Manual Install.

## Notes for Apple Silicon hosts

The spksrc image is published for `linux/amd64` only, so both `docker build`
and `docker run` pin `--platform=linux/amd64`. Builds work fine under
emulation, just slower.

## When Go 1.27 ships

Once Go 1.27 is out, the patched-fork detour can be removed: revert
`Dockerfile` to a stock `PKG_VERS = 1.27.x` pin in `/spksrc/native/go` (or
let spksrc's tree advance to 1.27 on its own and remove the override
entirely).
