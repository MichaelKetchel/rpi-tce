#!/bin/sh

# This may help prevent failure on high PPS networks
# tftptimeout 1000

# Keep only MMC boot as a boot target - disable all other boot methods
setenv boot_targets mmc0

# enable netconsole (can be disabled if defined in env.txt as 'netconsole=0')
setenv netconsole 1

# load env file and assign some variables
load mmc 0:1 $loadaddr env.txt
env import -t $loadaddr $filesize serverip ipaddr image_name netconsole nc_ip nc_broadcast use_dhcp

# DHCP if enabled and get ips. Data looks like:
# dnsip=192.170.1.1
# ipaddr=192.170.1.53
# netmask=255.255.255.0
# gatewayip=192.170.1.1
# Possibly more than this. DHCP Opts?
# Turning off autoload prevents it from trying to boot from PXE options I think.
if test $use_dhcp = '1'; then
    echo "Getting address details from DHCP"
    setenv autoload no; dhcp;
    setenv serverip $gatewayip
    setenv autoload yes
else
    print "Using preconfigured ip ${ipaddr}"
fi

# forward the console from serial to netconsole
if test $netconsole = '1'; then
    setenv nc 'setenv stdout serial,nc;setenv stdin serial;'
    # setenv nc 'setenv stdout serial,nc;setenv stdin nc;'
    if test $nc_broadcast != '1'; then
        setenv ncip $nc_ip
    fi
    run nc
fi


echo "==== KETCH THIS U-BOOT FLASHING SCRIPT ====="
# debug print assigned addresses. 
# we assigned 'serverip' and 'ipaddr' from env.txt
printenv serverip
printenv ipaddr
printenv ethaddr
echo ""

# Get local partition info
part start mmc 0 1 l_boot_part_start
part size mmc 0 1 l_boot_part_size
# part type mmc 0:1 l_boot_part_type

# Calculate offsets
setexpr l_boot_part_end $l_boot_part_start + $l_boot_part_size
setexpr part_offset $l_boot_part_end

setexpr boot_part_start_hex $l_boot_part_start * 200
setexpr boot_part_size_hex $l_boot_part_size * 200

# Prep new MBR line
setenv new_mbr_parts "name=uboot,start=0x${boot_part_start_hex},size=0x${boot_part_size_hex},bootable,id=0x0c;"

# Reset file size counter so we can later check if tftp download succeeded
setenv filesize 0

# Init values for reading the first file to RAM
# setenv pt_size_bytes 400000
setenv ram_start_add_bytes 80000

# Get file from a remote tftp server, store in RAM
# server folder path is this device MAC address
tftpboot 0x${ram_start_add_bytes} ${serverip}:${ethaddr}/rpi_image_part_0

