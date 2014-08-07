#
# Makefile for scsi_transport_srp.ko and ib_srp.ko.
#

ifeq ($(KVER),)
  ifeq ($(KDIR),)
    KVER = $(shell uname -r)
    KDIR ?= /lib/modules/$(KVER)/build
  else
    KVER = $$KERNELRELEASE
  endif
else
  KDIR ?= /lib/modules/$(KVER)/build
endif

VERSION := $(shell sed -n 's/Version:[[:blank:]]*//p' ib_srp-backport.spec)

# The file Modules.symvers has been renamed in the 2.6.18 kernel to
# Module.symvers. Find out which name to use by looking in $(KDIR).
MODULE_SYMVERS:=$(shell if [ -e $(KDIR)/Module.symvers ]; then \
		       echo Module.symvers; else echo Modules.symvers; fi)

# Name of the OFED kernel RPM.
OFED_KERNEL_IB_RPM:=$(shell for r in kernel-ib mlnx-ofa_kernel compat-rdma; do rpm -q $$r 2>/dev/null | grep -q "^$$r" && echo $$r && break; done)

# Name of the OFED kernel development RPM.
OFED_KERNEL_IB_DEVEL_RPM:=$(shell for r in kernel-ib-devel mlnx-ofa_kernel-devel compat-rdma-devel; do rpm -q $$r 2>/dev/null | grep -q "^$$r" && echo $$r && break; done)

OFED_FLAVOR=$(shell /usr/bin/ofed_info 2>/dev/null | head -n1 | sed -n 's/^MLNX_OFED.*/MOFED/p;s/^OFED-.*/OFED/p')

ifneq ($(OFED_KERNEL_IB_RPM),)
ifeq ($(OFED_KERNEL_IB_RPM),compat-rdma)
# OFED 3.x
OFED_KERNEL_DIR:=/usr/src/compat-rdma
OFED_CFLAGS:=-I$(OFED_KERNEL_DIR)/include
else
OFED_KERNEL_DIR:=/usr/src/ofa_kernel
ifeq ($(OFED_FLAVOR),MOFED)
# Mellanox OFED with or without kernel-ib RPM
OFED_CFLAGS:=-I$(OFED_KERNEL_DIR)/include
else
# OFED 1.5
include $(OFED_KERNEL_DIR)/config.mk
OFED_CFLAGS:=$(BACKPORT_INCLUDES) -I$(OFED_KERNEL_DIR)/include
endif
endif
# Any OFED version
OFED_MODULE_SYMVERS:=$(OFED_KERNEL_DIR)/Module.symvers
endif

INSTALL_MOD_DIR ?= extra

all: check
	CONFIG_SCSI_SRP_ATTRS=m						   \
		$(MAKE) -C $(KDIR) M=$(shell pwd)/drivers/scsi		   \
		PRE_CFLAGS="$(OFED_CFLAGS)" modules
	@m="$(shell pwd)/drivers/infiniband/ulp/srp/$(MODULE_SYMVERS)";	   \
	cat <"$(KDIR)/$(MODULE_SYMVERS)" >"$$m";			   \
	cat "$(shell pwd)/drivers/scsi/$(MODULE_SYMVERS)"		   \
		$(OFED_MODULE_SYMVERS) |				   \
	while read line; do						   \
	    set -- $$line;						   \
	    csum="$$1";							   \
	    sym="$$2";							   \
	    if ! grep -q "^$$csum[[:blank:]]*$$sym[[:blank:]]" "$$m"; then \
		sed -i.tmp -e "/^[\w]*[[:blank:]]*$$sym[[:blank:]]/d" "$$m"; \
		echo "$$line" >>"$$m";					   \
	    fi								   \
	done
	CONFIG_SCSI_SRP_ATTRS=m CONFIG_SCSI_SRP=m CONFIG_INFINIBAND_SRP=m  \
	$(MAKE) -C $(KDIR) M=$(shell pwd)/drivers/infiniband/ulp/srp	   \
	    PRE_CFLAGS="$(OFED_CFLAGS)" modules

install: all
	for m in drivers/scsi/scsi_transport_srp.ko			   \
	  drivers/infiniband/ulp/srp/ib_srp.ko; do		   	   \
	  install -vD -m 644 $$m					   \
	    $(INSTALL_MOD_PATH)/lib/modules/$(KVER)/$(INSTALL_MOD_DIR)/$$(basename $$m); \
	done
	if [ -z "$(INSTALL_MOD_PATH)" ]; then	\
	  /sbin/depmod -a $(KVER);			\
	fi

