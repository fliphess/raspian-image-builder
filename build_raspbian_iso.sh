#!/bin/bash -x
WORKING_DIR=$( dirname $( readlink -f $0 ))

function die() { echo "Error in $0: $1"; exit 1; }

function box() {
    echo "#################################################"
    echo ">>> $1"
    echo "#################################################"
}

function main() {

  box "Setting up build environment"
    source ${WORKING_DIR}/build/settings || die "Failed to source settings file"
    mkdir -vp ${BUILD_DIR}
    mkdir -vp ${BUILD_DIR}/images


  box "Creating image file"
    source ${WORKING_DIR}/build/create-image 
    IMAGE_FILE="${BUILD_DIR}/images/raspbian_basic_${DISTRO}_${TIMESTAMP}.img"
    create_image_file

  box "Mounting and partitioning mounted disk image"
    losetup -d ${LOOP_DEVICE}
    LOOP_DEVICE=`kpartx -va ${IMAGE_FILE} | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`
    LOOP_DEVICE="/dev/mapper/${LOOP_DEVICE}"
    BOOT_PARTITION=${LOOP_DEVICE}p1
    ROOT_PARTITION=${LOOP_DEVICE}p2
    mkfs.vfat ${BOOT_PARTITION}
    mkfs.ext4 ${ROOT_PARTITION}

  box "Mounting root, proc and sys"
    mkdir -p ${CHROOT_DIR}
    mount ${ROOT_PARTITION} ${CHROOT_DIR}
    
    mkdir -p ${CHROOT_DIR}/proc
    mount -t proc none ${CHROOT_DIR}/proc
    
    mkdir -p ${CHROOT_DIR}/sys  
    mount -t sysfs none ${CHROOT_DIR}/sys

    mkdir -p ${CHROOT_DIR}/dev ; 
    mount -o bind /dev ${CHROOT_DIR}/dev

    mkdir -p ${CHROOT_DIR}/dev/pts
    mount -o bind /dev/pts ${CHROOT_DIR}/dev/pts

  box "Bootstrapping raspian"
    cd ${CHROOT_DIR}
    debootstrap --foreign --arch armhf ${DISTRO} ${CHROOT_DIR}
    cp /usr/bin/qemu-arm-static usr/bin/

    LANG=C chroot ${CHROOT_DIR} /debootstrap/debootstrap --second-stage

  box "Adjusting settings in chroot"
    source ${WORKING_DIR}/build/adjust-settings-chroot
    adjust_settings_in_chroot

  box "Creating and running third stage installer script"
    source ${WORKING_DIR}/build/third-stage
    create_third_stage
    LANG=C chroot ${CHROOT_DIR} /third-stage

  box "Creating and running update and cleanup script"
    source ${WORKING_DIR}/build/cleanup-stage
    cleanup_stage

  box "Syncing changes to partition to be sure"
    cd ${CHROOT_DIR}
    sync ; sync ; sync ; sleep 10

  box "Unmounting partitions in chroot"
    PARTITIONS=( $BOOT_PARTITION ${CHROOT_DIR}/dev/pts ${CHROOT_DIR}/dev ${CHROOT_DIR}/sys ${CHROOT_DIR}/proc ${CHROOT_DIR} ${ROOT_PARTITION} )
    for $PART in ${PARTIONS[@]} ; do
        umount -l ${PART}
    done

  box "All Done!"
}

main
