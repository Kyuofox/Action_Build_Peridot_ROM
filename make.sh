#!/bin/bash

VENDOR_URL="$1"       # 底包下载地址
IMAGE_TYPE="$2"      # 打包镜像类型
EXT4_RW="$3"         # 可读EXT4
GITHUB_ENV="$4"       # 输出环境变量
GITHUB_WORKSPACE="$5" # 工作目录

Red='\033[1;31m'    # 粗体红色
Yellow='\033[1;33m' # 粗体黄色
Blue='\033[1;34m'   # 粗体蓝色
Green='\033[1;32m'  # 粗体绿色

device=peridot # 设备代号

vendor_os_version=$(echo ${VENDOR_URL} | cut -d"/" -f4)          # 底包的 OS 版本号, 例: OS1.0.32.0.UNCCNXM
vendor_version=$(echo ${vendor_os_version} | sed 's/OS1/V816/g') # 底包的实际版本号, 例: V816.0.32.0.UNCCNXM
vendor_zip_name=$(echo ${VENDOR_URL} | cut -d"/" -f5)            # 底包的 zip 名称, 例: miui_HOUJI_OS1.0.32.0.UNCCNXM_4fd0e15877_14.0.zip

android_version=$(echo ${VENDOR_URL} | cut -d"_" -f5 | cut -d"." -f1) # Android 版本号, 例: 14
build_time=$(date) && build_utc=$(date -d "$build_time" +%s)   # 构建时间

magiskboot="$GITHUB_WORKSPACE"/tools/magiskboot
a7z="$GITHUB_WORKSPACE"/tools/7zzs
zstd="$GITHUB_WORKSPACE"/tools/zstd
ksud="$GITHUB_WORKSPACE"/tools/lkm_patch/ksud
payload_extract="$GITHUB_WORKSPACE"/tools/payload_extract
mke2fs="$GITHUB_WORKSPACE"/tools/mke2fs
e2fsdroid="$GITHUB_WORKSPACE"/tools/e2fsdroid
erofs_extract="$GITHUB_WORKSPACE"/tools/extract.erofs
erofs_mkfs="$GITHUB_WORKSPACE"/tools/mkfs.erofs
lpmake="$GITHUB_WORKSPACE"/tools/lpmake
apktool_jar="java -jar "$GITHUB_WORKSPACE"/tools/apktool.jar"

sudo chmod -R 777 "$GITHUB_WORKSPACE"/tools

Start_Time() {
  Start_s=$(date +%s)
  Start_ns=$(date +%N)
}

