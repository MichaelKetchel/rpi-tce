#!/usr/local/bin/ruby
require 'json'
require 'net/http'
require 'net/https'
require 'pp'
require 'openssl'
require 'open-uri'
require 'cgi'
require 'yaml'
require 'resolv'
# Maybe could use /usr/bin/env ruby, but the above is the known path on TCE.

# fdisk -x /dev/mmcblk0
NO_VERIFY_SSL = false
BOOT_THRASH_THRESHOLD = 4
BOOT_EXEC_MAX_ENTRIES = 10
MAX_BOOT_ADDRESS_WAIT = 120
FIRMWARE_SERVER_DHCP_SUB_OPTION=155
RPI_MODEL = `cat /sys/firmware/devicetree/base/model`.delete("\u0000")
STARTING_DIR = File.expand_path(File.dirname(__FILE__))
IMGFILE="image.img.gz"
IMG_PATH="/tmp/#{IMGFILE}"
BOOT_DEVICE="/dev/mmcblk0"
BOOT_DATA_PART="#{BOOT_DEVICE}p1"
LOCAL_DATA_FILE="/mnt/mmcblk0p1/bldata.json"
IMG_BEGINNING_PATH="#{IMG_PATH}.begin"

$local_data = {
    "current_image_md5" => nil,
    "last_flash_success" => false,
    "boot_exec_times" => [],
    "first_boot" => true,
    "remote_log" => false,
    "boot_server_override" => nil,
}

alias :og_puts :puts

def puts(*args, &block)
    og_puts(*args, &block)
    msg = args.join(' ')
    log_msg msg if $local_data['remote_log']
    return msg
end

def bigputs (args)
    return puts "#### #{args} ####"
end

def get_if_mac(ifname)
    `ifconfig #{ifname}`.match(/(?<=HWaddr )((?:\w\w:){5}\w\w)/)[1].strip
end

def get_default_gateway
    `route | grep 'default' | awk '{print $2}'`.strip
end

def digest_option_43_from_dec(option_hex, option_hash:{})
    return option_hash if option_hex.size == 0
    option_id = option_hex.shift
    option_length = option_hex.shift
    option_value = option_hex.shift(option_length)
    option_hash[option_id] = option_value
    return digest_option_43_from_dec(option_hex, option_hash:option_hash)
end


def get_server_from_dhcp_opts
    dhcp_config = YAML.load_file('/tmp/dhcp_config.yml')
    raw_option_payload = dhcp_config.dig('eth0', 'opts', 43)
    if raw_option_payload != nil
        option_hash = digest_option_43_from_dec(raw_option_payload.scan(/../).map(&:hex))
        return option_hash[FIRMWARE_SERVER_DHCP_SUB_OPTION]&.pack('C*')
    else
        puts("Not controller defined in dhcp:")
        return nil
    end
end

def get_cpu_info
    serial = `awk '/Serial/{print $3}' /proc/cpuinfo`.chomp
    model = `awk '/Model/{$1=$2=""; print $0}' /proc/cpuinfo`.chomp.lstrip
    return {'serial' => serial, 'model' => model }
end

def get_os()
    os = `uname -r`
    return os.strip
end

def get_controller_url
    address = $local_data["boot_server_override"] || get_server_from_dhcp_opts || get_default_gateway
    return ["https://#{ address }/api/firmware_update", address =~ Resolv::AddressRegex ]
end

def get_pifi_url
    address = $local_data["boot_server_override"] || get_server_from_dhcp_opts || get_default_gateway
    return ["https://#{ address }/pifi", address =~ Resolv::AddressRegex ]
end

ETH0_MAC=get_if_mac("eth0")

def post_to_url(path, params:{}, follow_redirects:0, allow_file:false, no_verify_ssl:NO_VERIFY_SSL, &block)
    uri = URI.parse(path)
    # puts("POSTting URI: #{uri.to_s}")
    http = Net::HTTP.new(uri.hostname,uri.port)
    http.max_retries = 3
    http.use_ssl = true if uri.instance_of? URI::HTTPS
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE if no_verify_ssl
    req = Net::HTTP::Post.new(uri)
    req.body = params.to_json
    req.content_type = 'application/json'
    req["Accept"] = 'application/json'
    resp = http.request(req)

    if follow_redirects == 0 || !resp.kind_of?(Net::HTTPRedirection)
        return yield(resp, false) if block_given?
        return resp
    end
    
    if (resp["location"].include?("disposition=attachment") && allow_file)
        return open(resp['location'], "rb", {ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE}) {|io| yield(io, true)} if no_verify_ssl
        return open(resp['location'], "rb") {|io| yield(io, true)}
    end

    return post_to_url(resp['location'], params:params, follow_redirects:follow_redirects-1, no_verify_ssl:no_verify_ssl, &block)
