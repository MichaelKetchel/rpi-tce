#!/usr/bin/env bash
set -e 
SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)
source $SCRIPT_PATH/common.sh
cd $PROJECT_PATH

#SOURCES_PATH="$(pwd)/sources"

MNT_PATH="$WORK_PATH/mnt/"
BOOT_PATH="$MNT_PATH/boot"
DATA_PATH="$MNT_PATH/data"

KERNEL_ARTIFACTS_PATH="$PROJECT_PATH/kernel/artifacts"
KEXEC_ARTIFACTS_PATH="$PROJECT_PATH/kexec/artifacts"
REBOOTP_ARTIFACTS_PATH="$PROJECT_PATH/rebootp/artifacts"
ARTIFACTS_PATH="$PROJECT_PATH/artifacts"
BASE_IMAGE="piCore64-14.1.0"
CORE_NAME="rootfs-piCore64-14.1.gz"


NEW_IMAGE_PATH=$WORK_PATH/$NEW_IMAGE_NAME.img
BASE_IMAGE_PATH=$WORK_PATH/$BASE_IMAGE.img

sudo umount -dR $MNT_PATH/* || true
sudo rm -rf $WORK_PATH/*
for path in $WORK_PATH $MNT_PATH $BOOT_PATH $DATA_PATH; do
  mkdir -p $path
done

# Build kernel
# $PROJECT_PATH/kernel/get_sources.sh
# $PROJECT_PATH/kernel/build_kernel.sh

# Build kexec tcz
# $PROJECT_PATH/kexec/get_sources.sh
# $PROJECT_PATH/kexec/run_remote_build.sh

# $PROJECT_PATH/get_sources.sh
mkdir -p $SOURCES_PATH
cd $SOURCES_PATH
wget -nc http://tinycorelinux.net/14.x/aarch64/releases/RPi/$BASE_IMAGE.zip

# TODO: Get all required tcz files and deps:
# http://tinycorelinux.net/14.x/aarch64/tcz/<tcz_file>
# parted.tcz
# ruby.tcz
# gdbm.tcz



cd $WORK_PATH


# mkdir
# sudo find | sudo cpio -o -H newc | gzip -2 > ../tinycore.gz

# unzip exiting image
unzip -o $SOURCES_PATH/$BASE_IMAGE.zip -d $WORK_PATH
# mount




# Unmount, just in case
echo "Pre-emptively unmounting"
sudo umount -q "$BOOT_PATH" || true
sudo umount -q "$DATA_PATH" || true

# # Mount image
# while IFS=';' read -ra PART_LINES; do
#   for PART_LINE in "${PART_LINES[@]:1}"; do
#     # echo "Line: $PART_LINE"
#     PART_NUM=$(echo "${PART_LINE}" | gawk 'BEGIN {RS="partition"} NR > 1 { print  $1 }' )
#     PART_START=$(echo "${PART_LINE}" | grep -Po '(?<=startsector )(\d+)')
#     PART_TYPE=$(echo "${PART_LINE}" | gawk 'BEGIN {RS="ID="}  NR > 1 {print $1}' | sed -e 's/,//')
#     PART_SIZE=$(echo "${PART_LINE}" | grep -Po '(\d+)(?= sectors)')
#     # process "$i"
#     echo "$PART_NUM -> $PART_START <-> $PART_SIZE : $PART_TYPE"

#     # If boot
#     if [[ "$PART_TYPE" == "0xc" ]]; then
#       echo "Mounting boot"
#       sudo mkdir -p "$BOOT_PATH"
#       sudo mount -o rw,sync,offset=$(( $PART_START * 512 )),sizelimit=$(( $PART_SIZE * 512 )) $BASE_IMAGE.img "$BOOT_PATH"
#     fi

#     # If data
#     if [[ "$PART_TYPE" == "0x83" ]]; then
#       echo "Mounting data"
#       sudo mkdir -p "$DATA_PATH"
#       sudo mount -o rw,sync,offset=$(( $PART_START * 512 )),sizelimit=$(( $PART_SIZE * 512 )) $BASE_IMAGE.img "$DATA_PATH"
#     fi

#   done
# done <<< "$(file $BASE_IMAGE.img)"

# Create new image with bigger size.

TCE_ROOTFS_TYPE="ext4"
TCE_PART_SIZE="131072" #128MB
# Boot partition size [in KiB] (will be rounded up to IMAGE_ROOTFS_ALIGNMENT)
BOOT_PART_SIZE="131072" # 128MB
# Set alignment to 4MB [in KiB]
IMAGE_ROOTFS_ALIGNMENT="4096"

BOOT_PART_SIZE_ALIGNED=$(( BOOT_PART_SIZE + IMAGE_ROOTFS_ALIGNMENT - 1 ))
BOOT_PART_SIZE_ALIGNED=$(( BOOT_PART_SIZE_ALIGNED - (( BOOT_PART_SIZE_ALIGNED % IMAGE_ROOTFS_ALIGNMENT)) ))

SDIMG_SIZE=$(( IMAGE_ROOTFS_ALIGNMENT + BOOT_PART_SIZE_ALIGNED + TCE_PART_SIZE ))
sudo dd if=/dev/zero of=${NEW_IMAGE_PATH} bs=1024 count=0 seek=${SDIMG_SIZE}

BOOT_PARTITION_START="${IMAGE_ROOTFS_ALIGNMENT}"
BOOT_PARTITION_END=$(( BOOT_PART_SIZE_ALIGNED + IMAGE_ROOTFS_ALIGNMENT ))

TRUNCATE_IMAGE_AFTER=${SDIMG_SIZE}


# BOOT_PARTITION_END=$(( UBOOT_PARTITION_END + BOOT_PART_SIZE_ALIGNED ))
rm -rf $NEW_IMAGE_PATH || true
sudo dd if=/dev/zero of=$NEW_IMAGE_PATH bs=1024 count=0 seek=${SDIMG_SIZE}
sudo parted -s ${NEW_IMAGE_PATH} mklabel msdos
sudo parted -s ${NEW_IMAGE_PATH} unit KiB mkpart primary fat32 ${BOOT_PARTITION_START} ${BOOT_PARTITION_END}
sudo parted -s ${NEW_IMAGE_PATH} set 1 boot on
sudo parted -s ${NEW_IMAGE_PATH} -- unit KiB mkpart primary ${TCE_ROOTFS_TYPE} ${BOOT_PARTITION_END} -1s
sudo parted ${NEW_IMAGE_PATH} print

# Format partitions
sudo kpartx -av "${NEW_IMAGE_PATH}"
kpartx_res=$(sudo kpartx -av "${NEW_IMAGE_PATH}")
print_title "$kpartx_res"


# Get loop device name
while IFS= read -r line;
do
  echo "LINE: '${line}'"
  loopdev_name=$(grep -oP '(?<=add map ).*?(?=p1 )' <<< "${line}")
  if [ ! -z "$loopdev_name" ]; then
      break
  fi
done <<< "$kpartx_res"

print_title "loopdev_name: $loopdev_name"
NEW_LOOPDEV="$loopdev_name"
sudo mkfs.vfat -F32 -n BOOT "/dev/mapper/${NEW_LOOPDEV}p1"
sudo mkfs.${TCE_ROOTFS_TYPE} -L TCE "/dev/mapper/${NEW_LOOPDEV}p2"
# sudo parted "${NEW_IMAGE_PATH}" print

# read -n 1 -p "New image basis created. Continue?"

print_title "Mounting base image"
sudo kpartx -av "${BASE_IMAGE_PATH}"
kpartx_res=$(sudo kpartx -av "${BASE_IMAGE_PATH}")
print_title "$kpartx_res"

# Get loop device name
while IFS= read -r line;
do
  echo "LINE: '${line}'"
  loopdev_name=$(grep -oP '(?<=add map ).*?(?=p1 )' <<< "${line}")
  if [ ! -z "$loopdev_name" ]; then
      break
  fi
done <<< "$kpartx_res"
BASE_LOOPDEV="$loopdev_name"

# Mount new base
sudo mount -o rw,sync /dev/mapper/${NEW_LOOPDEV}p1 "$BOOT_PATH"

echo "Base loopdev is: ${BASE_LOOPDEV}"
# Copy data from base image to new one and extend.

#sudo dd if=/dev/mapper/${BASE_LOOPDEV}p1 of=/dev/mapper/${NEW_LOOPDEV}p1
print_title "Copying data from base image to new one"
mkdir -p /tmp/basep1
sudo mount /dev/mapper/${BASE_LOOPDEV}p1 /tmp/basep1
sudo cp -ar /tmp/basep1/* "$BOOT_PATH"
sudo umount /tmp/basep1

print_title "Copying partition 2"
sudo dd if=/dev/mapper/${BASE_LOOPDEV}p2 of=/dev/mapper/${NEW_LOOPDEV}p2
# sudo fatresize /dev/mapper/${NEW_LOOPDEV}p1
sudo e2fsck -fp /dev/mapper/${NEW_LOOPDEV}p2 || true
sudo resize2fs /dev/mapper/${NEW_LOOPDEV}p2

# Mount TCE
print_title "Mounting TCE (partition 2)"
sudo mount -o rw,sync /dev/mapper/${NEW_LOOPDEV}p2 "$DATA_PATH"

# Detach base image
print_title "Detaching base image"
sudo kpartx -dv "${BASE_IMAGE_PATH}"


# read -n 1 -p "New image base created and populated. Continue?"

# Clean out old stuff
print_title "Cleaning old files..."
sudo rm -rf $BOOT_PATH/*.dtb $BOOT_PATH/overlays $BOOT_PATH/kernel*.img $BOOT_PATH/modules-*.gz

# Trim mounts
print_title "Trimming filesystems..."
sudo fstrim -v $BOOT_PATH
sudo fstrim -v $DATA_PATH

# Copy in new config and other stuff
print_title "Copying in config..."
MODULES_ARCHIVE=$(basename $(ls $KERNEL_ARTIFACTS_PATH/modules*.gz))
sudo install -o root -g root -m 755 $PROJECT_PATH/files/config.txt $BOOT_PATH/config.txt
sudo sed -i "s/MODULES_ARCHIVE/${MODULES_ARCHIVE}/" $BOOT_PATH/config.txt
sudo sed -i "s/KERNEL_IMG/kernel8.img/" $BOOT_PATH/config.txt

# read -n 1 -p "Ready to copy kernel. Continue?"

print_title "Copying in kernel, modules, and device tree files..."
# sudo install -d -o root -g root -m 755 $BOOT_PATH/overlays

sudo cp -r --preserve=mode $KERNEL_ARTIFACTS_PATH/boot/* $BOOT_PATH/
sudo install -o root -g root -m 755 $PROJECT_PATH/files/cmdline.txt $BOOT_PATH/cmdline.txt
sudo install -o root -g root -m 755 $KERNEL_ARTIFACTS_PATH/modules*.gz $BOOT_PATH/

# Install TCE packages
print_title "Installing TCE packages..."
sudo cp --preserve=mode $PROJECT_PATH/files/tce/optional/* $DATA_PATH/tce/optional/
sudo install -o 1001 -g 50 -m 664 $KEXEC_ARTIFACTS_PATH/kexec_package.tcz $DATA_PATH/tce/optional/kexec.tcz
sudo install -o 1001 -g 50 -m 664 $REBOOTP_ARTIFACTS_PATH/rebootp.tcz $DATA_PATH/tce/optional/rebootp.tcz

echo '''kexec.tcz
ruby.tcz
parted.tcz
pciutils.tcz
raspi-utils.tcz
util-linux.tcz
curl.tcz
openssl-1.1.1.tcz
rebootp.tcz''' | sudo tee -a $DATA_PATH/tce/onboot.lst


cd $DATA_PATH/tce/optional/

for filename in kexec rebootp; do
  md5sum ${filename}.tcz | sudo tee ${filename}.tcz.md5.txt
  sudo chown 1001:50 ${filename}.tcz.md5.txt
  sudo chmod 644 ${filename}.tcz.md5.txt
done

# https://wiki.tinycorelinux.net/doku.php?id=wiki:remastering
echo "Unpacking core.gz"
mkdir $WORK_PATH/core
cd $WORK_PATH/core
zcat ${BOOT_PATH}/${CORE_NAME} | sudo cpio -i -H newc -d

# read -n 1 -p "Ready to update core. Continue?"

echo "Updating core"
echo "Configuring boot scripts"
sudo sed -i 's|# /usr/sbin/startserial|/usr/sbin/startserial|g' opt/bootlocal.sh
echo 'if [ -x /home/tc/bootscript ]; then echo "Found override bootscript, executing..."; /home/tc/bootscript; else echo "Using default bootscript."; /opt/bootscript; fi' | sudo tee -a opt/bootlocal.sh
sudo install -o 0 -g 50 -m 775 $PROJECT_PATH/files/boot_script.rb opt/bootscript

echo "Configuring DHCP and DHCP hooks"
sudo install -o 0 -g 50 -m 775 $PROJECT_PATH/files/dhcp_hook.sh opt/dhcp_hook.sh
sudo sed -i '$ d' usr/share/udhcpc/default.script
sudo echo 'if test -f /opt/dhcp_hook.sh; then . /opt/dhcp_hook.sh; fi' | sudo tee -a usr/share/udhcpc/default.script
sudo sed -i -E 's|(/sbin/udhcpc)|\1 -V "RG Nets" -O 43|' etc/init.d/dhcp.sh
# read -n 1 -p "Ready to repack core. Continue?"

echo "Repacking core"
cd $WORK_PATH/core
sudo find | sudo cpio -o -H newc | gzip -2 > ../${CORE_NAME}
cd $WORK_PATH
advdef -z4 ${CORE_NAME}

echo "Replacing core"
sudo cp -r ${WORK_PATH}/${CORE_NAME} ${BOOT_PATH}/${CORE_NAME}

echo "Updating mydata.tgz"
mkdir -p ${WORK_PATH}/mydata
sudo tar --same-owner -xzvf ${DATA_PATH}/tce/mydata.tgz  -C ${WORK_PATH}/mydata/
sudo install -o 0 -g 50 -m 775 $WORK_PATH/core/opt/bootlocal.sh  ${WORK_PATH}/mydata/opt/bootlocal.sh
sudo tar -pczvf ${WORK_PATH}/mydata.tgz -C ${WORK_PATH}/mydata/ ./
sudo install -o 1001 -g 50 -m 664 ${WORK_PATH}/mydata.tgz ${DATA_PATH}/tce/mydata.tgz

cd $WORK_PATH

# Umount parts
print_title "Unmounting and cleaning up..."
sudo umount "$BOOT_PATH"
sudo umount "$DATA_PATH"

sudo kpartx -dv "${NEW_IMAGE_PATH}"
gzip -k9 "${NEW_IMAGE_PATH}"

# mv $BASE_IMAGE.img $NEW_IMAGE_NAME.img

# for i in $(file $BASE_IMAGE.img|gawk 'BEGIN {RS="startsector"} NR > 1 {print $0*512}');do
#     mount -o rw,offset=$i $BASE_IMAGE.img $where
# done


# deploy new kernel to boot
# deploy other boof files to boot
# deploy modules to boot
# update config.txt
# shouldn't need to mess with initrd yet
# deploy kexec to tce optional or onboot
