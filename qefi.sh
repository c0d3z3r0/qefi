#!/bin/sh

# Copyright (C) 2018 Michael Niewöhner
# This is open source software, licensed under GPLv2.
# See LICENSE file for details.

# Author: Michael Niewöhner (c0d3z3r0)
# Mail:   foss@mniewoehner.de

tpl_dir="$(dirname $(realpath $0))"
disk_tpl="${tpl_dir}/img/disk.img"
part_tpl="${tpl_dir}/img/part.img"
vars_tpl="${tpl_dir}/vars.fd"
keys="${tpl_dir}/keys"

usage() {
  echo "Usage: qefi <(i)nit|k(ernel)|d(isk)|c(lean)|r(einit)> [KERNEL] [FILES ...]"
  exit 1
}

clean() {
  rm -rf ${keys} $(dirname ${disk_tpl}) ${vars_tpl}
}

init() {
  [ -f ${vars_tpl} -o -e ${keys} ] && echo "Already initialized." && exit 1
  mkdir ${keys} $(dirname ${disk_tpl})

  # Create secure boot keys
  CN="test, SecureBoot"
  GUID=$(uuidgen -r | tee ${keys}/GUID.txt)
  for i in PK KEK db; do
    openssl req -new -x509 -newkey rsa:4096 -subj "/CN=${CN} ${i}/" \
      -keyout ${keys}/${i}.key -out ${keys}/${i}.crt -days 3650 -nodes -sha256
    cert-to-efi-sig-list -g ${GUID} ${keys}/${i}.crt ${keys}/${i}.esl
  done
  sign-efi-sig-list -k ${keys}/PK.key -c ${keys}/PK.crt PK ${keys}/PK.esl ${keys}/PK.auth

  # Enroll keys to VARS
  cp /usr/share/edk2/ovmf/OVMF_VARS.fd ${vars_tpl}
  echo -n -e '\x01' >/tmp/SecureBootEnable
  echo -n -e '\x00' >/tmp/CustomMode
  flash-var -g D719B2CB-3D3A-4596-A3BC-DAD00E67656F ${vars_tpl} db ${keys}/db.esl
  flash-var -g 8BE4DF61-93CA-11D2-AA0D-00E098032B8C ${vars_tpl} KEK ${keys}/KEK.esl
  flash-var -g 8BE4DF61-93CA-11D2-AA0D-00E098032B8C ${vars_tpl} PK ${keys}/PK.auth
  flash-var -g F0A30BC7-AF08-4556-99C4-001009C93A44 ${vars_tpl} SecureBootEnable /tmp/SecureBootEnable
  flash-var -g C076EC0C-7028-4399-A072-71EE5C448B9F ${vars_tpl} CustomMode /tmp/CustomMode
}

init_disk() {
  # Create disk template
  truncate -s 50M ${disk_tpl}
  sgdisk -n1:2048:+45M -t1:EF00 ${disk_tpl}
  truncate -s 1M ${disk_tpl}  # only keep parttable

  # Create filesystem template
  truncate -s 45M ${part_tpl}
  mkfs.vfat -F32 ${part_tpl}
  mmd -i ${part_tpl} ::/EFI ::/EFI/BOOT
}

runqemu() {
  tmp="$(mktemp -d)"
  vars="${tmp}/$(basename ${vars_tpl})"
  cp ${vars_tpl} ${vars}

  qemu -no-user-config -nodefaults \
    -machine q35,smm=on,accel=kvm -m 512 -smp 2 -display none -serial stdio \
    -global driver=cfi.pflash01,property=secure,value=on \
    -drive if=pflash,file=/usr/share/edk2/ovmf/OVMF_CODE.secboot.fd,format=raw,readonly \
    -drive if=pflash,file=${vars},format=raw \
    ${@}

  rm -r ${tmp}
  tput sgr0
}

boot_disk() {
  bootx64=${1}
  shift
  [ -z "${bootx64}" ] && usage

  tmp="$(mktemp -d)"
  part="${tmp}/$(basename ${part_tpl})"
  bootimg="${tmp}/boot.img"
  bootx64_signed="${tmp}/bootx64.signed"

  [ -f ${keys}/db.key -a -f ${vars_tpl} ] || init
  [ -f ${disk_tpl} -a -f ${part_tpl} ] || init_disk

  sbsign --key ${keys}/db.key --cert ${keys}/db.crt --output ${bootx64_signed} ${bootx64}
  cp ${part_tpl} ${part}
  mcopy -i ${part} ${bootx64_signed} ::/EFI/BOOT/BOOTX64.EFI
  mcopy -i ${part} ${@} ::
  cat ${disk_tpl} ${part} >${bootimg}
  truncate -s 50M ${bootimg}

  runqemu -drive file=${bootimg},format=raw,media=disk

  rm -rf ${tmp}
}

boot_kernel() {
  kernel="${1}"
  [ -z "${kernel}" ] && usage

  tmp="$(mktemp -d)"
  kernel_signed="${tmp}/kernel.signed"

  [ -f ${keys}/db.key -a -f ${vars_tpl} ] || init

  sbsign --key ${keys}/db.key --cert ${keys}/db.crt --output ${kernel_signed} ${kernel}
  runqemu -kernel ${kernel_signed}

  rm -rf ${tmp}
}

action="${1}"
shift

case "${action}" in
  k|kernel) boot_kernel ${1}
    ;;
  d|disk) boot_disk ${@}
    ;;
  i|init) init
    ;;
  c|clean) clean
    ;;
  r|reinit) clean; init
    ;;
  *) if [ -f ${action} ]; then boot_kernel ${action}; else usage; fi
    ;;
esac

exit 0
