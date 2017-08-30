#!/bin/bash

# Usage [dist] [input_qcow2_img] [output_vmdk_img]
DIST=$1
INPUTIMG=$2
OUTPUTIMG=$3
RAND=`openssl rand -hex 8`
RD="/mnt/"$RAND
INPUTIMGWORK=$RAND$INPUTIMG
# mkimg_backup
cp $INPUTIMG $INPUTIMGWORK

mount_img(){
	# load nbd module
	sudo modprobe nbd
	# attach qcow2 image to nbd0
	sudo qemu-nbd --connect=/dev/nbd0 $INPUTIMGWORK
	# create mount point
	sudo mkdir -p $RD
	# mount image
	sudo mount /dev/nbd0p1 $RD
	# Prepare proc,dev,sys
	sudo mount -t proc proc	$RD/proc/
	sudo mount -o bind /dev	$RD/dev
	sudo mount -o bind /sys $RD/sys
}

umount_img(){
	# Unmount proc,dev,sys
	sudo umount $RD/proc
	sudo umount $RD/dev
	sudo umount $RD/sys
	# Unmount Image
	sync
	sudo umount $RD
	sudo qemu-nbd --disconnect /dev/nbd0
	sudo rm -r $RD
}

mkimg_centos(){
	mount_img
	# Update grub (to not to use biosdevname)
	echo 'GRUB_CMDLINE_LINUX="bisodevname=0 net.ifnames=0"' | sudo tee -a $RD/etc/default/grub
	sudo chroot $RD grub2-mkconfig -o /boot/grub2/grub.cfg
	# Install open-vm-tools
	sudo mv $RD/etc/resolv.conf $RD/etc/resolv.conf.org
	echo "nameserver 8.8.8.8" | sudo tee -a $RD/etc/resolv.conf
	sudo chroot $RD yum install -y open-vm-tools
	sudo mv $RD/etc/resolv.conf.org $RD/etc/resolv.conf
	UUID=`sudo chroot $RD blkid -s UUID -o value /dev/nbd0p1`
	sudo sed -i -e "s/root=\/dev\/nbd0p1/root=UUID=${UUID}/g" $RD/boot/grub2/grub.cfg

	umount_img

	# convert img
	qemu-img convert -p -f qcow2 -O vmdk -o subformat=streamOptimized $INPUTIMGWORK $OUTPUTIMG
	# remove temp img
	rm $INPUTIMGWORK
	echo "#### Complated ####"
	echo "Use following command to register the image!"
	echo "$ openstack image create --container-format bare --disk-format vmdk --property vmware_disktype=streamOptimized --property vmware_adaptertype=paraVirtual --property hw_vif_model=VirtualVmxnet3 --property vmware_ostype=rhel7_64Guest --file "$OUTPUTIMG" "${OUTPUTIMG%.*}
}

mkimg_ubuntu16(){
	mount_img
	# Update grub (to not to use biosdevname)
	sudo sed -i -e 's/console=ttyS0//g' $RD/etc/default/grub
	sudo sed -i -e 's/console=tty1//g' $RD/etc/default/grub

	sudo sed -i -e 's/console=ttyS0//g' $RD/boot/grub/grub.cfg
	sudo sed -i -e 's/console=tty1//g' $RD/boot/grub/grub.cfg

	umount_img
	
	# convert img
	qemu-img convert -p -f qcow2 -O vmdk -o subformat=streamOptimized $INPUTIMGWORK $OUTPUTIMG
	# remove temp img
	rm $INPUTIMGWORK
	echo "#### Complated ####"
	echo "Use following command to register the image!"
	echo "$ openstack image create --container-format bare --disk-format vmdk --property vmware_disktype=streamOptimized --property vmware_adaptertype=paraVirtual --property hw_vif_model=VirtualVmxnet3 --property vmware_ostype=ubuntu64Guest --file "$OUTPUTIMG" "${OUTPUTIMG%.*}
}

case $DIST in

ubuntu16)
mkimg_ubuntu16
;;
centos)
mkimg_centos
;;
esac



