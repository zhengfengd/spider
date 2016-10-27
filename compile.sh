#!/bin/bash
BUILD_VERSION=1-0-0-0

#TODO: add platform when ready
platformlist="mlnx-spider"

TOP_DIR=${PWD}/kevin_BRANCH
KERNEL_DIR=${TOP_DIR}/os/base/kernel/3.16.7
ROOTFS_DIR=${TOP_DIR}/os/base/rootfs
KERNEL_HEADER_DIR=${TOP_DIR}/os/base/header/linux-headers-3.16.7-ckt20
SDK_DIR=${TOP_DIR}/sdk/bcm/sdk-xgs-robo-6.4.9
XORPLUS_DIR=${TOP_DIR}/xorplus
IMAGES_DIR=${TOP_DIR}/images

export KERNEL_DIR
export ROOTFS_DIR
export KERNEL_HEADER_DIR
export SDK_DIR
export XORPLUS_DIR
export IMAGES_DIR

execute(){
    echo "Executing $*"
    $*
    if [ "$?" = "0" ]; then
        echo "$* succeeded!"
    else
        echo "$* failed!, exiting"
        read -n1 -r -p "Press space to continue to next step, any other key to exit with error..." key
        if [ "$key" = '' ]; then
          # Space pressed, do something
          # echo [$key] is empty when SPACE is pressed # uncomment to trace
          echo "OK then, fasten seat belts!"
        else
            # Anything else pressed, do whatever else.
            # echo [$key] not empty
            echo "Bye"
            exit 1
        fi
    fi
}

BASE_PATH=/baidu/
apt-get install -y libtool-bin

echo "Step 1: Compiling linux kernel"
echo "Entering directory '${KERNEL_DIR}'"
cd ${KERNEL_DIR}
execute make




echo "Build BSP..."
cd ${BASE_PATH}bsp/hw-management
execute debuild -us -uc
cp ../hw-management_1.mlnx.25.5.2016_amd64.deb ${BASE_PATH}/debs/
# Output is placed one folder up and consist of a lot of files, including the .deb
# Extract .deb and copy data.xz info to rootfs
# cd ..
# # ar x hw-management_1.mlnx.16.03.30_amd64.deb
# mkdir data-xz
# tar xvf data.tar.xz -C data-xz
# rm data.tar.xz control.tar.gz debian-binary
# cd data-xz
# cd /baidu/
# cp -rv bsp/data-xz/* image/

echo "Check /baidu/debs/ for hw-management (BSP) .deb"
ls -l ${BASE_PATH}/debs/


