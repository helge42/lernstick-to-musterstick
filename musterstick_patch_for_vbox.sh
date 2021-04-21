#!/bin/bash
#
# Description: Set the current values as defaults for the next boot in
#              isolinux/syslinux and grub config
#

# patches created with "diff -u3 "

# this tends to change from release to release...
BOOT_LABEL="EFI"
LIVE_MOUNTPOINT="/run/live/medium"
BOOTLOGO_DIR="bootlogo.dir"

cleanup() {
	if [ -n "${BOOT_TMP_MOUNT}" ]
	then
		echo "unmounting ${BOOT_PARTITION}"
		umount "${BOOT_TMP_MOUNT}" 2>&1
	else
		if [ -n "${IMAGE_DIR}" ]
		then
			echo "remounting ${IMAGE_DIR} read-only"
			mount -o remount,ro ${IMAGE_DIR} 2>&1
		fi
	fi

	if [ -n "${EXCHANGE_TMP_MOUNT}" ]
	then
		echo "unmounting "
		umount "${EXCHANGE_TMP_MOUNT}" 2>&1
	fi
	rm -r "${TMP_MOUNT_DIR}"
}

get_partition() {
	NUMBER=$1
	# examples (with NUMBER=1):
	# "/dev/sda3" -> "/dev/sda1"
	# "/dev/nvme0n1p3" -> "/dev/nvme0n1p1"
	echo ${SYSTEM_PARTITION} | sed "s|[0-9]*$|${NUMBER}|"
}

get_partition_label() {
	PARTITION=$1
	echo "$(/sbin/blkid ${PARTITION} -o udev | grep "ID_FS_LABEL=" | awk -F= '{ print $2 }')"
}

get_partition_fstype() {
	PARTITION=$1
	echo "$(/sbin/blkid ${PARTITION} -o udev | grep "ID_FS_TYPE=" | awk -F= '{ print $2 }')"
}

get_mountpoint() {
	PARTITION=$1
	echo "$(cat /proc/mounts | grep ${PARTITION} | awk '{ print $2 }')"
}

mount_boot_partition() {
	BOOT_PARTITION=$1
	echo "Temporary mount of boot partition ..."
	IMAGE_DIR="${TMP_MOUNT_DIR}/boot"
	mkdir "${IMAGE_DIR}"
	mount "${BOOT_PARTITION}" "${IMAGE_DIR}" && BOOT_TMP_MOUNT="${IMAGE_DIR}"
}


patch_file() {       # $1 file $2 patch_thing
	FILE_TO_PATCH=$1
	PATCH_THING="$2"

        # Try to apply the patch
        echo "$PATCH_THING" | patch -N --dry-run  $FILE_TO_PATCH
        #If the patch has not been applied then the $? which is the exit status
        #for last command would have a success status code = 0
        if [ $? -eq 0 ]
        then
                #apply the patch
                echo "apply patch to $FILE_TO_PATCH"
                echo "$PATCH_THING" | patch -b -N $FILE_TO_PATCH
        else
                echo "patch not applied to $FILE_TO_PATCH"
        fi
}

insert_file(){
	FILE_TO_INSERT=$1
	FILE_THING=$2

	if [ ! -f $FILE_TO_INSERT ];
	then
		echo "insert file $FILE_TO_INSERT"
		echo "$FILE_THING" | base64 -d  > $FILE_TO_INSERT
	else
		echo "not inserting, $FILE_TO_INSERT already exists"
	fi
}

# ------------------------
# Patch things
#-------------------------

PATCH_GRUB_CFG=$(cat << "GRUB_CFG"
--- grub.cfg.last	2021-04-15 11:45:54.000000000 +0200
+++ grub.cfg	2021-04-15 12:07:32.000000000 +0200
@@ -50,6 +50,8 @@
 export SWAP
 set QUIET="quiet splash"
 export QUIET
+set UPDATE=""
+export UPDATE
 set CUSTOM_OPTIONS=""
 export CUSTOM_OPTIONS
 
GRUB_CFG
)

