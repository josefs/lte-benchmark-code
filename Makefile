################################################################################
#                       LTE UPLINK RECEIVER PHY BENCHMARK                      #
#                                                                              #
# This file is distributed under the license terms given by LICENSE.TXT        #
################################################################################
# Author: Magnus Sjalander                                                     #
################################################################################

define HELP_TEXT
clear
echo "Makefile for the LTE uplink reciever PHY benchmark"
echo "Version 1.0 - 2010-12-08"
echo "Author: Magnus Sjalander <hms@chalmers.se>"
echo "--------------------------------------------------------------------------------"
echo "all                Compiles the uplink benchmark for the Tilera architecture"
echo "clean              Calls clean_uplink"
echo "help               Prints the complete help text"
echo "cilk_install       Installs the Cilk runtime and tools"
echo "compile_linux      Compiles the Tilera Linux kernel"
echo ""
endef

ROOT       = ${CURDIR}
SAVE_DIR   = ${ROOT}/saved
EXECUTABLE = ${UPLINK}/uplink
LOG_DIR    = ${ROOT}/log
SCRIPT_DIR = ${ROOT}/lib/scripts

PDF_READER = xpdf

.PHONY: all
all: uplink

.PHONY: clean
clean: clean_uplink

###########################################################
#                UPLINK BENCHMARK TARGETS                 #
###########################################################
include ${ROOT}/uplink/Makefile

###########################################################
#                     GRAPH TARGETS                       #
###########################################################
-include ${ROOT}/lib/graph/Makefile

###########################################################
#                    SCRIPTS TARGETS                      #
###########################################################
-include ${ROOT}/lib/scripts/Makefile

###########################################################
#                     TILERA TARGETS                      #
###########################################################

define HELP_TEXT_TILERA
echo "RUN Make Targets"
echo "--------------------------------------------------------------------------------"
echo "run_pci            Compiles the benchmark and launch it on Tilera"
echo "run_sim            Compiles the benchmark and launch it in the simulator"
echo "run_x86            Compiles the benchmark and launch it on the local x86 machine"
echo "run_ff             Compiler the benchmark with the FastFlow runtime on x86"
echo "run_cilk           Compiles the benchmark with the Cilk runtime on x86"
echo "run_cilk_pci       Compiles the benchmark with the Cilk runtime on Tilera"
echo "profile            Executes the application on Tilera with oprofile enabled"
echo "profile_view       View the data collected during a \"make profile\" run"
echo "help_tilera        Prints the help text of this section"
echo ""
endef
.PHONY: help_tilera
help_tilera:
	@${HELP_TEXT_TILERA}

TILERA_ROOT   = /opt/tilepro/
BIN           = $(TILERA_ROOT)/bin/
TILE_MONITOR  = $(BIN)tile-monitor
TILE_OPREPORT = $(BIN)tile-opreport
TILE_MKBOOT   = $(BIN)tile-mkboot

LINUX_ROOT    = ${TILERA_ROOT}/src/sys/linux
LINUX_BUILD   = ${ROOT}/lib/linux-build

MONITOR_COMMON_ARGS = \
  --batch-mode \
  --mkdir /tmp/test \
  --cd /tmp/test \
  --upload $(EXECUTABLE) $(EXECUTABLE) \
  --hv-bin-dir $(TILERA_ROOT)/src/sys/hv/ \
  --vmlinux ${LINUX_BUILD}/vmlinux \
  -- $(EXECUTABLE)

# For timing-accurate execution, remove the "--functional" option.
SIMULATOR_ARGS = \
  --functional \
  --image 8x4

PCI_ARGS = \
  --pci \
  --hvc lib/hypervisor/minimal-drivers.hvc \
  --debug-on-crash \
  --tile 8x8

PROFILE_ARGS = \
  --upload $(EXECUTABLE) /bin/uplink \
  --profile-init \
  --profile-kernel \
  --profile-flags '--callgraph=20' \
  --profile-start \
  --run - uplink - \
  --profile-stop \
  --profile-capture samples \
  --profile-analyze samples \
  --quit

FILTER = sort

.PHONY: run_sim
run run_sim: $(EXECUTABLE) ${LINUX_BUILD}/vmlinux
	$(TILE_MONITOR) $(SIMULATOR_ARGS) $(MONITOR_COMMON_ARGS)

.PHONY: test_sim
test_sim: $(EXECUTABLE)
	set -e -o pipefail; \
	$(TILE_MONITOR) $(SIMULATOR_ARGS) $(MONITOR_COMMON_ARGS) | $(FILTER) > output.run; \
	cat output.txt | $(FILTER) | diff output.run -

.PHONY: run_pci
run_pci: $(EXECUTABLE) ${LINUX_BUILD}/vmlinux
	@$(TILE_MONITOR) $(PCI_ARGS) $(MONITOR_COMMON_ARGS)

.PHONY: test_pci
test_pci: $(EXECUTABLE)
	set -e -o pipefail; \
	$(TILE_MONITOR) $(PCI_ARGS) $(MONITOR_COMMON_ARGS) | $(FILTER) > output.run; \
	cat output.txt | $(FILTER) | diff output.run -

.PHONY: gdb_pci
gdb_pci:
	LD_LIBRARY_PATH=${TILERA_ROOT}/lib /opt/tilepro/bin/tile-gdb -q

###########################################################
#                      PROFILING                          #
###########################################################