echo "Compile SDK to custom output...."
#cd ${BASE_PATH}/sdk/sx_sdk_eth-4.2.2102/
cd ${BASE_PATH}/sdk/sx_sdk_eth-4.2.1010/
yes | ./install.sh --use-sources --with-iproute2-3.19-sx_netdev --kernel-version 3.16.7-ckt20 --kernel-sources ${BASE_PATH}kevin_BRANCH/os/base/kernel/3.16.7/linux-3.16.7-ckt20/ --prefix ${BASE_PATH}sdk/sdk-output/ --build-root ${BASE_PATH}sdk/sdk-output/usr/src/sx_sdk
execute cp -r ../sdk-output/* /

echo "SDK output is located at ${BASE_PATH}/sdk/sdk-output/"


echo "Compile SAI to custom output"
cd /baidu/sai/mlnx_sai
export XML2_LIB_PATH=/usr/
execute ./autogen.sh
execute ./configure --with-applibs=/ --with-sxcomplib=/ --with-sxdlibs=/ --prefix=/usr/
execute make
execute make install DESTDIR=${BASE_PATH}/sai/sai-output/
execute cp -r ../sai-output/usr/* /usr/


echo "Compile MFT" 
cd ${BASE_PATH}/mft/mft-4.2.0-15/SRPMS/kernel-mft-4.2.0
#Remove when docker container is built with good config
apt-get install -y dkms
export WITH_DKMS=1
export kernelver=3.16.7-ckt20
export kernel_source_dir=/baidu/kevin_BRANCH/os/base/kernel/3.16.7/linux-3.16.7-ckt20/
execute dpkg-buildpackage -us -uc
cp ../kernel-mft-dkms_4.2.0-15_all.deb ${BASE_PATH}/debs/
cp ${BASE_PATH}/mft/mft-4.2.0-15/DEBS/mft-4.2.0-15.amd64.deb ${BASE_PATH}/debs/
cp ${BASE_PATH}/mft/mft-4.2.0-15/DEBS/mft-oem-4.2.0-15.amd64.deb ${BASE_PATH}/debs/


echo "Compile the rest of baidu os.."
cd ${BASE_PATH}/kevin_BRANCH

for platform in ${platformlist}
do
    echo "Step 3: Compiling switch software"
    DRIVER_DIR=${TOP_DIR}/os/base/driver/${platform}
    export DRIVER_DIR
    echo "Entering directory '${DRIVER_DIR}'"
    cd ${DRIVER_DIR}
    execute make 
done

#echo "Step 2: Compiling bcm sdk"
#sleep 1
#echo "Entering directory '${SDK_DIR}'"
#cd ${SDK_DIR}
    
#execute make mark_user
#echo -e "Leaving directory '${SDK_DIR}'\n\n\n"

for platform in ${platformlist}
do
    echo "Step 3: Compiling switch software"
    sleep 1
    echo "Entering directory '${XORPLUS_DIR}'"
    cd ${XORPLUS_DIR}
    make clean
    execute ./build-x86_64-${platform}.sh
    echo -e "Leaving directory '${XORPLUS_DIR}'\n\n\n"
    cd ${TOP_DIR}

    echo "Step 4: Building rootfs images"
    sleep 1
    echo "Entering directory '${IMAGES_DIR}'"
    cd ${IMAGES_DIR}
    execute make platform=${platform}
    echo "Leaving directory '${IMAGES_DIR}'"
    echo "Building images successfully in directory '${IMAGES_DIR}'"

    echo "Integrate mlnx components into root-fs"
    rm -rf new-image; mkdir new-image
    execute tar xvzf rootfs-${platform}.tar.gz -C new-image
    execute mkdir new-image/mlnx-debs
    execute cp ${BASE_PATH}debs/* new-image/mlnx-debs/
    execute cp ${BASE_PATH}mlnx-baidu-integration/install_components.sh new-image/
    execute mkdir new-image/pica/config
    execute cp ${BASE_PATH}mlnx-baidu-integration/xorplus/rtrmgrctl_spider.sh new-image/pica/
    execute cp ${BASE_PATH}mlnx-baidu-integration/xorplus/pica_startup.boot new-image/pica/config/
    execute cp ${BASE_PATH}mlnx-baidu-integration/xorplus/pica_default.boot new-image/pica/bin
    execute cp ${BASE_PATH}mlnx-baidu-integration/patches/70-persistent-net.rules new-image/etc/udev/rules.d/
    echo "auto eth0" >> new-image/etc/network/interfaces
    echo "iface eth0 inet dhcp" >> new-image/etc/network/interfaces
    echo "auto eth1" >> new-image/etc/network/interfaces
    echo "iface eth1 inet dhcp" >> new-image/etc/network/interfaces

    #TODO: remove this, add to Dockerfile and rebuild
    apt-get install -y make

    dpkg --root new-image  -i ${BASE_PATH}debs/mft-oem-4.2.0-15.amd64.deb
    dpkg --root new-image  -i ${BASE_PATH}debs/mft-4.2.0-15.amd64.deb
    
    #dpkg --root new-image  -i ${BASE_PATH}debs/hw-management_1.mlnx.25.5.2016_amd64.deb
    #dpkg --root new-image  -i ${BASE_PATH}debs/kernel-mft-dkms_4.2.0-15_all.deb
    #install necessary packages
    #cd ${BASE_PATH}debs/
    #execute apt-get download make patch dkms libpci3 pciutils libusb-1.0-0 usbutils libxml2 libxml2-dev dhcpcd5
    cd ${IMAGES_DIR}
    execute tar xvzf ${BASE_PATH}mlnx-baidu-integration/tar/mlnx-spider.debs.tar.gz -C ${BASE_PATH}debs/
    dpkg --root new-image  -i ${BASE_PATH}debs/make_4.0-8.1_amd64.deb
    dpkg --root new-image  -i ${BASE_PATH}debs/patch_2.7.5-1_amd64.deb
    dpkg --root new-image  -i ${BASE_PATH}debs/dkms_2.2.0.3-2_all.deb
    dpkg --root new-image  -i ${BASE_PATH}debs/libpci3_1%3a3.2.1-3_amd64.deb
    dpkg --root new-image  -i ${BASE_PATH}debs/pciutils_1%3a3.2.1-3_amd64.deb
    dpkg --root new-image  -i ${BASE_PATH}debs/libusb-1.0-0_2%3a1.0.19-1_amd64.deb
    dpkg --root new-image  -i ${BASE_PATH}debs/usbutils_1%3a007-2_amd64.deb
    dpkg --root new-image  -i ${BASE_PATH}debs/libxml2_2.9.1+dfsg1-5+deb8u3_amd64.deb
    dpkg --root new-image  -i ${BASE_PATH}debs/libxml2-dev_2.9.1+dfsg1-5+deb8u3_amd64.deb
    dpkg --root new-image  -i ${BASE_PATH}debs/dhcpcd5_6.0.5-2_amd64.deb


    echo "Copying sdk to root path..."
    execute cp -rv ${BASE_PATH}sdk/sdk-output/* new-image/
    echo "Copying SAI to root path..."
    execute cp -rv ${BASE_PATH}sai/sai-output/* new-image/

    echo "Adding some symlinks..."
    mkdir new-image/lib/modules/3.16.7-ckt20+/updates/
    ln -s /lib/modules/3.16.7-ckt20/updates/kernel new-image/lib/modules/3.16.7-ckt20+/updates/kernel
    mkdir new-image/usr/lib/python2.7/site-packages/
    ln -s /lib/python2.7/site-packages/python_sdk_api new-image/usr/lib/python2.7/site-packages/python_sdk_api
    
    #echo "Copying 3.16.7-ckt20 kernel modules to 3.16.7-ckt20+..."
    #cp -v new-image/lib/modules/3.16.7-ckt20/*.ko new-image/lib/modules/3.16.7-ckt20+/
    echo "Copying 3.16.7-ckt20 specifically compiled drivers to 3.16.7-ckt20+ path"
    cp -v ../os/base/kernel/3.16.7/specific-drivers/* new-image/lib/modules/3.16.7-ckt20+/

    dpkg --root new-image  -i ${BASE_PATH}debs/hw-management_1.mlnx.25.5.2016_amd64.deb
    ln -s new-image/lib/modules/3.16.7-ckt20/updates/ new-image/lib/modules/3.16.7-ckt20+/updates/
    cp new-image/lib/modules/3.16.7-ckt20/*.ko new-image/lib/modules/3.16.7-ckt20+/

    cd new-image; tar cvzf ../rootfs-${platform}-with-mlnx.tar.gz *; cd ..;

    cd ${TOP_DIR}

    
done
