#!/usr/bin/env python3
import json
import re
import subprocess
import os
from pprint import pp
import sys
import logging
from typing import Optional

import parted
from getpass import getpass


logger = logging.getLogger()
logger.setLevel(logging.DEBUG)
handler = logging.StreamHandler()
formatter = logging.Formatter('%(asctime)s [%(levelname)s] %(message)s')
handler.setFormatter(formatter)
logger.addHandler(handler)


script_path = os.path.realpath(__file__)
logger.info(f"The real path of this script is {script_path}")
directory, script = os.path.split(script_path)


def load_var_from_common(varname:str):
    return subprocess.check_output(f"bash -c '. ./common.sh && echo ${varname}'", shell=True, cwd=directory).decode('utf-8').strip()

SCRIPT = load_var_from_common("SCRIPT")
SCRIPT_PATH = load_var_from_common("SCRIPT_PATH")
WORK_PATH = load_var_from_common("WORK_PATH")
NEW_IMAGE_NAME = load_var_from_common("NEW_IMAGE_NAME")

MNT_PATH=f"{WORK_PATH}/mnt/"
BOOT_PATH=f"{MNT_PATH}/boot"
DATA_PATH=f"{MNT_PATH}/data"

ADDON_IMAGE_PATH = sys.argv[1] if len(sys.argv) > 1 else None
if ADDON_IMAGE_PATH is None:
    raise Exception("An addon image must be provided")

ADDON_IMAGE_FILENAME = os.path.basename(ADDON_IMAGE_PATH)
ADDON_IMAGE_NAME, _ = os.path.splitext(ADDON_IMAGE_FILENAME)

NEW_IMAGE_PATH = f"{WORK_PATH}/{NEW_IMAGE_NAME}-{ADDON_IMAGE_NAME}.img"
BASE_IMAGE_PATH = f"{WORK_PATH}/{NEW_IMAGE_NAME}.img"


def is_root():
    return os.geteuid() == 0

def test_sudo(pwd=""):
    args = "sudo -S echo OK".split()
    kwargs = dict(stdout=subprocess.PIPE,
                  encoding="ascii")
    if pwd:
        kwargs.update(input=pwd)
    cmd = subprocess.run(args, **kwargs)
    return ("OK" in cmd.stdout)

def prompt_sudo():
    ok = is_root() or test_sudo()
    if not ok:
        pwd = getpass("password: ")
        ok  = test_sudo(pwd)
    return ok


def obtain_sudo_pass():
    sudo_pass: Optional[str] = None
    if not (is_root() or test_sudo()):
        while True:
            sudo_pass = getpass("Sudo Password: ")
            if test_sudo(sudo_pass):
                break
            print("Wrong password, try again.")
    return sudo_pass


def run_with_sudo(args: list[str], pwd: Optional[str]= None, shell=False, raise_on_error=True):
    if not pwd:
        pwd = obtain_sudo_pass()

    runtime_args:list[str]|str = ["sudo", "-S"]
    runtime_args.extend(args)
    if shell:
        runtime_args = " ".join(runtime_args)
    kwargs = dict(stdout=subprocess.PIPE,
                  encoding="ascii",
                  shell=shell)
    if pwd:
        kwargs.update(input=pwd)
    cmd = subprocess.run(runtime_args, **kwargs)
    if raise_on_error and cmd.returncode != 0:
        raise Exception(f"Execution of  {runtime_args} returned code {cmd.returncode}: {cmd.stderr}")
    return cmd