.PHONY: profile
profile: $(EXECUTABLE)
	$(TILE_MONITOR) $(PCI_ARGS) $(PROFILE_ARGS)

.PHONY: profile_view
profile_view:
	$(TILE_OPREPORT) archive:samples --merge=all -l -p uplink/ uplink

###########################################################
#                     LINUX TILERA                        #
###########################################################

.PHONY: compile_linux
compile_linux: ${LINUX_BUILD}/vmlinux

${LINUX_BUILD}/Makefile:
	@mkdir -p ${LINUX_BUILD}
	@cd ${LINUX_BUILD} && TILERA_ROOT=${TILERA_ROOT} ${LINUX_ROOT}/tile-prepare

${LINUX_BUILD}/vmlinux: ${LINUX_BUILD}/Makefile ${EXECUTABLE}
	@make objdump_uplink | gawk -f ${ROOT}/lib/nap-irq/nap.awk > ${ROOT}/lib/nap-irq/nap-address.tmp
	@if test -f ${ROOT}/lib/nap-irq/nap-address.sed; then \
	if test -z "`diff ${ROOT}/lib/nap-irq/nap-address.tmp ${ROOT}/lib/nap-irq/nap-address.sed`"; then \
	rm ${ROOT}/lib/nap-irq/nap-address.tmp; \
	else \
	mv ${ROOT}/lib/nap-irq/nap-address.tmp ${ROOT}/lib/nap-irq/nap-address.sed; \
	sed -f ${ROOT}/lib/nap-irq/nap-address.sed ${ROOT}/lib/nap-irq/intvec_32.template > ${TILERA_ROOT}/src/sys/linux/arch/tile/kernel/intvec_32.S; \
	cd ${LINUX_BUILD} && TILERA_ROOT=${TILERA_ROOT} make; \
	fi; \
	else \
	mv ${ROOT}/lib/nap-irq/nap-address.tmp ${ROOT}/lib/nap-irq/nap-address.sed; \
	sed -f ${ROOT}/lib/nap-irq/nap-address.sed ${ROOT}/lib/nap-irq/intvec_32.template > ${TILERA_ROOT}/src/sys/linux/arch/tile/kernel/intvec_32.S; \
	cd ${LINUX_BUILD} && TILERA_ROOT=${TILERA_ROOT} make; \
	fi

###########################################################
#                          X86                            #
###########################################################

.PHONY: run_x86
run_x86:
	@make uplink x86=1
	@${EXECUTABLE}

.PHONY: run_serial
run_serial:
	@make uplink serial=1
	@${EXECUTABLE}

###########################################################
#                        FastFlow                         #
###########################################################

.PHONY: run_ff
run_ff:
	@make uplink ff=1
	@${EXECUTABLE}

###########################################################
#                         CILK                            #
###########################################################

CILK_ROOT       = ${ROOT}/lib/cilk
CILK_BUILD      = ${ROOT}/lib/cilk-build

CILK_TILE       = ${ROOT}/lib/cilk-tile
CILK_TILE_BUILD = ${ROOT}/lib/cilk-tile-build

ifndef NPROC
NPROC = 2
endif

.PHONY: run_cilk
run_cilk: ${CILK_ROOT}/bin/cilkc
	@make uplink cilk=1
	@${EXECUTABLE} --nproc ${NPROC}

.PHONY: run_cilk_pci
run_cilk_pci: ${CILK_ROOT}/bin/cilkc ${CILK_TILE}/bin/cilkc $(EXECUTABLE) ${LINUX_BUILD}/vmlinux
	@make uplink cilk_pci=1
	$(TILE_MONITOR) $(PCI_ARGS) $(MONITOR_COMMON_ARGS) --nproc 63

.PHONY: cilk_install
cilk_install: ${CILK_ROOT}/bin/cilkc ${CILK_TILE}/bin/cilkc

${CILK_BUILD}/Makefile:
	@wget http://supertech.csail.mit.edu/cilk/cilk-5.4.6.tar.gz
	@tar xvf cilk-5.4.6.tar.gz
	@mv cilk-5.4.6 ${CILK_BUILD}
	@rm cilk-5.4.6.tar.gz

${CILK_ROOT}/bin/cilkc: ${CILK_BUILD}/Makefile
	@-cd ${CILK_BUILD} && \
	./configure --prefix=${CILK_ROOT} CFLAGS="-D_XOPEN_SOURCE=600 -D_POSIX_C_SOURCE=200809L" && \
	make; \
	make install

${CILK_TILE_BUILD}/Makefile:
	@wget http://supertech.csail.mit.edu/cilk/cilk-5.4.6.tar.gz
	@tar xvf cilk-5.4.6.tar.gz
	@mv cilk-5.4.6 ${CILK_TILE_BUILD}
	@rm cilk-5.4.6.tar.gz

${CILK_TILE}/bin/cilkc: ${CILK_TILE_BUILD}/Makefile
	@cp ${ROOT}/lib/cilk-sysdep.h.in ${CILK_TILE_BUILD}/runtime
	@-cd ${CILK_TILE_BUILD} && \
	CC=/opt/tilepro/bin/tile-cc ./configure --prefix=${CILK_TILE} --host=x86_64 && \
	make; \
	make install

###########################################################
#                      HELP TARGET                        #
###########################################################

.PHONY: help
help:
	@${HELP_TEXT}
	@${HELP_TEXT_UPLINK}
	@${HELP_TEXT_TILERA}
	@${HELP_TEXT_NI}
	@${HELP_TEXT_GRAPH}