uninstall:
	for m in scsi_transport_srp.ko ib_srp.ko; do			       \
	  rm -f $(INSTALL_MOD_PATH)/lib/modules/$(KVER)/$(INSTALL_MOD_DIR)/$$m;\
	done
	if [ -z "$(INSTALL_MOD_PATH)" ]; then	\
	  /sbin/depmod -a $(KVER);			\
	fi

check:
	@if [ -n "$(OFED_KERNEL_IB_RPM)" ]; then                            \
	  if [ -z "$(OFED_KERNEL_IB_DEVEL_RPM)" ]; then                     \
	    echo "Error: the OFED package $(OFED_KERNEL_IB_RPM)-devel has"  \
	         "not yet been installed.";                                 \
	    false;                                                          \
	  elif [ -e /lib/modules/$(KVER)/kernel/drivers/infiniband ]; then  \
	    echo "Error: the distro-provided InfiniBand kernel drivers"     \
	         "must be removed first"                                    \
	         " (/lib/modules/$(KVER)/kernel/drivers/infiniband).";      \
	    false;                                                          \
	  elif [ -e /lib/modules/$(KVER)/updates/drivers/infiniband/ulp/srp/ib_srp.ko ]; then \
	    echo "Error: the OFED SRP initiator must be removed first"      \
	         "(/lib/modules/$(KVER)/updates/drivers/infiniband/ulp/srp/ib_srp.ko).";    \
	    false;                                                          \
	  elif [ -e $(KDIR)/scripts/Makefile.lib ]                          \
	       && ! grep -wq '^c_flags .*PRE_CFLAGS'                        \
	          $(KDIR)/scripts/Makefile.lib                              \
	       && ! grep -wq '^LINUXINCLUDE .*PRE_CFLAGS'                   \
	          $(KDIR)/Makefile; then                                    \
	    echo "Error: the kernel build system has not yet been patched.";\
	    false;                                                          \
	  else                                                              \
	    echo "  Building against $(OFED_FLAVOR) $(OFED_KERNEL_IB_RPM)"  \
	         "InfiniBand kernel headers.";                              \
	  fi                                                                \
	else                                                                \
	  if [ -n "$(OFED_KERNEL_IB_DEVEL_RPM)" ]; then                     \
	    echo "Error: the OFED kernel package has not yet been"          \
	         "installed.";                                              \
	    false;                                                          \
	  else                                                              \
	    echo "  Building against in-tree InfiniBand kernel headers.";   \
	  fi;                                                               \
	fi

sources: dist-gzip

dist-gzip:
	mkdir ib_srp-backport-$(VERSION) &&		\
	{ git ls-tree --name-only -r HEAD	|	\
	  tar -T- -cf- |				\
	  tar -C ib_srp-backport-$(VERSION) -xf-; } &&	\
	rm -f ib_srp-backport-$(VERSION).tar.bz2 &&	\
	tar -cjf ib_srp-backport-$(VERSION).tar.bz2	\
		ib_srp-backport-$(VERSION) &&		\
	rm -rf ib_srp-backport-$(VERSION)

# Build an RPM either for the running kernel or for kernel version $KVER.
rpm:
	name=ib_srp-backport &&						 \
	rpmtopdir="$$(if [ $$(id -u) = 0 ]; then echo /usr/src/packages; \
		      else echo $$PWD/rpmbuilddir; fi)" &&		 \
	$(MAKE) dist-gzip &&						 \
	rm -rf $${rpmtopdir} &&						 \
	for d in BUILD RPMS SOURCES SPECS SRPMS; do			 \
	  mkdir -p $${rpmtopdir}/$$d;					 \
	done &&								 \
	cp $${name}-$(VERSION).tar.bz2 $${rpmtopdir}/SOURCES &&		 \
	rpmbuild --define="%_topdir $${rpmtopdir}"			 \
		 -ba $${name}.spec &&					 \
	rm -f ib_srp-backport-$(VERSION).tar.bz2

clean:
	$(MAKE) -C $(KDIR) M=$(shell pwd)/drivers/scsi clean
	$(MAKE) -C $(KDIR) M=$(shell pwd)/drivers/infiniband/ulp/srp clean
	rm -f Modules.symvers Module.symvers Module.markers modules.order

extraclean: clean
	rm -f *.orig *.rej

.PHONY: all check clean dist-gzip extraclean install rpm sources
