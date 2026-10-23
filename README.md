# vast-host-cleanup

Shell scripts for Linux machines that host GPUs on [Vast.ai](https://vast.ai): fix a common self-test failure, or fully remove the Vast host software and reclaim the machine.

> ⚠️ These scripts run as root, stop services, kill processes and (in one case) **erase a disk partition**. Read each script before running it.

## Scripts

| Script | What it does |
|---|---|
| [`fix-vast-oci.sh`](fix-vast-oci.sh) | Fixes the `OCI runtime create failed … kaalia_docker_shim … exit status 101` error. It happens when `container_gpu_idxs/` ends up owned by `root` (typically after deleting and re-creating the machine), so the daemon can't write the GPU-index file. Safe to re-run. |
| [`purge_vast.sh`](purge_vast.sh) | Completely removes Vast.ai host software: cron jobs, systemd services, `kaalia` processes, the reverse SSH tunnel, renter containers and images, files and the `vastai_kaalia` user. **Ends any active rental.** Leaves the data disk alone. |
| [`wipe_vast_disk.sh`](wipe_vast_disk.sh) | After purging, wipes the old `vast_client_data` partition, reformats it as XFS labelled `dockerdata`, updates `/etc/fstab` and restarts Docker on a clean data root. Refuses to touch the root filesystem and asks you to type `YES`. **Destroys all data on that partition.** |
| [`set_hostname.sh`](set_hostname.sh) | Renames the machine and fixes the `127.0.1.1` line in `/etc/hosts` (keeps a backup). |

## Usage

```bash
# fix the exit-101 self-test failure
sudo bash fix-vast-oci.sh

# stop hosting and remove everything Vast installed
sudo bash purge_vast.sh

# then optionally reclaim the data partition (check the device with lsblk first!)
sudo bash wipe_vast_disk.sh /dev/nvme0n1p3

# rename the machine
sudo bash set_hostname.sh my-new-hostname
```

## Notes

[`vast-self-test-OCI-failure.md`](vast-self-test-OCI-failure.md) is the full write-up of the exit-101 investigation: the error, how the root cause was found, what was ruled out, and commands to verify the fix. Parts of it, and the messages in `fix-vast-oci.sh`, are in Croatian.

Tested on Ubuntu with an RTX 5090, NVIDIA driver 580, Container Toolkit 1.18 and Docker 29. Not affiliated with Vast.ai.