PATCH_GRUB_MAIN_CFG=$(cat << "GRUB_MAIN_CFG"
--- grub_main.cfg.last	2021-03-22 20:53:46.000000000 +0100
+++ grub_main.cfg	2021-04-15 12:32:46.000000000 +0200
@@ -26,7 +26,7 @@
 		# some additional kernel options are needed:
 		DEFAULT_APPEND="$DEFAULT_APPEND radeon.modeset=0 i915.modeset=1 i915.lvds_channel_mode=2"
 
-		linux $DEFAULT_KERNEL $DEFAULT_APPEND locales=$LOCALES keyboard-layouts=$KEYBOARD desktop=$DESKTOP $LIVE_MEDIA $PERSISTENCE_MEDIA $PERSISTENCE $SWAP $QUIET custom_options $CUSTOM_OPTIONS
+		linux $DEFAULT_KERNEL $DEFAULT_APPEND locales=$LOCALES keyboard-layouts=$KEYBOARD desktop=$DESKTOP $LIVE_MEDIA $PERSISTENCE_MEDIA $PERSISTENCE $SWAP $QUIET $UPDATE custom_options $CUSTOM_OPTIONS
 		initrd $DEFAULT_INITRD
 	}
 
@@ -52,14 +52,14 @@
 		# some additional kernel options are needed:
 		DEFAULT_APPEND="$DEFAULT_APPEND i915.modeset=1 i915.lvds_channel_mode=2"
 
-		linux $DEFAULT_KERNEL $DEFAULT_APPEND locales=$LOCALES keyboard-layouts=$KEYBOARD desktop=$DESKTOP $LIVE_MEDIA $PERSISTENCE_MEDIA $PERSISTENCE $SWAP $QUIET custom_options $CUSTOM_OPTIONS
+		linux $DEFAULT_KERNEL $DEFAULT_APPEND locales=$LOCALES keyboard-layouts=$KEYBOARD desktop=$DESKTOP $LIVE_MEDIA $PERSISTENCE_MEDIA $PERSISTENCE $SWAP $QUIET $UPDATE custom_options $CUSTOM_OPTIONS
 		initrd $DEFAULT_INITRD
 	}
 
 else
 	menuentry $"Start Lernstick" --class start --unrestricted {
 		echo $"Loading Lernstick..."
-		linux $DEFAULT_KERNEL $DEFAULT_APPEND locales=$LOCALES keyboard-layouts=$KEYBOARD desktop=$DESKTOP $LIVE_MEDIA $PERSISTENCE_MEDIA $PERSISTENCE $SWAP $QUIET custom_options $CUSTOM_OPTIONS
+		linux $DEFAULT_KERNEL $DEFAULT_APPEND locales=$LOCALES keyboard-layouts=$KEYBOARD desktop=$DESKTOP $LIVE_MEDIA $PERSISTENCE_MEDIA $PERSISTENCE $SWAP $QUIET $UPDATE custom_options $CUSTOM_OPTIONS
 		initrd $DEFAULT_INITRD
 	}
 fi
@@ -166,6 +166,17 @@
 	configfile "/boot/grub/grub_quiet.cfg"
 }
 
+update_label=$"Update Bootmenu:"
+if [ "${UPDATE}" = "" ]
+then
+	update_value=$"disabled"
+else
+	update_value=$"enabled"
+fi
+menuentry "${update_label} ${update_value}" --class update --unrestricted {
+	configfile "/boot/grub/grub_update.cfg"
+}
+
 custom_label=$"Custom options :"
 menuentry "${custom_label} ${CUSTOM_OPTIONS}" --class configure --unrestricted {
 	echo $"Please type your custom options in one line:"
GRUB_MAIN_CFG
)