end

def get_from_url(path, params:nil, follow_redirects:0, allow_file:false, no_verify_ssl:NO_VERIFY_SSL, &block)
    uri = URI.parse(path)
    uri.query = params.collect { |k,v| "#{k}=#{CGI::escape(v.to_s)}" }.join('&') if not params.nil?
    # puts("GETting URI: #{uri.to_s}")
    http = Net::HTTP.new(uri.hostname, uri.port)
    http.max_retries = 3
    http.use_ssl = true if uri.instance_of? URI::HTTPS
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE if no_verify_ssl
    req = Net::HTTP::Get.new(uri)
    resp = http.request(req)

    if follow_redirects == 0 || !resp.kind_of?(Net::HTTPRedirection)
        return yield(resp, false) if block_given?
        return resp
    end

    if (resp["location"].include?("disposition=attachment") && allow_file)
        return open(resp['location'], "rb", {ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE}) {|io| yield(io, true)} if no_verify_ssl
        return open(resp['location'], "rb") {|io| yield(io, true)}
    end
    return get_from_url(resp['location'], params, follow_redirects:follow_redirects-1, no_verify_ssl:no_verify_ssl, &block)
end

def post_to_controller(path, params:{}, follow_redirects:0, allow_file:false, &block)
    controller = get_controller_url()
    return post_to_url("#{controller[0]}/#{path}", params:params.merge({"mac":ETH0_MAC, "model": RPI_MODEL}), follow_redirects:follow_redirects, allow_file:allow_file, no_verify_ssl:controller[1], &block)
end

def get_from_controller(path, params:{}, follow_redirects:0, allow_file:false, &block)
    controller = get_controller_url()
    return get_from_url("#{controller[0]}/#{path}", params:params.merge({"mac":ETH0_MAC, "model": RPI_MODEL}), follow_redirects:follow_redirects, allow_file:allow_file, no_verify_ssl:controller[1], &block)
end


def send_rxg_hello_mesg()
    os=get_os()
    cpu=get_cpu_info
    body = { mac: ETH0_MAC,
             version: "RG Loader",
             ap_info: {
               wlans: [],
               os: os,
               model: cpu['model'],
               serial: cpu['serial'],
             }
    }
    print "Hello: ", body.to_json,"\n"
    pifi_url, pifi_no_ssl = get_pifi_url
    result = post_to_url("#{pifi_url}/hello", params:body, no_verify_ssl:pifi_no_ssl)
  end

def log_msg(msg)
    begin
        post_to_controller("log_message", params:{'msg' => msg})
    rescue => exception
        og_puts "An exception #{exception.class} occurred while sending log message: #{exception.message}. Continuing."
    end
end

def send_status(status)
    msg = "#{status} (#{caller_locations[0]})"
    # puts "Informing controller of status: #{msg}"
    begin
        post_to_controller("flash_status", params:{'status' => msg})
    rescue => exception
        puts "An exception #{exception.class} occurred while sending status: #{exception.message}. Continuing."
    end
end

def ask_controller(endpoint, fail_value=nil )
    puts "Asking controller about #{endpoint}..."
    begin
        res = get_from_controller(endpoint)
        if res.code == '200'
            puts "Controller said #{res.body.strip}"
            return res.body.strip.downcase =~ /true|1|yes/
        end
        puts "Non-200 returned: #{res.code} #{res.to_s}"
        return fail_value
    rescue => exception
        og_puts "An exception #{exception.class} occurred while asking controller about #{endpoint}: #{exception.message}. Continuing."
    end
end

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

class CommunicationError < StandardError
    attr_reader :return_code
    attr_reader :path
    attr_reader :res
    attr_reader :caller
    def initialize(msg="An error occured communicating with the controller: #{res}", path='', res='', return_code=-1, caller=nil)
        @return_code = return_code
        @path = path
        @res = res
        @caller = caller
        super(msg)
    end
