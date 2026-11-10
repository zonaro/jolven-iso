#!/usr/bin/env bash
# Boot a Nobara/Jolven ISO in an isolated QEMU disk. No real disk writes.
set -Eeuo pipefail
usage() {
  cat >&2 <<'HELP'
Usage: scripts/qa-nobara-vm.sh /path/custom.iso /path/to/test-directory
Opens QEMU with a sparse 40 GiB qcow2 disk; not real hardware.
Manual validation of boot, install and login is required.
HELP
  exit 64
}
[[ $# == 2 ]] || usage
for cmd in realpath qemu-system-x86_64 qemu-img; do
  command -v "$cmd" >/dev/null || { echo "Missing: $cmd" >&2; exit 69; }
done
iso="$(realpath -- "$1")"
[[ -f "$iso" && "$iso" == *.iso ]] || usage
mkdir -p -- "$2"
vm="$(realpath -- "$2")"
disk="$vm/nobara-jolven-test.qcow2"
if [[ ! -e "$disk" ]]; then
  qemu-img create -f qcow2 "$disk" 40G
fi
[[ -f "$disk" && ! -L "$disk" ]] || {
  echo 'Refusing symlink or non-file VM disk' >&2; exit 73;
}
if [[ -r /dev/kvm && -w /dev/kvm ]]; then
  accel=kvm
else
  echo 'KVM unavailable; using slower TCG virtualization.' >&2
  accel=tcg
fi
ovmf=""
for candidate in \
  /usr/share/edk2/ovmf/OVMF_CODE.fd \
  /usr/share/OVMF/OVMF_CODE_4M.fd \
  /usr/share/OVMF/OVMF_CODE.fd; do
  if [[ -r "$candidate" ]]; then ovmf="$candidate"; break; fi
done
vars=""
for candidate in \
  /usr/share/edk2/ovmf/OVMF_VARS.fd \
  /usr/share/OVMF/OVMF_VARS_4M.fd \
  /usr/share/OVMF/OVMF_VARS.fd; do
  if [[ -r "$candidate" ]]; then vars="$candidate"; break; fi
done
args=(-machine "q35,accel=$accel" -m 8192 -smp 4
      -device virtio-vga -display gtk
      -drive "file=$disk,if=virtio,format=qcow2"
      -cdrom "$iso" -boot order=d,menu=on)
if [[ -n "$ovmf" && -n "$vars" ]]; then
  vars_copy="$vm/OVMF_VARS.fd"
  if [[ ! -e "$vars_copy" ]]; then cp -- "$vars" "$vars_copy"; fi
  args+=(-drive "if=pflash,format=raw,readonly=on,file=$ovmf"
         -drive "if=pflash,format=raw,file=$vars_copy")
  echo 'UEFI firmware (Secure Boot unverified).' >&2
else
  echo 'OVMF unavailable; legacy BIOS test only.' >&2
fi
echo 'EXPERIMENTAL ISO; no assumption of boot/install success.' >&2
echo "VM disk: $disk" >&2
exec qemu-system-x86_64 "${args[@]}"
