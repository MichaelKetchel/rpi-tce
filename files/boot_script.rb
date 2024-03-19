#!/usr/local/bin/ruby
require 'json'
# Maybe could use /usr/bin/env ruby, but the above is the known path on TCE.

def bigputs (args)
    puts "#### #{args} ####"
end

# fdisk -x /dev/mmcblk0
BOOT_THRASH_THRESHOLD = 4
BOOT_EXEC_MAX_ENTRIES = 10
MAX_BOOT_ADDRESS_WAIT = 60

STARTING_DIR = File.expand_path(File.dirname(__FILE__))
IMG_SERVER='http://192.170.1.51:8080'
# IMGFILE="2023-12-11-raspios-bookworm-arm64-lite.img"
# IMGFILE="piglet-0089_20240221-005554_9bf6837e.img"
IMGFILE="piglet-0135_20240315-080026_cb70731d.img.gz"
IMG_PATH="/tmp/#{IMGFILE}"
BOOT_DEVICE="/dev/mmcblk0"
BOOT_DATA_PART="#{BOOT_DEVICE}p2"
IMG_BEGINNING_PATH="#{IMG_PATH}.begin"
NO_BOOT_PATH="#{IMG_SERVER}/noboot"
LOCAL_DATA_FILE="/mnt/mmcblk0p2/tce/bldata.json"

$local_data = {
    current_image_md5: nil,
    last_flash_success: false,
    boot_exec_times: [],
    first_boot: true,
}

class SysExecError < StandardError
    attr_reader :return_code
    attr_reader :cmd
    attr_reader :res
    attr_reader :caller
    def initialize(msg="An error occured running a shell command", cmd='', res='', return_code=-1, caller=nil)
      @return_code = return_code
      @cmd = cmd
      @res = res
      @caller = caller
      super(msg)
    end
  end

def set_exit enable
    if enable
      define_method :system do |*args|
        res = Kernel.system *args
        puts "Exec: #{args}"
        raise SysExecError.new("Error executing system command \"#{args}\": (#{$?.exitstatus})",args.to_s, res, $?.exitstatus, caller_locations) unless $?.success?
        return res
        # exit $?.exitstatus unless $?.success?
      end
      define_method :` do |args|
        define_method :backtick_method , Kernel.instance_method(:`)
        puts "Exec: #{args}"
        res = backtick_method args
        raise SysExecError.new("Error executing backtick command \"#{args}\": (#{$?.exitstatus})",args.to_s, res, $?.exitstatus, caller_locations) unless $?.success?
        return res
        # exit $?.exitstatus unless $?.success?
      end
    else
      define_method :system, Kernel.instance_method(:system)
      define_method :`, Kernel.instance_method(:`)
    end
  end
  
#   set_exit true
#   # ...
#   # any failed system calls here will cause your script to exit
#   # ...
#   set_exit false

def save_local_data
    mounted = `mount` =~ /#{BOOT_DATA_PART.gsub('/','\/')} on/
    `mount #{BOOT_DATA_PART}` unless mounted
    File.open(LOCAL_DATA_FILE, 'w') do |f|
        f.write($local_data.to_json)
    end
    `umount #{BOOT_DATA_PART}` unless mounted
end

def load_local_data
    mounted = `mount` =~ /#{BOOT_DATA_PART.gsub('/','\/')} on/
    `mount #{BOOT_DATA_PART}` unless mounted
    if File.file?(LOCAL_DATA_FILE)
        File.open (LOCAL_DATA_FILE) do |f|
            $local_data.merge!(JSON.load(f))
        end        
    else
        save_local_data
    end
    `umount #{BOOT_DATA_PART}` unless mounted
end