end

class InvalidControllerError < StandardError
    def initialize(msg="Tried to talk to an invalid controller!")
        super(msg)
    end
end

def set_exit enable
    if enable
      define_method :system do |*args|
        res = Kernel.system *args
        # puts "Exec: #{args}"
        raise SysExecError.new("Error executing system command \"#{args}\": (#{$?.exitstatus})",args.to_s, res, $?.exitstatus, caller_locations) unless $?.success?
        return res
        # exit $?.exitstatus unless $?.success?
      end
      define_method :` do |args|
        define_method :backtick_method , Kernel.instance_method(:`)
        # puts "Exec: #{args}"
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
        send_status puts("Starting Flashing process")
        set_exit true

        send_status puts("Getting Firmware MD5 Digest")
        resp = get_from_controller('get_firmware_md5')
        raise CommunicationError.new("Unable to fetch firmware md5", path: "get_firmware_md5", res:resp, return_code:resp.code) unless resp.kind_of? Net::HTTPSuccess
        new_md5 = JSON.parse(resp.body)['md5']
        
        send_status puts("Checking if should flash this firmware")
        if new_md5 == $local_data["current_image_md5"] && $local_data["last_flash_success"] && !ask_controller("force_flash", false)
            puts "Identical image already flashed successfully, no force requested, skipping flash."
            return true
        end

        send_status puts("Getting Firmware File")
        get_from_controller('get_firmware_file', follow_redirects:10, allow_file:true) do |read_file, file_found|
            unless file_found
                puts "No file found: #{read_file.error}" 
                raise CommunicationError.new("Unable to fetch firmware file", path: "get_firmware_file", res:read_file, return_code:read_file.code)
            end
            # puts read_file.class < IO
            File.open(IMG_PATH, 'wb') do |file|
                file.binmode
                file.write(read_file.read)
                puts file.path
            end
        end

        send_status puts("Checking MD5 of downloaded firmware file")
        file_md5 = `md5sum #{IMG_PATH}`.split(" ")[0]
        if new_md5 == file_md5
            send_status puts("MD5 OK, firmware downloaded OK.")
        else
            raise Exception.new("MD5 sums from server and downloaded file did not match") 
        end
        
        puts "New image has MD5 has of #{new_md5}"
        $local_data["current_image_md5"] = new_md5
        `cd #{STARTING_DIR};`

        # Get first chunks for img beginning
        send_status puts "Reading image partition table"
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

        send_status puts "Writing image to disk"
        # Well.. it might be just that easy. Write the flashed image to disk.
        dd_cmd = "gzip -dc #{IMG_PATH} | dd of=#{BOOT_DEVICE} bs=8M iflag=skip_bytes,fullblock oflag=seek_bytes skip=#{img_skip_sectors*512} seek=#{seek_sectors*512}"
        puts "Will run: sudo #{dd_cmd}"
        # output=`ls no_existing_file` ;  result=$?.success?
        output = `sudo #{dd_cmd}`


        # Update partition table
        send_status bigputs("Updating partition table")
        
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

        send_status bigputs("Extending partitions and FS")
        
        send_status puts "Resizing and checking partitions"
        `sudo parted /dev/mmcblk0 "resizepart 4 -0"`
        `sudo e2fsck -fp /dev/mmcblk0p4`
        `sudo resize2fs /dev/mmcblk0p4`

        send_status puts "Mounting filesystems"
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
        boot_blkid_partuuid = `blkid #{BOOT_DEVICE}`[/PTUUID="(\w+)"/,1]

        send_status puts "Updating cmdline.txt"
        puts "IMG partuuid: #{img_blkid_partuuid}"
        puts "Boot partuuid: #{boot_blkid_partuuid}"
        # Update cmdline
        (0..7).each do |part_num|
            `sudo sed -i 's/PARTUUID=#{img_blkid_partuuid}-0#{part_num}/PARTUUID=#{boot_blkid_partuuid}-0#{part_num + 2}/g' /mnt/mmcblk0p3/cmdline.txt`
        end
        `sudo sed -i 's| init=/usr/lib/raspi-config/init_resize\.sh||' /mnt/mmcblk0p3/cmdline.txt`
        `sudo sed -i 's| sdhci\.debug_quirks2=4||' /mnt/mmcblk0p3/cmdline.txt`

        send_status puts "Updating fstab"
        # Update fstab
        (0..7).each do |part_num|
            `sudo sed -i 's/PARTUUID=#{img_blkid_partuuid}-0#{part_num}/PARTUUID=#{boot_blkid_partuuid}-0#{part_num + 2}/g' /mnt/mmcblk0p4/etc/fstab`
        end
        set_exit false
        return true


    rescue CommunicationError => exception
        send_status puts "An exception occurred communicating with the controller: #{exception.path} (#{exception.return_code}): #{exception.res.body}"
        puts "Exception: #{exception.inspect}\n\t#{exception.backtrace.join("\n\t")}"
        return false
    rescue SysExecError => exception
        send_status puts "An exception occurred running a shell command: #{exception.cmd} (#{exception.return_code}): #{exception.res}"
        puts "Exception: #{exception.inspect}\n\t#{exception.backtrace.join("\n\t")}"
        return false
    rescue Exception => exception
        send_status puts "An unknown error occurred while flashing: #{exception.class} -> #{exception.message}"
        puts "Exception: #{exception.inspect}\n\t#{exception.backtrace.join("\n\t")}"
        return false
    end
