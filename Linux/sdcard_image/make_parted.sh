#!/bin/bash
###############################################################################
#
#Company : Liyang Milian Electronic Technology Co., Ltd.
#Brand: 米联客(msxbo)
#Technical forum:uisrc.com
#taobao: osrc.taobao.com
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
###############################################################################
# => Force locale language to be set to English. This avoids issues when doing
# text and string processing.
export LC_ALL=C LANGUAGE=C LANG=C

# => Filename of the running script
ZN_SCRIPT_NAME="$(basename ${BASH_SOURCE[0]})"

# => Directory containing the running script
ZN_SCRIPT_DIR="$(cd "$(dirname ${BASH_SOURCE[0]})" && pwd)"

# => Help and information
usage() {
  echo "Usage  : source ${ZN_SCRIPT_NAME}"
  echo "Purpose: Repartition SD Card"
  echo "Usage  : ${ZN_SCRIPT_NAME} [option]"
  echo "options:"
  echo "--help: Display this help message"
  
  exit 0;
}
expr "$*" : ".*--help" > /dev/null && usage

# => Import local function from common.sh
if [ -f "${ZN_SCRIPT_DIR}/common.sh" ]; then
  source ${ZN_SCRIPT_DIR}/common.sh
else
  printf "\033[31m[ERROR]\033[0m "
  printf "Could not find file '${ZN_SCRIPT_DIR}/common.sh'\n"
  exit 1
fi

# => The beginning
print_info "[ $(date "+%Y/%m/%d %H:%M:%S") ] Starting ${ZN_SCRIPT_NAME}\n"

# => Only use sudo if not running as root:
[ "$(id -u)" -ne 0 ] && export SUDO="sudo" || export SUDO=""

# => Check for dependencies
if ! type parted > /dev/null 2>&1; then
  echo_info "Installing parted..."
  ${SUDO} apt-get update && ${SUDO} apt-get --assume-yes install parted
  echo_info "Done!"
fi

# 0、 Plug in your SD Card to your Linux machine.

# 1、Determine what device to use
DISKS=($( grep -Hv ^0$ /sys/block/*/removable | sed s/removable:.*$/device\\/uevent/ |
  xargs grep -H ^DRIVER=sd | sed s/device.uevent.*$/size/ | xargs grep -Hv ^0$ |
  cut -d / -f 4 ))

for i in "${!DISKS[@]}"; do DISKS[$i]="/dev/${DISKS[$i]}"; done

until [[ -b /dev/${DISK} && ${DISKS[@]/"/dev/${DISK}"/} != ${DISKS[@]} ]]; do
  lsblk -d "${DISKS[@]}" -o NAME,RM,SIZE,TYPE,MODEL,SERIAL
  print_info "Type device filename, or press <Enter> to exit: " && read DISK
  [[ -z ${DISK} ]] && exit 0
done

# 2. Remove All Existing Partitions
print_warn "ALL DATA ON ${DISK} WILL BE ERASED!!! DO YOU WANT TO CONTINUE [y/N]? " && read REPLY
case ${REPLY} in
  y|Y)
    echo_info "Umount All Mounted Partitions"
    for part in $(lsblk /dev/${DISK} -o mountpoint --noheadings); do
      ${SUDO} umount ${part}
    done

    echo_info "Remove All Existing Partitions from ${DISK}"
    for PARTITION in $(${SUDO} parted /dev/${DISK} print | awk '/^ /{print $1}'); do
      ${SUDO} parted -s /dev/${DISK} rm ${PARTITION}
    done

    echo_info "Choose the MBR Partitioning Standard"
    ${SUDO} parted -s /dev/${DISK} mklabel msdos

    echo_info "Create the fat32 partition of 100MB and make it bootable"
    ${SUDO} parted -s /dev/${DISK} mkpart primary fat32 0% 100MiB && ${SUDO} parted -s /dev/${DISK} set 1 boot on

    echo_info "Create the ext4 partition until end of device"
    ${SUDO} parted -s /dev/${DISK} mkpart primary ext4 100MiB 100%

    echo_info "Re-read The Partition Table Without Rebooting Linux System"
    ${SUDO} partprobe /dev/${DISK} && sleep 1 && lsblk /dev/${DISK}

    # Create a Filesystem on the New Partition
    for PARTITION in $(lsblk -l /dev/${DISK} | grep part | awk '{print $1}'); do
      PARTNUM=${PARTITION##*[[:alpha:]]}
      case ${PARTNUM} in
        1)
          echo_info "To format a FAT32 filesystem on /dev/${PARTITION} with a 'BOOT' disk label"
          ${SUDO}  mkfs.vfat -F 32 -n "BOOT" /dev/${PARTITION}
          ;;
        2)
          echo_info "To format an ext4 filesystem on /dev/${PARTITION} with a 'rootfs' disk label"
          echo y | ${SUDO} mkfs.ext4 -L rootfs /dev/${PARTITION}
          ;;
        *)
          echo_warn "Extra unintended partition"
          ;;
      esac
    done

    ;;
  *)
    ;;
esac

# => The end
print_info "[ $(date "+%Y/%m/%d %H:%M:%S") ] Finished ${ZN_SCRIPT_NAME}\n"
