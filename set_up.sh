#!/bin/bash

if [ $# -eq 0 ]
  then
    echo "Should provide one argument to use as base path (a folder that will be created or emptied)"
    exit 1
fi


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

echo "Creating base folder and cloning mlnx-baidu-integration.git to light_branch..."
mkdir ${1}
cd ${1}
BASE_PATH=`pwd`
echo "OK, BASE_PATH=${BASE_PATH}"

execute git clone /net/10.224.1.11/vol/git/switchx/baidu/mlnx-baidu-integration.git/
#execute git checkout 098fffb4a35be8d498861e72b404a56fd63223f4
cd mlnx-baidu-integration
execute git checkout 098fffb4a35be8d498861e72b404a56fd63223f4
#execute git checkout light_branch
cd ../

echo "Extracting kevin_BRANCH.tar.gz..."
execute tar xvzf mlnx-baidu-integration/tar/kevin_BRANCH.tar.gz
cd kevin_BRANCH/images/
cp ../../mlnx-baidu-integration/patches/Makefile .



echo "Applying baidu patches..."
cd ${BASE_PATH}/kevin_BRANCH/os/base/kernel/3.16.7/
execute patch -p1 < ../../../../../mlnx-baidu-integration/patches/arp_neighbor_20160407.patch
cd ../../../../xorplus/
execute patch -p0 < ../../mlnx-baidu-integration/patches/endianess_20160411.patch
cd ${BASE_PATH}

echo "Applying SAI patches to xorplus"
cd kevin_BRANCH/xorplus
patch -p1 < ../../mlnx-baidu-integration/patches/xorplus_migration.patch
chmod u=rwx build-x86_64-mlnx-spider.sh
patch -p1 < ../../mlnx-baidu-integration/patches/lag.patch
cd ${BASE_PATH}

echo "Applying bsp patches to kernel 3.16.7..."
execute mkdir bsp; tar xvzf mlnx-baidu-integration/tar/hw-management.1.mlnx.25.5.2016.orig.tar.gz -C bsp


chmod +x mlnx-baidu-integration/*.sh

cd kevin_BRANCH/os/base/kernel/3.16.7/linux-3.16.7-ckt20/
execute patch -p1 < ${BASE_PATH}/bsp/hw-management/kernel-patches-3.16/ucd9200.patch
#This patch is broken, replace existing files with patches versions of them
cd ${BASE_PATH}
execute cp -f mlnx-baidu-integration/patches/pmbus* kevin_BRANCH/os/base/kernel/3.16.7/linux-3.16.7-ckt20/drivers/hwmon/pmbus/


echo "Overriding kernel's .config"
echo "Setting CONFIG_I2C_MUX_GPIO=m, CONFIG_I2C_MUX_PCA9541=m, CONFIG_I2C_MUX_PCA954x=m, CONFIG_PMBUS=m, CONFIG_SENSORS_PMBUS=m, CONFIG_SENSORS_UCD9200=m, CONFIG_SENSORS_UCD9000=m by replacing .config with custom one"
cd ${BASE_PATH}
execute cp -f mlnx-baidu-integration/patches/kernel-dot-config kevin_BRANCH/os/base/kernel/3.16.7/linux-3.16.7-ckt20/.config


echo "Overriding kernel's makefile to save specific .ko before removing all"
execute cp -f mlnx-baidu-integration/patches/kernel-makefile kevin_BRANCH/os/base/kernel/3.16.7/Makefile


echo "Preparing mlnx-spider drivers copying ag7648 to mlnx-spider"
cd ${BASE_PATH}
execute mkdir kevin_BRANCH/os/base/driver/mlnx-spider;
execute cp -r kevin_BRANCH/os/base/driver/ag7648/*  kevin_BRANCH/os/base/driver/mlnx-spider/;



echo "Replacing BSP debian/rules to compile with specific kernel"
cd ${BASE_PATH}
execute cp -f mlnx-baidu-integration/patches/bsp-rules bsp/hw-management/debian/rules


echo "Preparing SDK compilation..."
cd ${BASE_PATH}
#execute mkdir sdk; execute tar xvzf mlnx-baidu-integration/tar/sx_sdk_eth-4.2.1056_M.tgz -C sdk
#execute cp -f mlnx-baidu-integration/patches/sdk-install.sh sdk/sx_sdk_eth-4.2.1056_M/install.sh
execute mkdir sdk; execute tar xvzf mlnx-baidu-integration/tar/sx_sdk_eth-4.2.1010.tar.gz -C sdk
execute cp -f mlnx-baidu-integration/patches/sdk-install-1010.sh sdk/sx_sdk_eth-4.2.1010/install.sh
execute mkdir -p sdk/sdk-output/usr/src/sx_sdk

echo "Preparing MFT compilation"
cd ${BASE_PATH}
execute mkdir mft; execute tar xvzf mlnx-baidu-integration/tar/mft-4.2.0-15.tgz -C mft
cd mft/mft-4.2.0-15/SRPMS/
rpm2cpio kernel-mft-4.2.0-15.src.rpm | cpio -idmv
tar xzf kernel-mft-4.2.0.tgz
tar czf kernel-mft_4.2.0.orig.tar.gz kernel-mft-4.2.0
 

echo "Prepare SAI to compile"
cd ${BASE_PATH}
execute git clone file:///net/10.224.1.11/vol/git/sai_interface.git sai
execute chmod +x sai/mlnx_sai/auto*
mkdir -p sai/sai-output/
cd sai/mlnx_sai
execute git checkout oldvlan


echo "Move custom rc.local to kevin_BRANCH/images/mlnx-spider/"
cd ${BASE_PATH}
mkdir kevin_BRANCH/images/mlnx-spider
cp mlnx-baidu-integration/images-mlnx-spider/* kevin_BRANCH/images/mlnx-spider/

#TODO: remove this, I'm using ag7648 image since I didn't add mlnx-spider platform yet.
cp -f mlnx-baidu-integration/images-mlnx-spider/* kevin_BRANCH/images/ag7648/

echo "Prepare .deb output..."
execute mkdir ${BASE_PATH}/debs/


echo "Now I will start a docker session. You need to run ./mlnx-baidu-integration/compile.sh from there..."
read -n1 -r -p "Press any key to continue..." key
docker run -it -v ${BASE_PATH}:/baidu/ debian-8.3
