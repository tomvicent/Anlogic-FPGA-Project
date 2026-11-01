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

# => Filename of the running script
ZN_SCRIPT_NAME="$(basename ${BASH_SOURCE[0]})"

# => Directory containing the running script
ZN_SCRIPT_DIR="$(cd "$(dirname ${BASH_SOURCE[0]})" && pwd)"

# => Help and information
usage() {
  echo "Purpose: Deploying Debian/Ubuntu Image to SD card"
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

# 2、
echo_info "Umount All Mounted Partitions"
for PART in $(lsblk /dev/${DISK} -o mountpoint --noheadings); do
  ${SUDO} umount ${PART}
done

# 3、
SDCARD_MOUNT_POINT=${ZN_SCRIPT_DIR}/sdcard && mkdir -p ${SDCARD_MOUNT_POINT}
trap "sudo umount ${SDCARD_MOUNT_POINT} &> /dev/null; sudo rm -rf ${SDCARD_MOUNT_POINT}" EXIT

for PARTITION in $(lsblk -l /dev/$DISK | grep part | awk '{print $1}'); do
  PARTNUM=${PARTITION##*[[:alpha:]]}
  case ${PARTNUM} in
    1)
      [[ $(lsblk -no FSTYPE /dev/${PARTITION}) != 'vfat' ]] && \
        error_exit "No bootable device found"

      echo_info "Mount the boot partition to ${SDCARD_MOUNT_POINT}"
      ${SUDO} mount -t vfat /dev/${PARTITION} ${SDCARD_MOUNT_POINT}

      echo_info "Install boot images to ${SDCARD_MOUNT_POINT}"
      ${SUDO} rsync -rv ${ZN_SCRIPT_DIR}/boot/ ${SDCARD_MOUNT_POINT} && sync

      echo_info "Umount the boot partition from ${SDCARD_MOUNT_POINT}"
      ${SUDO} umount ${SDCARD_MOUNT_POINT}
      ;;
    2)
      [[ $(lsblk -no FSTYPE /dev/${PARTITION}) != 'ext4' ]] && \
        error_exit "No rootfs partition found"

      echo_info "Mount the rootfs partition to ${SDCARD_MOUNT_POINT}"
      ${SUDO} mount -t ext4 /dev/${PARTITION} ${SDCARD_MOUNT_POINT}

      if [ "$(ls -A ${SDCARD_MOUNT_POINT})" != "lost+found" ]; then
        ${SUDO} umount ${SDCARD_MOUNT_POINT}
        error_exit "The ROOTFS partition is dirty, please clean it!"
      fi

      echo_info "Install rootfs images to ${SDCARD_MOUNT_POINT}"
      ${SUDO} tar zxmf ${ZN_SCRIPT_DIR}/rootfs/rootfs.tar.gz -C ${SDCARD_MOUNT_POINT} && sync
      if [ -d "${ZN_SCRIPT_DIR}/custom" ];then
        ${SUDO} rsync -av ${ZN_SCRIPT_DIR}/custom/ ${SDCARD_MOUNT_POINT} && sync
      fi

      if [ -d "${ZN_SCRIPT_DIR}/recovery" ];then
        ${SUDO} rsync -av ${ZN_SCRIPT_DIR}/recovery ${SDCARD_MOUNT_POINT} && sync
        ${SUDO} rsync -av ${ZN_SCRIPT_DIR}/boot/ ${SDCARD_MOUNT_POINT}/recovery/boot && sync
        ${SUDO} rsync -av ${ZN_SCRIPT_DIR}/custom/ ${SDCARD_MOUNT_POINT}/recovery/custom && sync
        ${SUDO} rsync -av ${ZN_SCRIPT_DIR}/rootfs/ ${SDCARD_MOUNT_POINT}/recovery/rootfs && sync
      fi

      echo_info "umount the rootfs partition from ${SDCARD_MOUNT_POINT}"
      ${SUDO} umount ${SDCARD_MOUNT_POINT}
      ;;
    *)
      echo_warn "Extra unintended partition"
      ;;
  esac
done

# => The end
print_info "[ $(date "+%Y/%m/%d %H:%M:%S") ] Finished ${ZN_SCRIPT_NAME}\n"