# If $filesize is greater than 0 - transfer probably completed
if test ${filesize} > 0; then 
    # Build a blkmap called ramdisk so we can calculate a new partition table
    blkmap create ram_disk
    setexpr fileblks ${filesize} + 0x1ff
    setexpr fileblks ${filesize} / 0x200
    blkmap map ram_disk 0 ${fileblks} mem ${fileaddr}

    # Get remote guid

    # Calculate and build new new_MBR_parts from remote image
    part list blkmap 0 r_part_numbers

    # Get part uuids for current and remote roots
    part uuid mmc 0:1 l_root_uuid
    part uuid blkmap 0:1 r_root_uuid

    # Get last part number to use for expansion
    for i in $r_part_numbers; do
        setenv r_last_part_num $i
    done

    for i in $r_part_numbers; do
        part start blkmap 0 $i r_part_start
        part size blkmap 0 $i r_part_size
        # part type blkmap 0 $i r_part_type
        setexpr new_part_num $i + 1
        
        # Hate this, but until `part type` is fixed, figuring this out another way is a real pain
        setenv part_type "83"
        if test "${i}" = "1"; then
            setenv first_r_part_start $r_part_start
            setenv part_type "0c"
            # Note blocks to skip from the start of the boot part in the image.
            setenv blocks_to_skip $r_part_start
        fi

        setexpr r_part_start $r_part_start - $first_r_part_start
        setexpr r_part_start $r_part_start + $part_offset
        setexpr r_part_start_hex $r_part_start * 0x200

        setexpr r_part_size_hex $r_part_size * 0x200
        echo "Updating part $i to $new_part_num at $r_part_start_hex"
        # echo "Updating part $i ($r_part_type) to $new_part_num at $r_part_start_hex"

        if test "${i}" = "${r_last_part_num}"; then
            # If this is the last partition, make it as big as possible.
            setenv new_mbr_parts "${new_mbr_parts}start=0x${r_part_start_hex},size=-,id=0x${part_type};"
        else
            setenv new_mbr_parts "${new_mbr_parts}start=0x${r_part_start_hex},size=0x${r_part_size_hex},id=0x${part_type};"
        fi
        setenv l_last_part_num $new_part_num
    done

    echo "MMC Partition Table:"
    part list mmc 0
    echo "Remote Image partition Table:"
    part list blkmap 0
    echo "New MBR table:"
    printenv new_mbr_parts
    # pause "New MBR built. Waiting to continue"
    # sleep 5

  

    # Calculate addresses and write first file (skipping the partition table) to MMC (SD Card)
    # setenv mmc_offset 16000
    setenv mmc_offset $part_offset
    # setexpr blocks_to_skip $pt_size_bytes / 200 ;
    setexpr first_pt_offset_bytes $blocks_to_skip * 0x200
    setexpr img_size_blk $filesize / 0x200 ;
    setexpr blocks_to_write $img_size_blk - $blocks_to_skip ;
    setexpr ram_address_bytes $ram_start_add_bytes + $first_pt_offset_bytes ;


    printenv
    # pause "Ready to write first block"
    # sleep 5

    # Destroy blkmap ram_disk because we don't need it again.
    blkmap destroy ram_disk

    # mmc write [RAM ADDRESS bytes] [MMC BLK ADDRES] [BLK COUNT]
    mmc write ${ram_address_bytes} ${mmc_offset} ${blocks_to_write} ;
    setexpr mmc_offset $mmc_offset + ${blocks_to_write} ;
    setexpr flashed_bytes $blocks_to_write * 200

    # init values needed for the rest of the files
    setenv ram_address_bytes $ram_start_add_bytes
    setenv file_not_found false

    # Iterate over the rest of the files, read to RAM and write to mmc
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        if $file_not_found ; then
            # Skip the rest of the iterations
        else 
            setenv filesize 0
            tftpboot 0x${ram_start_add_bytes} ${serverip}:${ethaddr}/rpi_image_part_$i
            if test ${filesize} > 0 ; then
                setexpr img_size_blk $filesize / 200 ;
                mmc write 0x${ram_address_bytes} 0x${mmc_offset} 0x${img_size_blk} ;
                setexpr mmc_offset $mmc_offset + 0x${img_size_blk} ;
                setexpr flashed_bytes $flashed_bytes + $filesize ;
            else 
                setenv file_not_found true
            fi 
        fi
    done

    echo "flashed_bytes = $flashed_bytes"
    # pause "About to write MBR, waiting."
    # sleep 5
    mbr write mmc 0 "${new_mbr_parts}"
    mbr verify mmc 0 "${new_mbr_parts}"

    # We deleted this file before flashing, if it exists - flashing succeeded
    #if fatload mmc 0:2 ${loadaddr} image-version-info; then 
    #    setenv status OK
    #else
    #    setenv status FAILED
    #fi
    setenv status OK

    # Load written size memory and save it as a file on TFTP server
    mw.l ${loadaddr} ${flashed_bytes}
    tftpput ${loadaddr} 4 ${serverip}:${ethaddr}/${status}


    # Rescan to get disk id
    mmc rescan

    # Updating fstab
    echo "Updating fstab entries"
    setenv fstab_mem_addr 0x00200000
    ext4load mmc 0:$l_last_part_num $fstab_mem_addr /etc/fstab
    setenv fstab_size $filesize
    # ext4load mmc 0:3 0x00200006 /etc/fstab
    # setexpr fstab_size $filesize + 6
    # mw.w 0x00200000 0x7366 
    # mw.l 0x00200002 0x3d626174
    # md.b 0x00200000 ${fstab_size}

    
    # Get base UUIDs
    setenv l_base_uuid $l_root_uuid
    setenv r_base_uuid $r_root_uuid
    setexpr l_base_uuid sub "([^-]+)-.." "\1"
    setexpr r_base_uuid sub "([^-]+)-.." "\1"

    # Rewrite all fstab mappings
    for i in $r_part_numbers; do
        setexpr current_part_number $l_last_part_num - $i
        setexpr current_part_number $current_part_number + 1
        setexpr current_part_number_offset $current_part_number + 1
        replmem $fstab_mem_addr $fstab_size "PARTUUID=${r_base_uuid}-0${current_part_number}" "PARTUUID=${l_base_uuid}-0${current_part_number_offset}" fstab_size
    done

    # Write new fstab
    ext4write mmc 0:$l_last_part_num $fstab_mem_addr /etc/fstab $fstab_size
fi;

# pause "Flash complete, waiting."
# sleep 5
# load cmdline.txt file to memory (used foor bootcmd)
load mmc 0:2 0x00200008 cmdline.txt
## calc new filesize
setexpr cmdline_size $filesize + 8

# modify memory, add "cmdline=" before the data (else env import wont work)
mw.l 0x00200000 0x6c646d63   
mw.l 0x00200004 0x3d656e69   

# load the memory as env
env import -t 0x00200000 $cmdline_size cmdline

echo ""
echo "Original bootargs:"
printenv cmdline
echo ""

echo "substituting rootfs partition: mmcblk0p2 -> mmcblk0p3"
setexpr cmdline sub mmcblk0p2 mmcblk0p3
echo ""
echo "substituting serial output: serial0 -> ttyS0"
setexpr cmdline sub serial0 ttyS0
echo ""

part uuid mmc 0:3 part_uuid
echo "Substituting PARTUUID values"
setexpr cmdline sub "root=PARTUUID=[^-]+-02" "root=PARTUUID=${part_uuid}"


# echo "Removing resize hook REMOVE THIS BEFORE PROD!"
# setexpr cmdline sub "init=/usr/lib/raspi-config/init_resize.sh" ""

# Set boot command
setenv bootargs ${cmdline} 8250.nr_uarts=1 initcall_blacklist=bcm2708_fb_init

echo "New bootargs:"
printenv bootargs
echo ""

# echo "Loading DTB file:"
# printenv fdtfile

# # Load blobs to ram
# fatload mmc 0:2 ${fdt_addr_r} ${fdtfile}
# echo ""

echo "Loading Kernel image kernel8.img:"
fatload mmc 0:2 ${kernel_addr_r} kernel8.img
echo ""

# echo "Loading ramdisk"
# fatload mmc 0:2 ${ramdisk_addr_r} initramfs8
# echo ""

setenv kernel_comp_addr_r 0x1400000
setenv kernel_comp_size 0x6000000

# pause "About to boot kernel"
# sleep 5
echo "Booting.."
# Boot file kernel and device
# booti ${kernel_addr_r} - ${fdt_addr_r}
# booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr}
# booti ${kernel_addr_r} - ${fdt_addr}
