# Flags
export KEEPVERITY=false
export KEEPFORCEENCRYPT=false
export RECOVERYMODE=false
export PREINITDEVICE=cache

#########
# Unpack
#########

chmod -R 755 .

CHROMEOS=false

echo "Unpacking boot image"
./magiskboot unpack recovery.img

case $? in
  0 ) ;;
  1 )
    echo "Unsupported/Unknown image format"
    ;;
  2 )
    echo "ChromeOS boot image detected"
    ;;
  * )
    echo "Unable to unpack boot image"
    ;;
esac

###################
# Ramdisk Restores
###################

# Test patch status and do restore
echo "Checking ramdisk status"
if [ -e ramdisk.cpio ]; then
  ./magiskboot cpio ramdisk.cpio test
  STATUS=$?
else
  # Stock A only legacy SAR, or some Android 13 GKIs
  STATUS=0
fi
case $((STATUS & 3)) in
  0 )  # Stock boot
    echo "Stock boot image detected"
    SHA1=$(./magiskboot sha1 recovery.img)
    cp -af ramdisk.cpio ramdisk.cpio.orig 2>/dev/null
    ;;
  1 )  # Magisk patched
    echo "Magisk patched boot image detected"
    # Find SHA1 of stock boot image
    [ -z $SHA1 ] && SHA1=$(./magiskboot cpio ramdisk.cpio sha1)
    ./magiskboot cpio ramdisk.cpio restore
    cp -af ramdisk.cpio ramdisk.cpio.orig 2>/dev/null
    ;;
  2 )  # Unsupported
    echo "Boot image patched by unsupported programs"
    echo "Please restore back to stock boot image"
    ;;
esac

# Work around custom legacy Sony /init -> /(s)bin/init_sony : /init.real setup
INIT=init
if [ $((STATUS & 4)) -ne 0 ]; then
  INIT=init.real
fi

##################
# Ramdisk Patches
##################

echo "- Patching ramdisk"
export SKIP64=""
mkdir cpiotmp
cd cpiotmp
sudo cpio -idv < ../ramdisk.cpio
cd ..
export cpu_abi=$(grep -o 'ro.product.cpu.abi=[^ ]*' cpiotmp/prop.default | cut -d '=' -f 2)
if [ "$cpu_abi" != "arm64-v8a" ]; then
    cpu_abi=armeabi-v7a
    SKIP64="#"
fi

echo -n "RANDOMSEED=" > config
tr -dc A-Za-z0-9 </dev/urandom | head -c 8 >> config
echo -ne "\n" >> config
echo "KEEPVERITY=$KEEPVERITY" >> config
echo "KEEPFORCEENCRYPT=$KEEPFORCEENCRYPT" >> config
echo "RECOVERYMODE=$RECOVERYMODE" >> config
echo "PREINITDEVICE=$PREINITDEVICE" >> config
[ ! -z $SHA1 ] && echo "SHA1=$SHA1" >> config

# Compress to save precious ramdisk space
./magiskboot compress=xz zzz/lib/armeabi-v7a/libmagisk32.so magisk32.xz
$SKIP64 ./magiskboot compress=xz zzz/lib/$cpu_abi/libmagisk64.so magisk64.xz
./magiskboot compress=xz zzz/assets/stub.apk stub.xz

./magiskboot cpio ramdisk.cpio \
"add 0750 $INIT zzz/lib/$cpu_abi/libmagiskinit.so" \
"mkdir 0750 overlay.d" \
"mkdir 0750 overlay.d/sbin" \
"add 0644 overlay.d/sbin/magisk32.xz magisk32.xz" \
"$SKIP64 add 0644 overlay.d/sbin/magisk64.xz magisk64.xz" \
"add 0644 overlay.d/sbin/stub.xz stub.xz" \
"patch" \
"backup ramdisk.cpio.orig" \
"mkdir 000 .backup" \
"add 000 .backup/.magisk config"