def flash_os_image
    begin
        puts "Script starting in: #{STARTING_DIR}"
        puts "Fetching flash image"
        set_exit true
        
        `wget #{IMG_SERVER}/#{IMGFILE} -P /tmp` unless File.file?("/tmp/#{IMGFILE}")
        `wget #{IMG_SERVER}/#{IMGFILE}.md5.txt -P /tmp` unless File.file?("/tmp/#{IMGFILE}.md5.txt")
        `cd /tmp; md5sum -c #{IMGFILE}.md5.txt;`
        `cd #{STARTING_DIR};`

        new_md5 = `cat /tmp/#{IMGFILE}.md5.txt`.split[0]
        if new_md5 == $local_data['current_image_md5'] && $local_data[:last_flash_success]
            puts "Identical image already flashed successfully, skipping flash."
            return true
        else 
            puts "New image has MD5 has of #{new_md5}"
            $local_data['current_image_md5'] = new_md5
        end

        # Get first chunks for img beginning
        puts "Reading image partition table"
        `gzip -dc #{IMG_PATH} | dd bs=8M count=1 iflag=fullblock > #{IMG_BEGINNING_PATH}`

        local_part_details = `fdisk -l #{BOOT_DEVICE} -o device,start,end,id,boot | grep #{BOOT_DEVICE}`
        local_part_details = local_part_details.split("\n")[1..2].map{|line| line.split(" ")}

        img_part_details = `fdisk -l #{IMG_BEGINNING_PATH} -o device,start,end,id,boot | grep .img`
        puts img_part_details
        img_part_details = img_part_details.split("\n")[1..2].map{|line| line.split(" ")}

        # Use last local partition end to calculate offset 
        # Base sector size is going to be 512bytes because SD card
        seek_sectors = local_part_details.last[2].to_i + 1
        puts ("Seek sectors: #{seek_sectors}")

        # Use start of first img partition end to calculate skip
        # puts img_part_details
        img_skip_sectors = img_part_details.first[1].to_i
        puts ("Image skip sectors: #{img_skip_sectors}")


        # Well.. it might be just that easy. Write the flashed image to disk.
        dd_cmd = "gzip -dc #{IMG_PATH} | dd of=#{BOOT_DEVICE} bs=8M iflag=skip_bytes,fullblock oflag=seek_bytes skip=#{img_skip_sectors*512} seek=#{seek_sectors*512}"
        puts "Will run: sudo #{dd_cmd}"
        # output=`ls no_existing_file` ;  result=$?.success?
        output = `sudo #{dd_cmd}`


        # Update partition table
        bigputs("Updating partition table")
        puts("Removing extra partitions if present")
        `sudo umount #{BOOT_DEVICE}p3 || true`
        `sudo umount #{BOOT_DEVICE}p4 || true`
        `sudo parted -s #{BOOT_DEVICE} rm 3 || true`
        `sudo parted -s #{BOOT_DEVICE} rm 4 || true`

        puts("Creating new partitions")
        for part in img_part_details do
            part_offset_bytes = (seek_sectors*512)
            img_start_offset_bytes = (img_skip_sectors*512)

            # Todo, make this more robust
            part_types = {
                'c' => 'fat32',
                '83' => 'ext4',
            }

            parted_cmd = "parted -s #{BOOT_DEVICE} -- unit B mkpart primary #{part_types[part[3]]} #{part[1].to_i * 512 - img_start_offset_bytes + part_offset_bytes}B  #{part[2].to_i * 512 - img_start_offset_bytes + part_offset_bytes}B"
            puts "Created partition with cmd: #{parted_cmd}"
            `sudo #{parted_cmd}`
            # TODO: Add boot flag?
            # sudo parted -s ${NEW_IMAGE_PATH} set 1 boot on

        end

        puts "Sleeping 10 seconds for filesystems to be detected..."
        `sudo rebuildfstab`
        `sudo fdisk -l`
        sleep 10

        bigputs("Extending partitions and FS")

        puts "Resizing and checking partitions"
        `sudo parted /dev/mmcblk0 "resizepart 4 -0"`
        `sudo e2fsck -fp /dev/mmcblk0p4`
        `sudo resize2fs /dev/mmcblk0p4`

        puts "Mounting filesystems"
        `sudo mkdir -p /mnt/mmcblk0p3`
        `sudo mkdir -p /mnt/mmcblk0p4`
        `sudo mount /dev/mmcblk0p1 /mnt/mmcblk0p1` unless `mount` =~ /\/dev\/mmcblk0p1 on/
        `sudo mount /dev/mmcblk0p3 /mnt/mmcblk0p3` unless `mount` =~ /\/dev\/mmcblk0p3 on/
        `sudo mount /dev/mmcblk0p4 /mnt/mmcblk0p4` unless `mount` =~ /\/dev\/mmcblk0p4 on/

        # sudo kexec -d --type zImage --dtb /mnt/mmcblk0p3/bcm2711-rpi-4-b.dtb --serial ttyAMA0 --command-line "$(cat /mnt/mmcblk0p3/cmdline.txt)" -l /mnt/mmcblk0p3/kernel8.img
        # sudo kexec -d --type Image --dtb /mnt/mmcblk0p3/bcm2711-rpi-4-b.dtb --serial ttyAMA0 --command-line "$(cat /mnt/mmcblk0p3/cmdline.txt)" -l /mnt/mmcblk0p3/kernel8-b.img
        # sudo kexec -a -x --type zImage --dtb /mnt/mmcblk0p3/bcm2711-rpi-4-b.dtb --command-line "$(cat /mnt/mmcblk0p3/cmdline.txt) init=/sbin/init debug rootwait" -l /mnt/mmcblk0p3/kernel8.img
        # sudo kexec -e 

        img_blkid_partuuid = `blkid #{IMG_BEGINNING_PATH}`[/PTUUID="(\w+)"/,1]
        #92c1f194
        boot_blkid_partuuid = `blkid #{BOOT_DEVICE}`[/PTUUID="(\w+)"/,1]
        #30b3401a


        puts "Updating cmdline.txt"
        puts "IMG partuuid: #{img_blkid_partuuid}"
        puts "Boot partuuid: #{boot_blkid_partuuid}"
        # Update cmdline
        (0..7).each do |part_num|
            `sudo sed -i 's/PARTUUID=#{img_blkid_partuuid}-0#{part_num}/PARTUUID=#{boot_blkid_partuuid}-0#{part_num + 2}/g' /mnt/mmcblk0p3/cmdline.txt`
        end
        `sudo sed -i 's| init=/usr/lib/raspi-config/init_resize\.sh||' /mnt/mmcblk0p3/cmdline.txt`
        `sudo sed -i 's| sdhci\.debug_quirks2=4||' /mnt/mmcblk0p3/cmdline.txt`

        puts "Updating fstab"
        # Update fstab
        (0..7).each do |part_num|
            `sudo sed -i 's/PARTUUID=#{img_blkid_partuuid}-0#{part_num}/PARTUUID=#{boot_blkid_partuuid}-0#{part_num + 2}/g' /mnt/mmcblk0p4/etc/fstab`
        end
        set_exit false
        return true

    rescue SysExecError => exception
        puts "An exception occurred running a shell command: #{exception.cmd} (#{exception.return_code}): #{exception.res}"
        puts "Exception: #{exception.inspect}\n\t#{exception.backtrace.join("\n\t")}"
        return false
    rescue Exception => exception
        puts "An unknown error occurred while flashing: #{exception} #{exception.message}"
        puts "Exception: #{exception.inspect}\n\t#{exception.backtrace.join("\n\t")}"
        return false
    end