def main():
    # logger = getLogger(__name__)
    logger.info("Let's go!")

    sudo_pass = obtain_sudo_pass()

    # # Get the file name without extension from ADDON_IMAGE_PATH
    addon_image_size = os.path.getsize(ADDON_IMAGE_PATH)
    logger.info(f"The size of {ADDON_IMAGE_NAME} is: {addon_image_size} bytes")


    target_blkid = run_with_sudo(["blkid", BASE_IMAGE_PATH], pwd=sudo_pass).stdout
    source_blkid = run_with_sudo(["blkid", ADDON_IMAGE_PATH], pwd=sudo_pass).stdout

    regex = r"PTUUID=\"(\w+)\""
    target_blkid = re.search(regex, target_blkid).group(1)
    source_blkid = re.search(regex, source_blkid).group(1)
    

    logger.info(f"Copying base image from {BASE_IMAGE_PATH} to work with")
    os.system(f'cp {BASE_IMAGE_PATH} {NEW_IMAGE_PATH}')

    logger.info(f"Extending base image to an additional {(addon_image_size/1024/1024)} MB")
    # run_with_sudo([f"dd if=/dev/zero bs=1M count={(addon_image_size/1024)} >> {NEW_IMAGE_PATH} "], shell=True, pwd=sudo_pass)
    logger.debug(f"dd if=/dev/zero bs=1M count={(int(addon_image_size/1024/1024))} >> {NEW_IMAGE_PATH} ")
    os.system(f"dd if=/dev/zero bs=1M count={(int(addon_image_size/1024/1024))} >> {NEW_IMAGE_PATH} ")
    # with open(NEW_IMAGE_PATH, 'ab') as fout:  # append binary mode

    #     fout.truncate(int(addon_image_size))



    new_device = parted.getDevice(NEW_IMAGE_PATH)
    addon_device = parted.getDevice(ADDON_IMAGE_PATH)

    new_disk = parted.newDisk(new_device)
    addon_disk = parted.newDisk(addon_device)

    free_space_regions = new_disk.getFreeSpaceRegions()
    # free_geometry = free_space_regions[-1]

    current_end_block = new_disk.partitions[1].geometry.end

    source_partition_number:int = 0
    target_partition_number:int = new_disk.partitions[-1].number
    parts_to_copy: list[tuple[int]] = []
    for addon_partition in (addon_disk.partitions):
        logger.info(f"Creating partition {addon_partition.name}")
        source_partition_number = addon_partition.number
        new_start_block = current_end_block + 1

        new_geometry = parted.Geometry(device=new_device, start=new_start_block, length=addon_partition.geometry.getLength())
        new_fs = parted.FileSystem(type= addon_partition.fileSystem.type, geometry=new_geometry)
        new_part = parted.Partition(disk=new_disk, type=parted.PARTITION_NORMAL, fs = new_fs, geometry=new_geometry)

        # if addon_partition.fileSystem.type == 'fat32':
        #     # It must be a boot partition.
        #     new_part.setFlag(parted.PARTITION_BOOT)
        #
        # new_disk.addPartition(new_part, constraint=new_device.optimalAlignedConstraint)
        # new_disk.commit()
        parted_command = f"parted -s {NEW_IMAGE_PATH} unit B mkpart primary {addon_partition.fileSystem.type} {new_geometry.start*512} {new_geometry.end*512} "
        logger.debug(f"Parted CMD: {parted_command}")
        res = run_with_sudo([parted_command],shell=True, pwd=sudo_pass)
        pp(res)

        logger.info("created partition OK")
        target_partition_number+=1
        parts_to_copy.append((source_partition_number, target_partition_number, addon_partition.fileSystem.type))
        current_end_block = new_part.geometry.end

    logger.info("Partitions created. Cloning.")

    # Create two loopback devices for each image
    # os.system(f'sudo -S losetup -D')  # Remove all existing loopback devices
    # run_with_sudo(f'losetup -D'.split(' '), pwd=sudo_pass)
    # img1_res =  run_with_sudo(['losetup -P --find --show ' + NEW_IMAGE_PATH], pwd=sudo_pass, shell=True)
    # img1_loop =img1_res.stdout.strip()
    # img2_res = run_with_sudo(['losetup -P --find --show ' + ADDON_IMAGE_PATH], pwd=sudo_pass, shell=True)
    # img2_loop = img2_res.stdout.strip()



    img1_res = run_with_sudo(['kpartx -sav ' + NEW_IMAGE_PATH], pwd=sudo_pass, shell=True)
    img1_parts = [a.split()[2] for a in img1_res.stdout.strip().split('\n')]
    img2_res = run_with_sudo(['kpartx -sav ' + ADDON_IMAGE_PATH], pwd=sudo_pass, shell=True)
    img2_parts = [a.split()[2] for a in img2_res.stdout.strip().split('\n')]

    for pair in parts_to_copy:  # For each pair of partitions to copy
        # src_part = f'{img2_loop}p{pair[0]}'  # Source partition on addon image
        # dst_part = f'{img1_loop}p{pair[1]}'  # Destination partition on new image
        src_part = img2_parts[pair[0]-1]  # Source partition on addon image
        dst_part = img1_parts[pair[1]-1]  # Destination partition on new image

        if pair[2] == "fat32":
            run_with_sudo([f"mkfs.vfat -F32 /dev/mapper/{dst_part}"], shell=True, pwd=sudo_pass)
        else:
            run_with_sudo([f"mkfs.{pair[2]} /dev/mapper/{dst_part}"], shell=True, pwd=sudo_pass)

        logger.info(f"Cloning {ADDON_IMAGE_PATH}:{pair[0]} to {NEW_IMAGE_PATH}:{pair[1]}")
        run_with_sudo(['dd', f"if=/dev/mapper/{src_part}", f"of=/dev/mapper/{dst_part}", "bs=1024"] , pwd=sudo_pass)
        logger.info(f"Done")
        # os.system(f'mount {src_part} {MNT_PATH}')  # Mount source partition
        # src_files = glob(f'{MNT_PATH}/*')  # Get list of all files in source partition
        # for file in src_files:
        #     base = os.path.basename(file)
        #     if os.path.isfile(file):  # If it's a regular file, copy it to destination
        #         os.system(f'cp {file} {dst_part}/{base}')
        #     else:  # If it's a directory, create it on the new image if it doesn't exist yet
        #         os.system(f'mkdir -p {dst_part}/{base}')
        # os.system(f'umount {MNT_PATH}')  # Unmount source partition

    # os.system('sudo losetup -D')  # Remove loopback devices after we're done

    # TODO: Lots of assumptions here/
    run_with_sudo("mkdir -p /mnt/sdboot".split(' '), pwd=sudo_pass)
    run_with_sudo("mkdir -p /mnt/sdroot".split(' '), pwd=sudo_pass)
    run_with_sudo(f"mount /dev/mapper/{img1_parts[2]} /mnt/sdboot".split(' '), pwd=sudo_pass)
    run_with_sudo(f"mount /dev/mapper/{img1_parts[3]} /mnt/sdroot".split(' '), pwd=sudo_pass)

    for srcPartId,dstPartId,_ in parts_to_copy:
        run_with_sudo([f"sed -i 's/PARTUUID={source_blkid}-{str(srcPartId).zfill(2)}/PARTUUID={target_blkid}-{str(dstPartId).zfill(2)}/g' /mnt/sdboot/cmdline.txt"], shell=True, pwd=sudo_pass)
        run_with_sudo([f"sed -i 's/PARTUUID={source_blkid}-{str(srcPartId).zfill(2)}/PARTUUID={target_blkid}-{str(dstPartId).zfill(2)}/g' /mnt/sdroot/etc/fstab"], shell=True, pwd=sudo_pass)

    # run_with_sudo([
    #                   f"sed -i 's| init=/usr/lib/raspi-config/init_resize\.sh||' /mnt/sdboot/cmdline.txt"],
    #               shell=True, pwd=sudo_pass)

    # run_with_sudo([ f"sed -i 's| sdhci\.debug_quirks2=4||' /mnt/sdboot/cmdline.txt"], shell=True, pwd=sudo_pass)

    run_with_sudo(f"umount /mnt/sdboot".split(' '), pwd=sudo_pass)
    run_with_sudo(f"umount /mnt/sdroot".split(' '), pwd=sudo_pass)


    # Write BL data to main boot:

    logger.info("Writing BLData file")
    md5sum = run_with_sudo(["md5sum", ADDON_IMAGE_PATH]).stdout.split()[0]
    bl_data = {
        "current_image_md5": md5sum,
        "last_flash_success": True,
        "boot_exec_times": [],
        "first_boot": True,
        "remote_log": False,
        "boot_server_override": None,
    }
    run_with_sudo(f"mount /dev/mapper/{img1_parts[2][:-1]}1 /mnt/sdboot".split(' '), pwd=sudo_pass)
    run_with_sudo(f"touch /mnt/sdboot/bldata.json".split(' '), pwd=sudo_pass, raise_on_error=False)
    run_with_sudo(f"chmod 777 /mnt/sdboot/bldata.json".split(' '), pwd=sudo_pass, raise_on_error=False)
    with open('/tmp/bldata.json', 'w') as f:
        f.write(json.dumps(bl_data))  # Replace with actual value
    run_with_sudo(f"cp /tmp/bldata.json /mnt/sdboot/bldata.json".split(' '), pwd=sudo_pass, raise_on_error=True)
    run_with_sudo(f"umount /mnt/sdboot".split(' '), pwd=sudo_pass)



    img1_res = run_with_sudo(['kpartx -dv ' + NEW_IMAGE_PATH], pwd=sudo_pass, shell=True)
    img2_res = run_with_sudo(['kpartx -dv ' + ADDON_IMAGE_PATH], pwd=sudo_pass, shell=True)
    # run_with_sudo(f'losetup -D'.split(' '), pwd=sudo_pass)


if __name__ == "__main__":
    main()