End_Time() {
  local End_s End_ns time_s time_ns
  End_s=$(date +%s)
  End_ns=$(date +%N)
  time_s=$((10#$End_s - 10#$Start_s))
  time_ns=$((10#$End_ns - 10#$Start_ns))
  if ((time_ns < 0)); then
    ((time_s--))
    ((time_ns += 1000000000))
  fi
 
  local ns ms sec min hour
  ns=$((time_ns % 1000000))
  ms=$((time_ns / 1000000))
  sec=$((time_s % 60))
  min=$((time_s / 60 % 60))
  hour=$((time_s / 3600))

  if ((hour > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$hour小时$min分$sec秒$ms毫秒"
  elif ((min > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$min分$sec秒$ms毫秒"
  elif ((sec > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$sec秒$ms毫秒"
  elif ((ms > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$ms毫秒"
  else
    echo -e "${Green}- 本次$1用时: ${Blue}$ns纳秒"
  fi
}

### 系统包下载
echo -e "${Red}- 开始下载系统包"
Start_Time
echo -e "${Yellow}- 开始下载底包"
aria2c -x16 -j$(nproc) -U "Mozilla/5.0" -d "$GITHUB_WORKSPACE" ${VENDOR_URL}
End_Time 下载底包
### 系统包下载结束

### 解包
echo -e "${Red}- 开始解压系统包"
mkdir -p "$GITHUB_WORKSPACE"/images/config
mkdir -p "$GITHUB_WORKSPACE"/zip

echo -e "${Yellow}- 开始解压底包"
Start_Time
$a7z x "$GITHUB_WORKSPACE"/${vendor_zip_name} -o"$GITHUB_WORKSPACE"/images payload.bin >/dev/null
rm -rf "$GITHUB_WORKSPACE"/${vendor_zip_name}
End_Time 解压底包
mkdir -p "$GITHUB_WORKSPACE"/Extra_dir
echo -e "${Red}- 开始解底包 Payload"
$payload_extract -s -o "$GITHUB_WORKSPACE"/Extra_dir/ -i "$GITHUB_WORKSPACE"/images/payload.bin -x -T0
sudo rm -rf "$GITHUB_WORKSPACE"/images/payload.bin
echo -e "${Red}- 开始分解底包 Images"
for i in mi_ext product system system_ext system_dlkm odm vendor vendor_dlkm; do
  echo -e "${Yellow}- 正在分解底包: $i.img"
  cd "$GITHUB_WORKSPACE"/images
  sudo $erofs_extract -i "$GITHUB_WORKSPACE"/Extra_dir/$i.img -x -s
  rm -rf "$GITHUB_WORKSPACE"/Extra_dir/$i.img
done
sudo mkdir -p "$GITHUB_WORKSPACE"/images/firmware-update/
sudo cp -rf "$GITHUB_WORKSPACE"/Extra_dir/* "$GITHUB_WORKSPACE"/images/firmware-update/
### 解包结束

### 写入变量
echo -e "${Red}- 开始写入变量"
# 构建日期
echo "build_time=$build_time" >>$GITHUB_ENV
echo -e "${Blue}- 构建日期: $build_time"
# 底包版本
echo -e "${Blue}- 底包版本: $vendor_os_version"
echo "vendor_os_version=$vendor_os_version" >>$GITHUB_ENV
# 底包安全补丁
vendor_build_prop=$GITHUB_WORKSPACE/images/vendor/build.prop
vendor_security_patch=$(grep "ro.vendor.build.security_patch=" "$vendor_build_prop" | awk -F "=" '{print $2}')
echo -e "${Blue}- 底包安全补丁版本: $vendor_security_patch"
echo "vendor_security_patch=$vendor_security_patch" >>$GITHUB_ENV
# 底包vendor基线版本
vendor_base_line=$(grep "ro.vendor.build.id=" "$vendor_build_prop" | awk -F "=" '{print $2}')
echo -e "${Blue}- 底包基线版本: $vendor_base_line"
echo "vendor_base_line=$vendor_base_line" >>$GITHUB_ENV
### 写入变量结束

### 功能修改
echo -e "${Red}- 开始功能修改"
Start_Time
# 修改 Vendor Boot
echo -e "${Red}- 修改 Vendor Boot"
mkdir -p "$GITHUB_WORKSPACE"/vendor_boot
cd "$GITHUB_WORKSPACE"/vendor_boot
mv -f "$GITHUB_WORKSPACE"/images/firmware-update/vendor_boot.img "$GITHUB_WORKSPACE"/vendor_boot
$magiskboot unpack -h "$GITHUB_WORKSPACE"/vendor_boot/vendor_boot.img 2>&1
if [ -f ramdisk.cpio ]; then
  comp=$($magiskboot decompress ramdisk.cpio 2>&1 | grep -v 'raw' | sed -n 's;.*\[\(.*\)\];\1;p')
elif [ -d vendor_ramdisk ]; then
  cpio_files="$GITHUB_WORKSPACE/vendor_boot/vendor_ramdisk/ramdisk.cpio $(ls -1 $GITHUB_WORKSPACE/vendor_boot/vendor_ramdisk/*.cpio | grep -vE '/ramdisk\.cpio$')";
  if [ "$comp" ]; then
    mv -f ramdisk.cpio ramdisk.cpio.$comp
    $magiskboot decompress ramdisk.cpio.$comp ramdisk.cpio 2>&1
    if [ $? != 0 ] && $comp --help 2>/dev/null; then
      $comp -dc ramdisk.cpio.$comp >ramdisk.cpio
    fi
  fi
  mkdir -p ramdisk
  chmod 755 ramdisk
  cd ramdisk
  if [ "$cpio_files" ]; then
    for cpio_file in ${cpio_files}; do
      $magiskboot cpio $cpio_file extract &>/dev/null
    done;
  else
    $magiskboot cpio ../ramdisk.cpio extract &>/dev/null
  fi
fi
## 移除 mi_ext 和 pangu (fstab)
if [[ "${IMAGE_TYPE}" == "ext4" && "${EXT4_RW}" == "true" ]]; then
  echo -e "\e[1;33m- 移除 mi_ext 和 pangu (fstab) \e[0m"
  sudo sed -i "/mi_ext/d" "$GITHUB_WORKSPACE"/"${device}"_files/fstab.qcom
  sudo sed -i "/overlay/d" "$GITHUB_WORKSPACE"/"${device}"_files/fstab.qcom
fi
# 替换 ramdisk 的 fstab
echo -e "${Red}- 替换 ramdisk 的 fstab"
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/fstab.qcom "$GITHUB_WORKSPACE"/vendor_boot/ramdisk/first_stage_ramdisk/fstab.qcom
sudo chmod 644 "$GITHUB_WORKSPACE"/vendor_boot/ramdisk/first_stage_ramdisk/fstab.qcom
## 重新打包 Vendor Boot
cd "$GITHUB_WORKSPACE"/vendor_boot/ramdisk/
find . | grep -vE '^\.$' | sort | cpio -H newc -o > ../ramdisk_new.cpio
cd ..
if [ "$comp" ]; then
  $magiskboot compress=$comp ramdisk_new.cpio 2>&1
  if [ $? != 0 ] && $comp --help 2>/dev/null; then
    $comp -9c ramdisk_new.cpio >ramdisk.cpio.$comp
  fi
fi
ramdisk=$(ls ramdisk_new.cpio* 2>/dev/null | tail -n1)
if [ "$ramdisk" ]; then
  if [ -d vendor_ramdisk ]; then
    for f in vendor_ramdisk/*.cpio; do
      cp -f "$GITHUB_WORKSPACE"/tools/_extra/empty.cpio $f;
    done;
    cp -f $ramdisk vendor_ramdisk/ramdisk.cpio;
  else
    cp -f $ramdisk ramdisk.cpio;
  fi;
  case $comp in
  cpio) nocompflag="-n" ;;
  esac
  $magiskboot repack $nocompflag "$GITHUB_WORKSPACE"/vendor_boot/vendor_boot.img "$GITHUB_WORKSPACE"/images/firmware-update/vendor_boot.img 2>&1
fi
sudo rm -rf "$GITHUB_WORKSPACE"/vendor_boot
# 替换 Vendor 的 fstab
echo -e "${Red}- 替换 vendor 的 fstab"
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/fstab.qcom "$GITHUB_WORKSPACE"/images/vendor/etc/fstab.qcom
# 添加 Root (刷入时可自行选择)
echo -e "${Red}- 添加 ROOT (刷入时可自行选择)"
## 修补 Magisk 27.0 (Official)
echo -e "${Yellow}- 修补 Magisk 28.0 (Official)"
sh "$GITHUB_WORKSPACE"/tools/magisk_patch/boot_patch.sh "$GITHUB_WORKSPACE"/images/firmware-update/init_boot.img
mv "$GITHUB_WORKSPACE"/tools/magisk_patch/new-boot.img "$GITHUB_WORKSPACE"/images/firmware-update/init_boot-magisk.img
## Patch KernelSU
echo -e "${Yellow}- Patch KernelSU"
mkdir -p "$GITHUB_WORKSPACE"/init_boot
cd "$GITHUB_WORKSPACE"/init_boot
cp -f "$GITHUB_WORKSPACE"/images/firmware-update/init_boot.img "$GITHUB_WORKSPACE"/init_boot
$ksud boot-patch -b "$GITHUB_WORKSPACE"/init_boot/init_boot.img --magiskboot $magiskboot --kmi android14-6.1
mv -f "$GITHUB_WORKSPACE"/init_boot/kernelsu_*.img "$GITHUB_WORKSPACE"/images/firmware-update/init_boot-kernelsu.img
rm -rf "$GITHUB_WORKSPACE"/init_boot
# 禁用恢复预置应用提示
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/auto-install.json "$GITHUB_WORKSPACE"/images/product/etc/
# 统一 build.prop
echo -e "${Red}- 统一 build.prop"
sudo sed -i 's/ro.build.user=[^*]*/ro.build.user=YuKongA,Kyuofox/' "$GITHUB_WORKSPACE"/images/system/system/build.prop
sudo find "$GITHUB_WORKSPACE"/images/ -path "$GITHUB_WORKSPACE"/images/mi_ext -prune -o -type f -name 'build.prop' -print | while read -r port_build_prop; do
  sudo sed -i 's/build.date=[^*]*/build.date='"${build_time}"'/' "${port_build_prop}"
  sudo sed -i 's/build.date.utc=[^*]*/build.date.utc='"${build_utc}"'/' "${port_build_prop}"
done
# 清除套壳应用
mi_ext_build_iick=$(find "$GITHUB_WORKSPACE"/images/ -type f -name 'build.prop' 2>/dev/null | xargs grep -rl "ro.miui.support.system.app.uninstall.v2=true" | sed 's/^\.\///' | sort)
if [ ! -z $mi_ext_build_iick ];then
  echo -e "${Red}- 开始清除套壳应用"
  for ext_build in $(find "$GITHUB_WORKSPACE"/images/ -type f -name 'build.prop' 2>/dev/null | xargs grep -rl "ro.miui.support.system.app.uninstall.v2" | sed 's/^\.\///' | sort)
  do
    echo -e "${Yellow}- 定位到文件: $ext_build"
    sed -i "/ro.miui.support.system.app.uninstall.v2/d" "$ext_build"
  done
  find "$GITHUB_WORKSPACE"/images/mi_ext/ -type f -iname "*miui-uninstall*" -exec rm -f {} \;
  find "$GITHUB_WORKSPACE"/images/mi_ext/ -type f -iname "*sec_overlay*" -exec rm -f {} \;
  for files in MIUISecurityManager MIUIThemeStore
  do
    appsui=$(find "$GITHUB_WORKSPACE"/images/product/data-app/ -type d -iname "*${files}*")
    if [ ! -z $appsui ];then
      echo -e "${Yellow}- 得到精简目录: $appsui"
      rm -rf $appsui
    fi
  done
fi
# 精简部分应用
echo -e "${Red}- 精简部分应用"
apps=("MIGalleryLockscreen" "MIpay" "MIUIDriveMode" "MIUIDuokanReader" "MIUIGameCenter" "MIUINewHome" "MIUIYoupin" "MIUIHuanJi" "MIUIMiDrive" "MIUIVirtualSim" "ThirdAppAssistant" "XMRemoteController" "MIUIVipAccount" "MiuiScanner" "Xinre" "SmartHome" "MiShop" "MiRadio" "MIUICompass" "BaiduIME" "iflytek.inputmethod" "MIService" "MIUIEmail" "MIUIVideo" "MIUIMusicT" "Health" "iFlytekIME" "OS2VipAccount")
for app in "${apps[@]}"; do
  appsui=$(sudo find "$GITHUB_WORKSPACE"/images/product/data-app/ -type d -iname "*${app}*")
  if [[ -n $appsui ]]; then
    echo -e "${Yellow}- 找到精简目录: $appsui"
    sudo rm -rf "$appsui"
  fi
done
# 添加aptX Lossless支持
echo -e "${Red}- 添加 aptX Lossless 支持"
sudo sed -i '/persist\.vendor\.qcom\.bluetooth\.aptxadaptiver2_1_support/a persist.vendor.qcom.bluetooth.aptxadaptiver2_2_support=true' "$GITHUB_WORKSPACE"/images/vendor/build.prop
# 占位广告应用
echo -e "${Red}- 占位广告应用"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/app/MSA/*
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/MSA.apk "$GITHUB_WORKSPACE"/images/product/app/MSA
# 替换完美图标
echo -e "${Red}- 替换完美图标"
cd "$GITHUB_WORKSPACE"
git clone --depth=1 https://github.com/pzcn/Perfect-Icons-Completion-Project.git icons &>/dev/null
for pkg in "$GITHUB_WORKSPACE"/images/product/media/theme/miui_mod_icons/dynamic/*; do
  if [[ -d "$GITHUB_WORKSPACE"/icons/icons/$pkg ]]; then
    rm -rf "$GITHUB_WORKSPACE"/icons/icons/$pkg
  fi
done
rm -rf "$GITHUB_WORKSPACE"/icons/icons/com.xiaomi.scanner
mv "$GITHUB_WORKSPACE"/images/product/media/theme/default/icons "$GITHUB_WORKSPACE"/images/product/media/theme/default/icons.zip
rm -rf "$GITHUB_WORKSPACE"/images/product/media/theme/default/dynamicicons
mkdir -p "$GITHUB_WORKSPACE"/icons/res
mv "$GITHUB_WORKSPACE"/icons/icons "$GITHUB_WORKSPACE"/icons/res/drawable-xxhdpi
cd "$GITHUB_WORKSPACE"/icons
zip -qr "$GITHUB_WORKSPACE"/images/product/media/theme/default/icons.zip res
cd "$GITHUB_WORKSPACE"/icons/themes/Hyper/
zip -qr "$GITHUB_WORKSPACE"/images/product/media/theme/default/dynamicicons.zip layer_animating_icons
cd "$GITHUB_WORKSPACE"/icons/themes/common/
zip -qr "$GITHUB_WORKSPACE"/images/product/media/theme/default/dynamicicons.zip layer_animating_icons
mv "$GITHUB_WORKSPACE"/images/product/media/theme/default/icons.zip "$GITHUB_WORKSPACE"/images/product/media/theme/default/icons
mv "$GITHUB_WORKSPACE"/images/product/media/theme/default/dynamicicons.zip "$GITHUB_WORKSPACE"/images/product/media/theme/default/dynamicicons
rm -rf "$GITHUB_WORKSPACE"/icons
# 常规修改
sudo rm -rf "$GITHUB_WORKSPACE"/images/vendor/recovery-from-boot.p
sudo rm -rf "$GITHUB_WORKSPACE"/images/vendor/bin/install-recovery.sh
sudo unzip -o -q "$GITHUB_WORKSPACE"/tools/flashtools.zip -d "$GITHUB_WORKSPACE"/images
# 移除 Android 签名校验
sudo mkdir -p "$GITHUB_WORKSPACE"/apk/
echo -e "${Red}- 移除 Android 签名校验"
sudo cp -rf "$GITHUB_WORKSPACE"/images/system/system/framework/services.jar "$GITHUB_WORKSPACE"/apk/services.apk
cd "$GITHUB_WORKSPACE"/apk
sudo $apktool_jar d -q "$GITHUB_WORKSPACE"/apk/services.apk
fbynr='getMinimumSignatureSchemeVersionForTargetSdk'
sudo find "$GITHUB_WORKSPACE"/apk/services/smali_classes2/com/android/server/pm/ "$GITHUB_WORKSPACE"/apk/services/smali_classes2/com/android/server/pm/pkg/parsing/ -type f -maxdepth 1 -name "*.smali" -exec grep -H "$fbynr" {} \; | cut -d ':' -f 1 | while read -r i; do
  hs=$(grep -n "$fbynr" "$i" | cut -d ':' -f 1)
  sz=$(sudo tail -n +"$hs" "$i" | grep -m 1 "move-result" | tr -dc '0-9')
  hs1=$(sudo awk -v HS=$hs 'NR>=HS && /move-result /{print NR; exit}' "$i")
  hss=$hs
  sedsc="const/4 v${sz}, 0x0"
  { sudo sed -i "${hs},${hs1}d" "$i" && sudo sed -i "${hss}i\\${sedsc}" "$i"; } && echo -e "${Yellow}- ${i} 修改成功"
done
cd "$GITHUB_WORKSPACE"/apk/services/
sudo $apktool_jar b -q -f -c "$GITHUB_WORKSPACE"/apk/services/ -o services.jar
sudo cp -rf "$GITHUB_WORKSPACE"/apk/services/services.jar "$GITHUB_WORKSPACE"/images/system/system/framework/services.jar
# ext4_rw 修改
if [[ "${IMAGE_TYPE}" == "ext4" && "${EXT4_RW}" == "true" ]]; then
  ## 移除 mi_ext 和 pangu (product)
  pangu="$GITHUB_WORKSPACE"/images/product/pangu/system
  sudo find "$pangu" -type d | sed "s|$pangu|/system/system|g" | sed 's/$/ u:object_r:system_file:s0/' >>"$GITHUB_WORKSPACE"/images/config/system_file_contexts
  sudo find "$pangu" -type f | sed 's/\./\\./g' | sed "s|$pangu|/system/system|g" | sed 's/$/ u:object_r:system_file:s0/' >>"$GITHUB_WORKSPACE"/images/config/system_file_contexts
  sudo cp -rf "$GITHUB_WORKSPACE"/images/product/pangu/system/* "$GITHUB_WORKSPACE"/images/system/system/
  sudo rm -rf "$GITHUB_WORKSPACE"/images/product/pangu/system/*
fi
# 补全ext4_rw修改后HyperOS所缺失的overlays
if [[ "${IMAGE_TYPE}" == "ext4" && "${EXT4_RW}" == "true" ]]; then
  echo -e "${Red}- 补全 HyperOS 叠加层"
  i=1
  find "$GITHUB_WORKSPACE"/images/mi_ext -type f -name "*.apk" | while read -r overlays; do
    echo -e "${Yellow}- 找到文件: $overlays"
    cp -rf "$overlays" "$GITHUB_WORKSPACE"/images/product/overlay/
    i=$((i+1))
  done
fi
# 系统更新获取更新路径对齐
echo -e "${Red}- 系统更新获取更新路径对齐"
for mod_device_build in $(sudo find "$GITHUB_WORKSPACE"/images/ -type f -name 'build.prop' 2>/dev/null | xargs grep -rl 'ro.product.mod_device=' | sed 's/^\.\///' | sort); do
  if echo "${date}" | grep -q "XM" || echo "${date}" | grep -q "DEV"; then
    sudo sed -i 's/ro.product.mod_device=[^*]*/ro.product.mod_device=peridot/' "$mod_device_build"
  else
    sudo sed -i 's/ro.product.mod_device=[^*]*/ro.product.mod_device=peridot_pre/' "$mod_device_build"
  fi
done
# 为HyperOS添加版本信息
if [[ "${IMAGE_TYPE}" == "ext4" && "${EXT4_RW}" == "true" ]]; then
  echo -e "${Red}- 补全 HyperOS 版本信息"
  product_build_prop=$(sudo find "$GITHUB_WORKSPACE"/images/product/ -type f -name "build.prop")
  mi_ext_build_prop=$(sudo find "$GITHUB_WORKSPACE"/images/mi_ext/ -type f -name "build.prop")
  search_keywords=("mi.os" "ro.miui" "mod_device")
  while IFS= read -r line; do
    for keyword in "${search_keywords[@]}"; do
      if [[ $line == *"$keyword"* ]]; then
        echo -e "${Yellow}- 找到指定字符: $line"
        sudo sed -i "$(sudo sed -n "/ro.product.build.version.sdk/=" "$product_build_prop")a $line" "$product_build_prop"
      fi
    done
  done < "$mi_ext_build_prop"
fi
# 替换更改文件/删除多余文件
echo -e "${Red}- 替换更改文件/删除多余文件"
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"_files
End_Time 功能修复
### 功能修复结束

### 生成 super.img
echo -e "${Red}- 开始打包super.img"
Start_Time
partitions=("mi_ext" "odm" "product" "system" "system_ext" "system_dlkm" "vendor" "vendor_dlkm")
if [[ "${IMAGE_TYPE}" == "erofs" ]]; then
  for partition in "${partitions[@]}"; do
    echo -e "${Red}- 正在生成: $partition"
    sudo python3 "$GITHUB_WORKSPACE"/tools/fspatch.py "$GITHUB_WORKSPACE"/images/$partition "$GITHUB_WORKSPACE"/images/config/"$partition"_fs_config
    sudo python3 "$GITHUB_WORKSPACE"/tools/contextpatch.py "$GITHUB_WORKSPACE"/images/$partition "$GITHUB_WORKSPACE"/images/config/"$partition"_file_contexts
    Start_Time
    sudo $erofs_mkfs --quiet -zlz4hc,9 -T 1230768000 --mount-point /$partition --fs-config-file "$GITHUB_WORKSPACE"/images/config/"$partition"_fs_config --file-contexts "$GITHUB_WORKSPACE"/images/config/"$partition"_file_contexts "$GITHUB_WORKSPACE"/images/$partition.img "$GITHUB_WORKSPACE"/images/$partition
    End_Time 打包erofs
    eval "$partition"_size=$(du -sb "$GITHUB_WORKSPACE"/images/$partition.img | awk {'print $1'})
    sudo rm -rf "$GITHUB_WORKSPACE"/images/$partition
  done
  sudo rm -rf "$GITHUB_WORKSPACE"/images/config
  Start_Time
  $lpmake --metadata-size 65536 --super-name super --block-size 4096 --partition mi_ext_a:readonly:"$mi_ext_size":qti_dynamic_partitions_a --image mi_ext_a="$GITHUB_WORKSPACE"/images/mi_ext.img --partition mi_ext_b:readonly:0:qti_dynamic_partitions_b --partition odm_a:readonly:"$odm_size":qti_dynamic_partitions_a --image odm_a="$GITHUB_WORKSPACE"/images/odm.img --partition odm_b:readonly:0:qti_dynamic_partitions_b --partition product_a:readonly:"$product_size":qti_dynamic_partitions_a --image product_a="$GITHUB_WORKSPACE"/images/product.img --partition product_b:readonly:0:qti_dynamic_partitions_b --partition system_a:readonly:"$system_size":qti_dynamic_partitions_a --image system_a="$GITHUB_WORKSPACE"/images/system.img --partition system_b:readonly:0:qti_dynamic_partitions_b --partition system_ext_a:readonly:"$system_ext_size":qti_dynamic_partitions_a --image system_ext_a="$GITHUB_WORKSPACE"/images/system_ext.img --partition system_ext_b:readonly:0:qti_dynamic_partitions_b --partition system_dlkm_a:readonly:"$system_dlkm_size":qti_dynamic_partitions_a --image system_dlkm_a="$GITHUB_WORKSPACE"/images/system_dlkm.img --partition system_dlkm_b:readonly:0:qti_dynamic_partitions_b --partition vendor_a:readonly:"$vendor_size":qti_dynamic_partitions_a --image vendor_a="$GITHUB_WORKSPACE"/images/vendor.img --partition vendor_b:readonly:0:qti_dynamic_partitions_b --partition vendor_dlkm_a:readonly:"$vendor_dlkm_size":qti_dynamic_partitions_a --image vendor_dlkm_a="$GITHUB_WORKSPACE"/images/vendor_dlkm.img --partition vendor_dlkm_b:readonly:0:qti_dynamic_partitions_b --device super:9663676416 --metadata-slots 3 --group qti_dynamic_partitions_a:9126805504 --group qti_dynamic_partitions_b:9126805504 --virtual-ab -F --output "$GITHUB_WORKSPACE"/images/super.img
  End_Time 打包super
  for partition in "${partitions[@]}"; do
    rm -rf "$GITHUB_WORKSPACE"/images/$partition.img
  done
elif [[ "${IMAGE_TYPE}" == "ext4" ]]; then
  img_free() {
    size_free="$(tune2fs -l "$GITHUB_WORKSPACE"/images/${partition}.img | awk '/Free blocks:/ { print $3 }')"
    size_free="$(echo "$size_free / 4096 * 1024 * 1024" | bc)"
    if [[ $size_free -ge 1073741824 ]]; then
      File_Type=$(awk "BEGIN{print $size_free/1073741824}")G
    elif [[ $size_free -ge 1048576 ]]; then
      File_Type=$(awk "BEGIN{print $size_free/1048576}")MB
    elif [[ $size_free -ge 1024 ]]; then
      File_Type=$(awk "BEGIN{print $size_free/1024}")kb
    elif [[ $size_free -le 1024 ]]; then
      File_Type=${size_free}b
    fi
    echo -e "${Yellow}- ${partition}.img 剩余空间: $File_Type"
  }
  for partition in "${partitions[@]}"; do
    eval "$partition"_size_orig=$(sudo du -sb "$GITHUB_WORKSPACE"/images/$partition | awk {'print $1'})
    if [[ "$(eval echo "$"$partition"_size_orig")" -lt "104857600" ]]; then
      size=$(echo "$(eval echo "$"$partition"_size_orig") * 15 / 10 / 4096 * 4096" | bc)
    elif [[ "$(eval echo "$"$partition"_size_orig")" -lt "1073741824" ]]; then
      size=$(echo "$(eval echo "$"$partition"_size_orig") * 108 / 100 / 4096 * 4096" | bc)
    else
      size=$(echo "$(eval echo "$"$partition"_size_orig") * 103 / 100 / 4096 * 4096" | bc)
    fi
    eval "$partition"_size=$(echo "$size * 4096 / 4096 / 4096" | bc)
  done
  for partition in "${partitions[@]}"; do
    mkdir -p "$GITHUB_WORKSPACE"/images/$partition/lost+found
    sudo touch -t 200901010000.00 "$GITHUB_WORKSPACE"/images/$partition/lost+found
  done
  for partition in "${partitions[@]}"; do
    echo -e "${Red}- 正在生成: $partition"
    sudo python3 "$GITHUB_WORKSPACE"/tools/fspatch.py "$GITHUB_WORKSPACE"/images/$partition "$GITHUB_WORKSPACE"/images/config/"$partition"_fs_config
    sudo python3 "$GITHUB_WORKSPACE"/tools/contextpatch.py "$GITHUB_WORKSPACE"/images/$partition "$GITHUB_WORKSPACE"/images/config/"$partition"_file_contexts
    eval "$partition"_inode=$(sudo cat "$GITHUB_WORKSPACE"/images/config/"$partition"_fs_config | wc -l)
    eval "$partition"_inode=$(echo "$(eval echo "$"$partition"_inode") + 8" | bc)
    $mke2fs -O ^has_journal -L $partition -I 256 -N $(eval echo "$"$partition"_inode") -M /$partition -m 0 -t ext4 -b 4096 "$GITHUB_WORKSPACE"/images/$partition.img $(eval echo "$"$partition"_size") || false
    Start_Time
    if [[ "${EXT4_RW}" == "true" ]]; then
      sudo $e2fsdroid -e -T 1230768000 -C "$GITHUB_WORKSPACE"/images/config/"$partition"_fs_config -S "$GITHUB_WORKSPACE"/images/config/"$partition"_file_contexts -f "$GITHUB_WORKSPACE"/images/$partition -a /$partition "$GITHUB_WORKSPACE"/images/$partition.img || false
    else
      sudo $e2fsdroid -e -T 1230768000 -C "$GITHUB_WORKSPACE"/images/config/"$partition"_fs_config -S "$GITHUB_WORKSPACE"/images/config/"$partition"_file_contexts -f "$GITHUB_WORKSPACE"/images/$partition -a /$partition -s "$GITHUB_WORKSPACE"/images/$partition.img || false
    fi
    End_Time 打包"$partition".img
    resize2fs -f -M "$GITHUB_WORKSPACE"/images/$partition.img
    eval "$partition"_size=$(du -sb "$GITHUB_WORKSPACE"/images/$partition.img | awk {'print $1'})
    img_free
    if [[ $partition == mi_ext ]]; then
      sudo rm -rf "$GITHUB_WORKSPACE"/images/$partition
      continue
    fi
    size_free=$(tune2fs -l "$GITHUB_WORKSPACE"/images/$partition.img | awk '/Free blocks:/ { print $3}')
    # 第二次打包 (不预留空间)
    if [[ "$size_free" != 0 && "${EXT4_RW}" != "true" ]]; then
      size_free=$(echo "$size_free * 4096" | bc)
      eval "$partition"_size=$(echo "$(eval echo "$"$partition"_size") - $size_free" | bc)
      eval "$partition"_size=$(echo "$(eval echo "$"$partition"_size") * 4096 / 4096 / 4096" | bc)
      sudo rm -rf "$GITHUB_WORKSPACE"/images/$partition.img
      echo -e "${Red}- 二次生成: $partition"
      $mke2fs -O ^has_journal -L $partition -I 256 -N $(eval echo "$"$partition"_inode") -M /$partition -m 0 -t ext4 -b 4096 "$GITHUB_WORKSPACE"/images/$partition.img $(eval echo "$"$partition"_size") || false
      Start_Time
      if [[ "${EXT4_RW}" == "true" ]]; then
        sudo $e2fsdroid -e -T 1230768000 -C "$GITHUB_WORKSPACE"/images/config/"$partition"_fs_config -S "$GITHUB_WORKSPACE"/images/config/"$partition"_file_contexts -f "$GITHUB_WORKSPACE"/images/$partition -a /$partition "$GITHUB_WORKSPACE"/images/$partition.img || false
      else
        sudo $e2fsdroid -e -T 1230768000 -C "$GITHUB_WORKSPACE"/images/config/"$partition"_fs_config -S "$GITHUB_WORKSPACE"/images/config/"$partition"_file_contexts -f "$GITHUB_WORKSPACE"/images/$partition -a /$partition -s "$GITHUB_WORKSPACE"/images/$partition.img || false
      fi
      End_Time 二次打包"$partition".img
      resize2fs -f -M "$GITHUB_WORKSPACE"/images/$partition.img
      eval "$partition"_size=$(du -sb "$GITHUB_WORKSPACE"/images/$partition.img | awk {'print $1'})
      img_free
    fi
    # 第二次打包 (除 mi_ext/system_dlkm/vendor_dlkm 外各预留 100M 空间)
    if [[ "${EXT4_RW}" == "true" ]]; then
      if [[ $partition != mi_ext && $partition != system_dlkm && $partition != vendor_dlkm ]]; then
        eval "$partition"_size=$(echo "$(eval echo "$"$partition"_size") + 104857600" | bc)
        eval "$partition"_size=$(echo "$(eval echo "$"$partition"_size") * 4096 / 4096 / 4096" | bc)
        sudo rm -rf "$GITHUB_WORKSPACE"/images/$partition.img
        echo -e "${Red}- 二次生成: $partition"
        $mke2fs -O ^has_journal -L $partition -I 256 -N $(eval echo "$"$partition"_inode") -M /$partition -m 0 -t ext4 -b 4096 "$GITHUB_WORKSPACE"/images/$partition.img $(eval echo "$"$partition"_size") || false
        Start_Time
        if [[ "${EXT4_RW}" == "true" ]]; then
          sudo $e2fsdroid -e -T 1230768000 -C "$GITHUB_WORKSPACE"/images/config/"$partition"_fs_config -S "$GITHUB_WORKSPACE"/images/config/"$partition"_file_contexts -f "$GITHUB_WORKSPACE"/images/$partition -a /$partition "$GITHUB_WORKSPACE"/images/$partition.img || false
        else
          sudo $e2fsdroid -e -T 1230768000 -C "$GITHUB_WORKSPACE"/images/config/"$partition"_fs_config -S "$GITHUB_WORKSPACE"/images/config/"$partition"_file_contexts -f "$GITHUB_WORKSPACE"/images/$partition -a /$partition -s "$GITHUB_WORKSPACE"/images/$partition.img || false
        fi
        End_Time 二次打包"$partition".img
        eval "$partition"_size=$(du -sb "$GITHUB_WORKSPACE"/images/$partition.img | awk {'print $1'})
        img_free
      fi
    fi
    sudo rm -rf "$GITHUB_WORKSPACE"/images/$partition
  done
  sudo rm -rf "$GITHUB_WORKSPACE"/images/config
  sudo rm -rf "$GITHUB_WORKSPACE"/images/mi_ext
  $lpmake --metadata-size 65536 --super-name super --block-size 4096 --partition mi_ext_a:readonly:"$mi_ext_size":qti_dynamic_partitions_a --image mi_ext_a="$GITHUB_WORKSPACE"/images/mi_ext.img --partition mi_ext_b:readonly:0:qti_dynamic_partitions_b --partition odm_a:readonly:"$odm_size":qti_dynamic_partitions_a --image odm_a="$GITHUB_WORKSPACE"/images/odm.img --partition odm_b:readonly:0:qti_dynamic_partitions_b --partition product_a:readonly:"$product_size":qti_dynamic_partitions_a --image product_a="$GITHUB_WORKSPACE"/images/product.img --partition product_b:readonly:0:qti_dynamic_partitions_b --partition system_a:readonly:"$system_size":qti_dynamic_partitions_a --image system_a="$GITHUB_WORKSPACE"/images/system.img --partition system_b:readonly:0:qti_dynamic_partitions_b --partition system_ext_a:readonly:"$system_ext_size":qti_dynamic_partitions_a --image system_ext_a="$GITHUB_WORKSPACE"/images/system_ext.img --partition system_ext_b:readonly:0:qti_dynamic_partitions_b --partition system_dlkm_a:readonly:"$system_dlkm_size":qti_dynamic_partitions_a --image system_dlkm_a="$GITHUB_WORKSPACE"/images/system_dlkm.img --partition system_dlkm_b:readonly:0:qti_dynamic_partitions_b --partition vendor_a:readonly:"$vendor_size":qti_dynamic_partitions_a --image vendor_a="$GITHUB_WORKSPACE"/images/vendor.img --partition vendor_b:readonly:0:qti_dynamic_partitions_b --partition vendor_dlkm_a:readonly:"$vendor_dlkm_size":qti_dynamic_partitions_a --image vendor_dlkm_a="$GITHUB_WORKSPACE"/images/vendor_dlkm.img --partition vendor_dlkm_b:readonly:0:qti_dynamic_partitions_b --device super:9663676416 --metadata-slots 3 --group qti_dynamic_partitions_a:9126805504 --group qti_dynamic_partitions_b:9126805504 --virtual-ab -F --output "$GITHUB_WORKSPACE"/images/super.img
  End_Time 打包super
  for partition in "${partitions[@]}"; do
    rm -rf "$GITHUB_WORKSPACE"/images/$partition.img
  done
fi
### 生成 super.img 结束

### 输出刷机包
echo -e "${Red}- 开始生成刷机包"
echo -e "${Red}- 开始压缩super.zst"
Start_Time
sudo find "$GITHUB_WORKSPACE"/images/ -exec touch -t 200901010000.00 {} \;
zstd -12 -f "$GITHUB_WORKSPACE"/images/super.img -o "$GITHUB_WORKSPACE"/images/super.zst --rm
End_Time 压缩super.zst
# 生成刷机包
echo -e "${Red}- 生成刷机包"
Start_Time
sudo $a7z a "$GITHUB_WORKSPACE"/zip/miui_${device}_${vendor_os_version}.zip "$GITHUB_WORKSPACE"/images/* >/dev/null
sudo rm -rf "$GITHUB_WORKSPACE"/images
End_Time 压缩卡刷包
# 定制 ROM 包名
echo -e "${Red}- 定制 ROM 包名"
md5=$(md5sum "$GITHUB_WORKSPACE"/zip/miui_${device}_${vendor_os_version}.zip)
echo "MD5=${md5:0:32}" >>$GITHUB_ENV
zip_md5=${md5:0:10}
if [[ "${IMAGE_TYPE}" == "erofs" ]]; then
    image_type="EROFS"
  else
    image_type="EXT4"
    if [[ "${EXT4_RW}" == "true" ]]; then
      image_type+="_RW"
    fi
fi
device_name=$(echo "${device}" | tr 'a-z' 'A-Z')
rom_name="miui_${device_name}_${vendor_os_version}_${zip_md5}_${android_version}.0_2in1_${image_type}.zip"
sudo mv "$GITHUB_WORKSPACE"/zip/miui_${device}_${vendor_os_version}.zip "$GITHUB_WORKSPACE"/zip/"${rom_name}"
echo "rom_name=$rom_name" >>$GITHUB_ENV
### 输出刷机包结束