end

def do_boot
    puts "Deciding whether to boot"
    unless $local_data[:last_flash_success]
        puts "Last flash failed. Restarting to try again."
        `sudo rebootp 1`
    end
    puts "Checking for noboot file..."
    no_boot = `curl -sf #{NO_BOOT_PATH}`
    result=$?.success?
    unless result and no_boot.strip.downcase =~ /true|1|yes/
        puts "Booting..."
        `sudo rebootp 3`
    end
    puts "Not booting."
end

# Load local data, make note of our boot time, and check the last n times to make sure we're not thrashing
load_local_data
$local_data[:boot_exec_times].append(Time.now)
$local_data[:boot_exec_times] = $local_data[:boot_exec_times].last(BOOT_EXEC_MAX_ENTRIES)
# Handle first boot tasks like saving ssh keys
if $local_data[:first_boot]
    $local_data[:first_boot] = false
    save_local_data
    `filetool.sh -b`
end

# Sense ethernet and wait for address

current_wait=0
while !system('ifconfig eth0 | grep "inet addr:" > /dev/null 2>&1')
    puts "Waiting for address..."
    sleep 5
    if current_wait > MAX_BOOT_ADDRESS_WAIT && $local_data[:last_flash_success]
        puts "Maximum wait exceeded, booting old image."
        do_boot
    end
end


should_flash = `curl #{IMG_SERVER}/doflash`.strip.downcase =~ /true|1|yes/
should_flash = false unless $?.success?

# Decide whether to pull and flash or just go straight to boot.
if should_flash
    $local_data[:last_flash_success] = flash_os_image     
end
save_local_data
do_boot



# # get new partuuids with blkid
# sudo sed -i 's/4e639091-02/30b3401a-03/g' /mnt/mmcblk0p3/cmdline.txt
# sudo sed -i 's/ quiet/ /g' /mnt/mmcblk0p3/cmdline.txt
# sudo sed -i 's/4e639091-01/30b3401a-02/g' /mnt/mmcblk0p4/etc/fstab
# sudo sed -i 's/4e639091-02/30b3401a-03/g' /mnt/mmcblk0p4/etc/fstab


#[1..2].split(" ")
# puts local_part_details[0]



# img_part_details = `fdisk -l #{IMGFILE} -o device,start,end`
# img_part_details = img_part_details.split("\n")[1..2].map{|line| line.split(" ")}
# puts img_part_details
# # local_part_details

# TODO: Make this smarter about which partition it is booting from.
# `sudo rebootp 3`