end

def wait_for_ethernet
    # Sense ethernet and wait for address
    current_wait=0
    while !system('ifconfig eth0 | grep "inet addr:" > /dev/null 2>&1')
        puts "Waiting for address..."
        sleep 5
        current_wait += 5
        if current_wait > MAX_BOOT_ADDRESS_WAIT && $local_data["last_flash_success"]
            puts "Maximum wait exceeded, booting old image."
            sleep 5
            do_boot
        end
    end
    sleep 1
    # puts `ifconfig eth0 | grep "inet addr:"`
end

def found_valid_controller?
    valid = false
    begin
        resp = get_from_controller('')
        valid = resp.kind_of?(Net::HTTPSuccess)
    rescue
        valid = false
    end
    puts "#{get_controller_url()[0]} is not a valid controller!" unless valid 
    return valid
end

def do_boot
    puts "Deciding whether to boot"
    no_boot = ask_controller('no_boot', false)
    unless no_boot
        puts "Checking if last flash succeeded"
        unless $local_data["last_flash_success"]
            send_status puts("Last flash failed. Restarting to try again.")
            # save_local_data
            # sleep 5
            # `sudo rebootp 1`
            return
        end
        send_status puts("Booting...")
        save_local_data
        sleep 5
        `sudo rebootp 3`
    end
    puts "Not booting."
end

# Load local data, make note of our boot time, and check the last n times to make sure we're not thrashing
load_local_data
$local_data["boot_exec_times"].append(Time.now)
$local_data["boot_exec_times"] = $local_data["boot_exec_times"].last(BOOT_EXEC_MAX_ENTRIES)
# TODO: Check for thrashing 

# Handle first boot tasks like saving ssh keys
if $local_data["first_boot"]
    $local_data["first_boot"] = false
    save_local_data
    `filetool.sh -b`
end

while true
    begin
        wait_for_ethernet
        raise InvalidControllerError.new unless found_valid_controller?
        send_status puts("RG Loader Online")

        send_rxg_hello_mesg
        puts `ifconfig eth0 | grep "inet addr:"`
        puts "Controller URL: #{get_controller_url[0]}"
        puts "Pifi URL:       #{get_pifi_url[0]}"
        # Decide whether to pull and flash or just go straight to boot.
        should_flash = ask_controller('do_flash', false)
        if should_flash
            puts "Instructed to flash"
            send_status puts("Preparing to flash")
            flash_result = flash_os_image
            send_status puts("Flash #{ flash_result ? 'succeeded' : 'failed'}")
            $local_data["last_flash_success"] = flash_result 
            save_local_data
        end
        do_boot
        sleep 10
        # If we get here, do_boot has decided not to boot and we need to cycle again. 

    rescue InvalidControllerError => e
        puts "#{e.class}: #{e.message}"
        do_boot
        puts "Unable to boot. Waiting for valid controller."
        sleep 10
    rescue => exception
        puts "An exception #{exception.class} occurred while looping: #{exception.message}"
        puts "Stubbornly refusing to die."
        sleep 5
    end
end

