# Vast.ai Self-Verification Failure — Diagnosis & Next Steps

**Host:** single-GPU Vast.ai host — RTX 5090
**Date diagnosed:** 2026-06-07
**Status:** Machine still listed, but GPU/container self-test AND real instances fail with the same error.

---

## ✅ CONFIRMED ROOT CAUSE (updated 2026-06-07, after re-test on a new instance)

**Directory ownership bug — caused by wiping & recreating the machine.**

The daemon logs `failed to open outfile/infile container_gpu_idxs/<id>` because:

- Daemon `kaalia` runs as user **`vastai_kaalia`** (group docker).
- `/var/lib/vastai_kaalia/data/container_gpu_idxs/` is owned by **`root:root`** (mode 755).
- All sibling dirs in `data/` (`configs`, `instance_extra_logs`, `get_controller_delay`) are correctly owned by `vastai_kaalia:docker`.
- So the daemon **cannot write** the per-container GPU-index file → shim aborts (exit 101) → `OCI runtime create failed`.

When the machine was deleted & recreated, this one directory got re-created as `root` instead of `vastai_kaalia`. (Earlier suspicion of a version_300 daemon bug was wrong — it's this permissions leftover.)

### THE FIX (run as root, no reboot needed)

```bash
sudo chown vastai_kaalia:docker /var/lib/vastai_kaalia/data/container_gpu_idxs
sudo mkdir -p /var/lib/vastai_kaalia/cdi_overrides
sudo chown vastai_kaalia:docker /var/lib/vastai_kaalia/cdi_overrides
```

### STATUS UPDATE (2026-06-07 ~15:00) — fix applied ✅

- `chown` odrađen. Oba direktorija sada `vastai_kaalia:docker` (potvrđeno):
  - `/var/lib/vastai_kaalia/data/container_gpu_idxs` → vastai_kaalia:docker ✅
  - `/var/lib/vastai_kaalia/cdi_overrides` → vastai_kaalia:docker ✅
- Zadnje `failed to open ... container_gpu_idxs` greške su iz **14:56**, a popravak je u **14:58** → greške su STARIJE od popravka, nema novih.
- **Preostaje:** pokrenuti novu instancu / self-test da se potvrdi da se GPU-index fajl sad upisuje (direktorij je prazan dok ne krene novi kontejner).
- Pomoćna skripta: `fix-vast-oci.sh` (pokreni sa `sudo bash fix-vast-oci.sh`).

Then retry an instance / self-test. Verify the fix:

```bash
# write test should now succeed:
sudo -u vastai_kaalia touch /var/lib/vastai_kaalia/data/container_gpu_idxs/_t && \
  sudo -u vastai_kaalia rm /var/lib/vastai_kaalia/data/container_gpu_idxs/_t && echo OK
# after next instance starts, file should appear:
ls -la /var/lib/vastai_kaalia/data/container_gpu_idxs/
# no new OCI errors:
grep -iE 'exit status 101|failed to open .*container_gpu_idxs' \
  /var/lib/vastai_kaalia/kaalia.log /var/lib/vastai_kaalia/kaalia.logX | tail
```

---

## The error (verbatim, from /var/lib/vastai_kaalia/kaalia.logX)

```
OCI runtime create failed: unable to retrieve OCI runtime error
(open /run/containerd/io.containerd.runtime.v2.task/moby/<id>/log.json: no such file or directory):
/var/lib/vastai_kaalia/latest/kaalia_docker_shim did not terminate successfully: exit status 101
```

And from the self-test container's start log:

```
missing container_gpu_idxs file at ".../container_gpu_idxs/<id>"; refusing to start container
```

Self-test image used: `vastai/test:self-test-cu128`

---

## Root cause — Vast daemon-side bug, NOT host config

- **Exit 101** = Rust panic/abort. The `kaalia_docker_shim` (Vast's NVIDIA-runtime wrapper) deliberately aborts because a required file is missing.
- The missing file lives in `/var/lib/vastai_kaalia/data/container_gpu_idxs/` — confirmed **EMPTY**. The daemon should write `container_gpu_idxs/<container_id>` (the GPU-index map for the container) *before* invoking the shim, but it doesn't.
- Also missing entirely: `/var/lib/vastai_kaalia/cdi_overrides/` directory (referenced in same flow).
- **Trigger:** daemon updated to **version_300** at 14:09 today and switched to **CDI mode** (`mode = "cdi"` in `/etc/nvidia-container-runtime/config.toml`). The empty `container_gpu_idxs/` dir was created during that 14:09 restart. This is a **regression/race in the version_300 CDI device-injection flow**.

## Why it's NOT the hardware/toolkit (all verified healthy)

- Driver 580.95.05 / CUDA 13.0; `nvidia-container-cli info` sees the RTX 5090 fine
- toolkit 1.18.0 (Blackwell-capable), runc 1.3.3, Docker 29.0.2
- `default-runtime: nvidia`; valid CDI spec at `/etc/cdi/nvidia.yaml`
- shim binary itself runs fine (`kaalia_docker_shim --version` → NVIDIA Container Runtime 1.18.0)
- Note: GPU also drives a display (Disp.A: On, ~80 MiB used) — not the cause here.

---

## Next steps (do after reboot)

1. **Reboot the host** (done / doing now). A plain daemon restart won't help — autorestart cron bounces it every minute and it keeps failing on stale state. Full reboot clears leftover container/CDI state and lets version_300 re-init `container_gpu_idxs`/`cdi_overrides` from scratch.
2. **After reboot, re-check:** is `/var/lib/vastai_kaalia/data/container_gpu_idxs/` getting populated when a self-test runs? Did the OCI error stop?
3. **If it persists after reboot** → confirmed version_300 daemon bug. Report to Vast (Discord #host-support or support ticket) with the two key lines above (the `exit status 101` line + the `missing container_gpu_idxs file` line). Ask them to roll the daemon back a version or push a fix.

## Useful commands to re-run after reboot

```bash
# Did the self-test pass this time?
cat /var/lib/vastai_kaalia/self_test.log

# Is the GPU-index file now being written?
ls -la /var/lib/vastai_kaalia/data/container_gpu_idxs/

# Any new OCI / shim panic errors?
grep -iE 'oci runtime create failed|exit status 101|container_gpu_idxs|refusing to start' \
  /var/lib/vastai_kaalia/kaalia.log /var/lib/vastai_kaalia/kaalia.logX | tail -30

# Manually trigger a self-test
cat /var/lib/vastai_kaalia/start_self_test.sh   # inspect first, then run as appropriate
```

## Key paths
- Daemon dir: `/var/lib/vastai_kaalia/`
- Logs: `kaalia.log`, `kaalia.logX` (rotated), `self_test.log`, `update_300.log`
- Runtime config: `/etc/nvidia-container-runtime/config.toml` (mode = "cdi")
- Docker config: `/etc/docker/daemon.json` (default-runtime nvidia → kaalia_docker_shim)
- CDI specs: `/etc/cdi/nvidia.yaml` (+ per-container `D.<id>.yaml`)
