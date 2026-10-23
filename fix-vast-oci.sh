#!/usr/bin/env bash
#
# fix-vast-oci.sh
# -----------------------------------------------------------------------------
# Popravlja Vast.ai "OCI runtime create failed ... kaalia_docker_shim ...
# exit status 101" gresku koju uzrokuje pogresno vlasnistvo direktorija
# nakon brisanja/ponovnog kreiranja masine.
#
# Uzrok: daemon 'kaalia' radi kao korisnik vastai_kaalia, ali se direktorij
# container_gpu_idxs (i ponekad nedostaje cdi_overrides) vrati u vlasnistvu
# root-a, pa daemon ne moze upisati GPU-index fajl -> shim padne (exit 101).
#
# Koristenje:  sudo bash fix-vast-oci.sh
# Pokreni ovo nakon SVAKOG reseta/reinstalacije masine ako se greska vrati.
# -----------------------------------------------------------------------------
set -euo pipefail

KAALIA_USER="vastai_kaalia"
KAALIA_GROUP="docker"
BASE="/var/lib/vastai_kaalia"
GPU_IDX_DIR="$BASE/data/container_gpu_idxs"
CDI_OVR_DIR="$BASE/cdi_overrides"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Ova skripta treba root. Pokreni: sudo bash $0" >&2
  exit 1
fi

if ! id "$KAALIA_USER" >/dev/null 2>&1; then
  echo "Korisnik '$KAALIA_USER' ne postoji — je li ovo Vast host? Prekidam." >&2
  exit 1
fi

echo "== Vast OCI fix =="

# 1) container_gpu_idxs — mora postojati i biti u vlasnistvu daemon korisnika
mkdir -p "$GPU_IDX_DIR"
chown "$KAALIA_USER:$KAALIA_GROUP" "$GPU_IDX_DIR"
chmod 755 "$GPU_IDX_DIR"
echo "  [ok] $GPU_IDX_DIR -> $KAALIA_USER:$KAALIA_GROUP"

# 2) cdi_overrides — ponekad nedostaje nakon reseta
mkdir -p "$CDI_OVR_DIR"
chown "$KAALIA_USER:$KAALIA_GROUP" "$CDI_OVR_DIR"
chmod 755 "$CDI_OVR_DIR"
echo "  [ok] $CDI_OVR_DIR -> $KAALIA_USER:$KAALIA_GROUP"

# 3) Provjera da daemon korisnik stvarno moze pisati
TESTF="$GPU_IDX_DIR/_writetest_$$"
if sudo -u "$KAALIA_USER" touch "$TESTF" 2>/dev/null; then
  rm -f "$TESTF"
  echo "  [ok] write test kao $KAALIA_USER: USPJESNO"
else
  echo "  [GRESKA] $KAALIA_USER i dalje ne moze pisati u $GPU_IDX_DIR" >&2
  exit 1
fi

echo
echo "== Trenutno vlasnistvo =="
ls -ld "$GPU_IDX_DIR" "$CDI_OVR_DIR"

echo
echo "== Zadnje OCI/shim greske u logu (ako ih ima nakon ovog trenutka, javi) =="
grep -iE 'exit status 101|failed to open .*container_gpu_idxs|oci runtime create failed' \
  "$BASE/kaalia.log" "$BASE/kaalia.logX" 2>/dev/null | tail -5 || echo "  (nema podudaranja)"

echo
echo "GOTOVO. Sad pokreni novu instancu / self-test na Vast konzoli."
echo "Za pracenje uzivo:"
echo "  watch -n2 'ls -la $GPU_IDX_DIR'"
