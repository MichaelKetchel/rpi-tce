
ARCH=arm64
CROSS_COMPILE=aarch64-linux-gnu-

CPP		= $(CC) -E
ifneq ($(LLVM),)
CC		= $(LLVM_PREFIX)clang$(LLVM_SUFFIX)
LD		= $(LLVM_PREFIX)ld.lld$(LLVM_SUFFIX)
AR		= $(LLVM_PREFIX)llvm-ar$(LLVM_SUFFIX)
NM		= $(LLVM_PREFIX)llvm-nm$(LLVM_SUFFIX)
OBJCOPY		= $(LLVM_PREFIX)llvm-objcopy$(LLVM_SUFFIX)
OBJDUMP		= $(LLVM_PREFIX)llvm-objdump$(LLVM_SUFFIX)
READELF		= $(LLVM_PREFIX)llvm-readelf$(LLVM_SUFFIX)
STRIP		= $(LLVM_PREFIX)llvm-strip$(LLVM_SUFFIX)
else
CC		= $(CROSS_COMPILE)gcc
LD		= $(CROSS_COMPILE)ld
AR		= $(CROSS_COMPILE)ar
NM		= $(CROSS_COMPILE)nm
OBJCOPY		= $(CROSS_COMPILE)objcopy
OBJDUMP		= $(CROSS_COMPILE)objdump
READELF		= $(CROSS_COMPILE)readelf
STRIP		= $(CROSS_COMPILE)strip
endif


rebootp: rebootp.c
	rm -rf artifacts | true
	mkdir -p artifacts/pkg/usr/local/sbin/
	$(CC) rebootp.c -o artifacts/rebootp
	

package:
	cd artifacts; cp rebootp pkg/usr/local/sbin/rebootp
	cd artifacts; mksquashfs pkg rebootp.tcz
	cd artifacts/pkg; find usr -not -type d > ../rebootp.tcz.list

clean:
	rm -rf artifacts