PATCH_LERNSTICK_UPDATE_BOOTMENU=$(cat << "LERNSTICK_UPDATE_BOOTMENU"
--- ./lernstick-update-bootmenu.orig	2021-04-11 16:22:53.908889000 +0200
+++ ./lernstick-update-bootmenu	2021-04-11 17:22:09.867047000 +0200
@@ -154,6 +154,15 @@
 
 update_bootloaders() {
 
+	# only update if update_bootmenu is set on cmdline
+	if ! (( $(grep -c "update_bootmenu" /proc/cmdline) )) 
+	then
+		echo "Option update_bootmenu is not set. Skiping update."
+		return 0
+	else
+		echo "Option update_bootmenu is set. Continue update ..."
+	fi
+
 	# determine correct configuration directory
 	echo "IMAGE_DIR: \"${IMAGE_DIR}\""
 	if [ -d ${IMAGE_DIR}/isolinux/ ]
LERNSTICK_UPDATE_BOOTMENU
)


PATCH_XMLCONFIG=$(cat << "XMLCONFIG"
--- ./xmlboot.config.orig	2021-04-10 13:52:38.000000000 +0200
+++ ./xmlboot.config	2021-04-11 17:26:46.000000000 +0200
@@ -206,6 +206,7 @@
     <option append_nonselected="nohz=off" id="dynamic_ticks" selected="true">Dynamic timer tick</option>
     <option append_nonselected="quiet splash" id="messages" off_off_triggers="debug">Show boot messages</option>
     <option append_selected="debug=1" id="debug" on_on_triggers="messages">Show debug messages</option>
+    <option append_selected="update_bootmenu" id="update">Update and save bootmenu</option>
   </options>
   <custom_options text=""/>
   <videomodes>
@@ -322,6 +323,7 @@
       <option id="dynamic_ticks"/>
       <option id="messages"/>
       <option id="debug"/>
+      <option id="update"/>
     </submenu>
     <start icon="icon_integrity_check.jpg" index="0" label="linux boot=live live-media-timeout=10 verify-checksums">
       <text>Check integrity of boot medium</text>
XMLCONFIG
)

FILE_UPDATE_PNG=$(cat << "UPDATE_PNG"
iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAC3XpUWHRSYXcgcHJvZmlsZSB0eXBl
IGV4aWYAAHja7ZdNkuQoDIX3nKKPgCSExHEwPxF9gzl+P2zKVZlVXRHT04tZpAkDVspPoE92Zobx
z88ZfuCgIjEkNc8l54gjlVS4YuLxOq6RYjr7fRHfJg/2cH/AMAlGuS7z2P4Vdn2/wdK2H4/2YG3r
+BaiW/g8ZEVe8+3nW0j4stO+DmXfV9OH7ewzp/iwn+frZEhGV+gJBx5CEtH7iiLrJKkYE3oShRPB
VnEaehxf5y7c06fk3bOn3MW67fKYihDzdshPOdp20ie73GH4mdpb5IcPTO4Qn3I3Z/c5x7W7mjIy
lcPe1NtWzhkcD6TyykZGM5yKuZ2toDm22ECsg+aB1gIVYmR7UqJOlSaNc2zUsMTEgw0jcwODZXMx
LtxkIUir0WSTIj2Ig0cDNYGZ77XQGbec8Ro5IneCJxPEFsVPLXxl/JN2C825Spco+p0rrItXTWMZ
i9zq4QUgNHdO9czv2cKHuokfwAoI6plmxwZrPC6JQ+m9tuTkLPDTmEK8yp6sbwGkCLEViyEBgZhR
3pQpGrMRIY8OPhUrZ0l8gACpcqcwwUYkA47zio17jE5fVr7MeLUAhErGQ+IgVAErJUX9WHLUUFXR
FFQ1q6lr0Zolp6w5Z8vrHVVNLJlaNjO3YtXFk6tnN3cvXgsXwStMSy4WipdSakXQCumKuys8aj34
kCMdeuTDDj/KURvKp6WmLTdr3kqrnbt0PP49dwvde+l10EApjTR05GHDRxl1otamzDR15mnTZ5n1
prapPlKjJ3LfU6NNbRFLp5+9U4PZ7E2C1utEFzMQ40QgbosACpoXs+iUEi9yi1ksjIdCGdRIF5xO
ixgIpkGsk2527+S+5RY0/Stu/DtyYaH7G+TCQrfJfeb2BbVez28UOQGtp3DlNMrEiw0Owyt7Xd9J
fzyG/yrwEnoJvYReQi+hl9BL6P8jNPHjAX81wy/I9pDBB0CBggAAAAZiS0dEAP8A/wD/oL2nkwAA
AAlwSFlzAAAPYQAAD2EBqD+naQAAAAd0SU1FB+UEDwobIc92yBUAAADCSURBVDjLrZIxCsJAEEUf
i4ewsrcWbC2jYOUVhAgeQUvRO9jbaq0XsDKVnYXEUtg7aDMLw+CQBPPhs0uWebszP9CSDsCnwhHY
eoAbsACOqqAEBuISWMu614VB7R9yS1IECnEErsAIyDQkNGz1pSCbKkAPyMVdA1kCE4COKTpJz0m5
rE/grr6/08YCLuLaCv/mbwHzGv9DrgtsC0OZw865cCUzKjyAzh/nrN0Z6BdMgb6JzyqdzyzgDIx/
5O8paxq3qy9OMzUgCA8knwAAAABJRU5ErkJggg==
UPDATE_PNG
)

FILE_GRUB_UPDATE_CFG=$(cat << "GRUB_UPDATE_CFG"
ZGlzYWJsZV90aW1lb3V0CgpmdW5jdGlvbiBleHBvcnRfdXBkYXRlIHsKCXNldCBVUERBVEU9IiR7
MX0iCglleHBvcnQgVVBEQVRFCglnb190b19tYWluX21lbnUKfQoKbWVudWVudHJ5ICQiQ29uZmln
dXJlIGJvb3QgbWVzc2FnZXM6IiAtLXVucmVzdHJpY3RlZCB7Cglnb190b19tYWluX21lbnUKfQoK
ZW50cnlfdGV4dD0kImVuYWJsZWQiCmlmIFsgIiR7VVBEQVRFfSIgPSAidXBkYXRlX2Jvb3RtZW51
IiBdCnRoZW4KCW1lbnVlbnRyeSAiKiAke2VudHJ5X3RleHR9IiAtLXVucmVzdHJpY3RlZCB7CgkJ
Z29fdG9fbWFpbl9tZW51Cgl9CmVsc2UKCW1lbnVlbnRyeSAiICAke2VudHJ5X3RleHR9IiAtLXVu
cmVzdHJpY3RlZCB7CgkJZXhwb3J0X3VwZGF0ZSAidXBkYXRlX2Jvb3RtZW51IgoJfQpmaQoKZW50
cnlfdGV4dD0kImRpc2FibGVkIgppZiBbICIke1VQREFURX0iID0gIiIgXQp0aGVuCgltZW51ZW50
cnkgIiogJHtlbnRyeV90ZXh0fSIgLS11bnJlc3RyaWN0ZWQgewoJCWdvX3RvX21haW5fbWVudQoJ
fQplbHNlCgltZW51ZW50cnkgIiAgJHtlbnRyeV90ZXh0fSIgLS11bnJlc3RyaWN0ZWQgewoJCWV4
cG9ydF9xdWlldCAiIgoJfQpmaQoK
GRUB_UPDATE_CFG
)

# ------------------------
# End Patch things
#-------------------------

patch_xmlconfig() {
	# determine correct configuration directory
	echo "IMAGE_DIR: \"${IMAGE_DIR}\""
	if [ -d ${IMAGE_DIR}/isolinux/ ]
	then
		SYSLINUX_CONFIG_DIR="${IMAGE_DIR}/isolinux"
	elif [ -d ${IMAGE_DIR}/syslinux/ ]
	then
		SYSLINUX_CONFIG_DIR="${IMAGE_DIR}/syslinux"
	else
		echo "There was neither an isolinux nor a syslinux configuration in \"${IMAGE_DIR}\"."
		SYSLINUX_CONFIG_DIR=""
		XMLBOOT_CONFIG=""
	fi

	if [ -n "${SYSLINUX_CONFIG_DIR}" ]
	then
		# check writability of configuration directory
		#
		# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
		# ! This test only works reliably with bash on      !
		# ! read-only filesystems! Therefore, do not change !
		# ! the first line with /bin/bash in this script!   !
		# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
		if [ ! -w ${SYSLINUX_CONFIG_DIR} ]
		then
			# it's ok, system was probably booted from iso...
			echo "The configuration directory \"${SYSLINUX_CONFIG_DIR}\" is not writable."
			echo "The system was probably booted from DVD."
			return 0
		fi

		XMLBOOT_CONFIG="${SYSLINUX_CONFIG_DIR}/${BOOTLOGO_DIR}/xmlboot.config"
		echo "XMLBOOT_CONFIG: \"${XMLBOOT_CONFIG}\""
	fi

	# Try to apply the patch
	echo "$PATCH_XMLCONFIG" | patch -N --dry-run  ${XMLBOOT_CONFIG}
	#If the patch has not been applied then the $? which is the exit status
	#for last command would have a success status code = 0
	if [ $? -eq 0 ]
	then
		#apply the patch
		echo "apply patch"
		echo "$PATCH_XMLCONFIG" | patch -b -N ${XMLBOOT_CONFIG}
	else
		echo "patch not applied"
	fi

	# rebuild bootlogo (only if syslinux/isolinux is really present)
	if [ -n "${SYSLINUX_CONFIG_DIR}" ]
	then
		gfxboot --archive "${SYSLINUX_CONFIG_DIR}/${BOOTLOGO_DIR}" --pack-archive "${SYSLINUX_CONFIG_DIR}/bootlogo"
	fi
}

# create directory for temporary mounts
TMP_MOUNT_DIR="$(mktemp --directory -t lernstick-update-bootmenu.XXXXXX)"

# set cleanup trap on exit
trap cleanup EXIT

# the only reliable info about our boot medium is the system partition
SYSTEM_PARTITION=$(grep ${LIVE_MOUNTPOINT} /proc/mounts | awk '{ print $1 }')
echo "system partition: \"${SYSTEM_PARTITION}\""

# get infos about first partition
FIRST_PARTITION="$(get_partition 1)"
echo "first partition: \"${FIRST_PARTITION}\""
FIRST_LABEL="$(get_partition_label ${FIRST_PARTITION})"
echo "first label: \"${FIRST_LABEL}\""

if [ "${FIRST_LABEL}" = "${BOOT_LABEL}" ]
then
	echo "EFI partition is the first partition"
	mount_boot_partition ${FIRST_PARTITION}

	GRUB_CONFIG="${IMAGE_DIR}/boot/grub/grub.cfg"
	GRUB_MAIN_CONFIG="${IMAGE_DIR}/boot/grub/grub_main.cfg"
	patch_file $GRUB_CONFIG "${PATCH_GRUB_CFG}"
	patch_file $GRUB_MAIN_CONFIG "${PATCH_GRUB_MAIN_CFG}"
	
	patch_file "/lib/systemd/lernstick-update-bootmenu" "${PATCH_LERNSTICK_UPDATE_BOOTMENU}"
	patch_xmlconfig

	GRUB_ICON_DIR="${IMAGE_DIR}/boot/grub/themes/lernstick/icons"
	insert_file "$GRUB_ICON_DIR/update.png" "$FILE_UPDATE_PNG"
	GRUB_UPDATE_CFG="${IMAGE_DIR}/boot/grub/grub_update.cfg"
	insert_file "$GRUB_UPDATE_CFG" "$FILE_GRUB_UPDATE_CFG"
else
	echo "Something wrong: First partition should be the EFI partition"
fi

echo "Done."
