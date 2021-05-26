###############################################################################
#
# Copyright 2021 OpenHW Group
#
# Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://solderpad.org/licenses/
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.0
#
###############################################################################
#
# VIVADO-specific Makefile for the CV32E40P "uvmt_cv32" testbench.
# Vivado is the Xilinx SystemVerilog simulator.
#
###############################################################################

VIVADO_HOME              ?= /tools/Xilinx/Vivado/2020.2/bin
VIVADO_CMP               ?= $(VIVADO_HOME)/xvlog

#VIVADO_CMP_FLAGS         ?= $(SV_CMP_FLAGS)
#VIVADO_CMP_FLAGS         ?= -sv --define CV32E40P_ASSERT_ON
VIVADO_CMP_FLAGS         ?= --incr -sv

VIVADO_CFG_COMPILE_FLAGS ?= --define NO_PULP
VIVADO_UVM_ARGS          ?= -L uvm
VIVADO_RESULTS           ?= $(if $(CV_RESULTS),$(CV_RESULTS)/vivado_results,$(MAKE_PATH)/vivado_results)
VIVADO_COREVDV_RESULTS   ?= $(VIVADO_RESULTS)/corev-dv
VIVADO_WORK              ?= $(VIVADO_RESULTS)/$(CFG)/vivado_work
VIVADO_IMAGE             ?= vivado.out
VIVADO_RUN_FLAGS         ?=
VIVADO_CODE_COV_SCOPE    ?= $(MAKE_PATH)/../tools/vivado/ccov_scopes.txt
VIVADO_USE_ISS           ?= YES

VIVADO_FILE_LIST ?= -f $(DV_UVMT_PATH)/uvmt_$(CV_CORE_LC).flist
VIVADO_FILE_LIST         += -f $(DV_UVMT_PATH)/imperas_iss.flist
VIVADO_USER_COMPILE_ARGS += --define $(CV_CORE_UC)_TRACE_EXECUTION
ifeq ($(USE_ISS),YES)
	VIVADO_RUN_FLAGS     += +USE_ISS
endif

# Seed management for constrained-random sims. For the DSIM Makefile (dsim.mk),
# this is an intentional repeat of the root Makefile because dsim regressions
# use random seeds by default.  TODO: determine how VIVADO manages seeds and
# update accordingly.
VIVADO_SEED    ?= random
VIVADO_RNDSEED ?= 

ifeq ($(VIVADO_SEED),random)
_RNDSEED = $(shell date +%N)
else
ifeq ($(VIVADO_SEED),)
# Empty VIVADO_SEED variable selects a random value
_RNDSEED = 1
else
_RNDSEED = $(VIVADO_SEED)
endif
endif

VIVADO_RUN_FLAGS         += $(USER_RUN_FLAGS)
VIVADO_RUN_FLAGS         += -sv_seed $(VIVADO_RNDSEED)

# Variables to control wave dumping from command the line
# Humans _always_ forget the "S", so you can have it both ways...
WAVES                  ?= 0
WAVE                   ?= 0
DUMP_WAVES             := 0
# Code Coverage collected by default
CCOV                   ?= 1

ifneq ($(WAVES), 0)
DUMP_WAVES = 1
endif

ifneq ($(WAVE), 0)
DUMP_WAVES = 1
endif

ifneq ($(DUMP_WAVES), 0)
VIVADO_ACC_FLAGS ?= +acc
VIVADO_DMP_FILE  ?= vivado.vcd
VIVADO_DMP_FLAGS ?= -waves $(VIVADO_DMP_FILE)
endif

ifneq ($(CCOV), 0)
	_USER_COMPILE_ARGS += -code-cov block -code-cov-scope-specs $(VIVADO_CODE_COV_SCOPE)
	_RUN_FLAGS         += -code-cov block -code-cov-scope-specs $(VIVADO_CODE_COV_SCOPE)
endif

.PHONY: sim
		+elf_file=$(CUSTOM)/$(TYPE1_TEST_PROGRAM).elf

no_rule:
	@echo 'makefile: SIMULATOR is set to $(SIMULATOR), but no rule/target specified.'
	@echo 'try "make SIMULATOR=vivado sanity" (or just "make sanity" if shell ENV variable SIMULATOR is already set).'

all: clean_all hello-world

# This special target is to support the special sanity target in the Common Makefile
hello-world:
	$(MAKE) test TEST=hello-world

help:
	@echo 'try "make SIMULATOR=vivado sanity" (or just "make sanity" if shell ENV variable SIMULATOR is already set).'
	vivado -help

mk_results: 
	$(MKDIR_P) $(VIVADO_RESULTS)
	$(MKDIR_P) $(VIVADO_WORK)

################################################################################
# VIVADO compile target
comp: mk_results $(CV_CORE_PKG) $(OVP_MODEL_DPI)
	$(VIVADO_CMP) \
		$(VIVADO_CMP_FLAGS) \
		$(VIVADO_UVM_ARGS) \
		$(VIVADO_ACC_FLAGS) \
		$(VIVADO_CFG_COMPILE_FLAGS) \
		$(VIVADO_USER_COMPILE_ARGS) \
		--include $(DV_UVME_PATH) \
		--include $(DV_UVMT_PATH) \
		-f $(CV_CORE_MANIFEST) \
		$(VIVADO_FILE_LIST) \
		-work $(VIVADO_WORK)
#		+$(UVM_PLUSARGS)
#		-genimage $(VIVADO_IMAGE)


################################################################################
# Running custom test-programs':
#   The "custom" target provides the ability to specify both the testcase run by
#   the UVM environment and a C or assembly test-program to be executed by the
#   core. Note that the UVM testcase is required to load the compiled program
#   into the core's memory.
#
# User defined variables used by this target:
#   CUSTOM_DIR:   Absolute, not relative, path to the custom C program. Default
#                 is `pwd`/../../tests/core/custom.
#   CUSTOM_PROG:  C or assembler test-program that executes on the core. Default
#                 is hello-world.c.
#   UVM_TESTNAME: Class identifer (not file path) of the UVM testcase run by
#                 environment. Default is uvmt_cv32_firmware_test_c.
#
# Use cases:
#   1: Full specification of the hello-world test:
#      $ make custom SIMULATOR=vivado CUSTOM_DIR=`pwd`/../../tests/core/custom CUSTOM_PROG=hello-world UVM_TESTNAME=uvmt_cv32_firmware_test_c
#
#   2: Same thing, using the defaults in these Makefiles:
#      $ make custom
#
#   3: Run ../../tests/core/custom/fibonacci.c
#      $ make custom CUSTOM_PROG=fibonacci
#
#   4: Run your own "custom program" located in ../../tests/core/custom
#      $ make custom CUSTOM_PROG=<my_custom_test_program>
#
custom: comp $(CUSTOM_DIR)/$(CUSTOM_PROG).hex $(CUSTOM_DIR)/$(CUSTOM_PROG).elf 
	mkdir -p $(VIVADO_RESULTS)/$(CFG)/$(CUSTOM_PROG)_$(RUN_INDEX) && cd $(VIVADO_RESULTS)/$(CFG)/$(CUSTOM_PROG)_$(RUN_INDEX)  && \
	$(VIVADO) -l vivado-$(CUSTOM_PROG).log -image $(VIVADO_IMAGE) \
		-work $(VIVADO_WORK) $(VIVADO_RUN_FLAGS) $(VIVADO_DMP_FLAGS) \
		-sv_lib $(UVM_HOME)/src/dpi/libuvm_dpi.so \
		-sv_lib $(DPI_DASM_LIB) \
		-sv_lib $(OVP_MODEL_DPI) \
		+UVM_TESTNAME=$(UVM_TESTNAME) \
		+firmware=$(CUSTOM_DIR)/$(CUSTOM_PROG).hex \
		+elf_file=$(CUSTOM_DIR)/$(CUSTOM_PROG).elf

################################################################################
# General test execution target "test"
# 

################################################################################
# If the configuration specified OVPSIM arguments, generate an ovpsim.ic file and
# set IMPERAS_TOOLS to point to it
gen_ovpsim_ic:
	@if [ ! -z "$(CFG_OVPSIM)" ]; then \
		mkdir -p $(VIVADO_RESULTS)/$(CFG)/$(TEST_NAME)_$(RUN_INDEX); \
		echo "$(CFG_OVPSIM)" > $(VIVADO_RESULTS)/$(CFG)/$(TEST_NAME)_$(RUN_INDEX)/ovpsim.ic; \
	fi
ifneq ($(CFG_OVPSIM),)
export IMPERAS_TOOLS=$(VIVADO_RESULTS)/$(CFG)/$(TEST_NAME)_$(RUN_INDEX)/ovpsim.ic
endif

# Skip compile if COMP is specified and negative
ifneq ($(call IS_NO,$(COMP)),NO)
VIVADO_SIM_PREREQ = comp
endif

# Corev-dv needs an optional run index suffix
ifeq ($(shell echo $(TEST) | head -c 6),corev_)
	OPT_RUN_INDEX_SUFFIX=_$(RUN_INDEX)
endif

test: $(VIVADO_SIM_PREREQ) $(TEST_TEST_DIR)/$(TEST_PROGRAM)$(OPT_RUN_INDEX_SUFFIX).hex gen_ovpsim_ic
	mkdir -p $(VIVADO_RESULTS)/$(CFG)/$(TEST_NAME)_$(RUN_INDEX) && \
	cd $(VIVADO_RESULTS)/$(CFG)/$(TEST_NAME)_$(RUN_INDEX) && \
		$(VIVADO) \
			-l vivado-$(TEST_NAME).log \
			-image $(VIVADO_IMAGE) \
			-work $(VIVADO_WORK) \
			$(VIVADO_RUN_FLAGS) \
			$(VIVADO_DMP_FLAGS) \
			$(TEST_PLUSARGS) \
			-sv_lib $(UVM_HOME)/src/dpi/libuvm_dpi.so \
			-sv_lib $(DPI_DASM_LIB) \
			-sv_lib $(OVP_MODEL_DPI) \
			+UVM_TESTNAME=$(TEST_UVM_TEST) \
			+firmware=$(TEST_TEST_DIR)/$(TEST_PROGRAM)$(OPT_RUN_INDEX_SUFFIX).hex \
			+elf_file=$(TEST_TEST_DIR)/$(TEST_PROGRAM)$(OPT_RUN_INDEX_SUFFIX).elf

# Similar to above, but for the ASM directory.
asm: comp $(ASM_DIR)/$(ASM_PROG).hex $(ASM_DIR)/$(ASM_PROG).elf
	mkdir -p $(VIVADO_RESULTS)/$(CFG)/$(ASM_PROG)_$(RUN_INDEX) && cd $(VIVADO_RESULTS)/$(CFG)/$(ASM_PROG)_$(RUN_INDEX)  && \
	$(VIVADO) -l vivado-$(ASM_PROG).log -image $(VIVADO_IMAGE) \
		-work $(VIVADO_WORK) $(VIVADO_RUN_FLAGS) $(VIVADO_DMP_FLAGS) \
		-sv_lib $(UVM_HOME)/src/dpi/libuvm_dpi.so \
		-sv_lib $(DPI_DASM_LIB) \
		-sv_lib $(OVP_MODEL_DPI) \
		+UVM_TESTNAME=$(UVM_TESTNAME) \
		+firmware=$(ASM_DIR)/$(ASM_PROG).hex \
		+elf_file=$(ASM_DIR)/$(ASM_PROG).elf

###############################################################################
# Run a single test-program from the RISC-V Compliance Test-suite. The parent
# Makefile of this <sim>.mk implements "all_compliance", the target that
# compiles the test-programs.
#
# There is a dependancy between RISCV_ISA and COMPLIANCE_PROG which *you* are
# required to know.  For example, the I-ADD-01 test-program is part of the rv32i
# testsuite.
# So this works:
#                make compliance RISCV_ISA=rv32i COMPLIANCE_PROG=I-ADD-01
# But this does not:
#                make compliance RISCV_ISA=rv32imc COMPLIANCE_PROG=I-ADD-01
# 
RISCV_ISA       ?= rv32i
COMPLIANCE_PROG ?= I-ADD-01

SIG_ROOT      ?= $(VIVADO_RESULTS)/$(CFG)/$(RISCV_ISA)
SIG           ?= $(VIVADO_RESULTS)/$(CFG)/$(RISCV_ISA)/$(COMPLIANCE_PROG)_$(RUN_INDEX)/$(COMPLIANCE_PROG).signature_output
REF           ?= $(COMPLIANCE_PKG)/riscv-test-suite/$(RISCV_ISA)/references/$(COMPLIANCE_PROG).reference_output
TEST_PLUSARGS ?= +signature=$(COMPLIANCE_PROG).signature_output

compliance: comp build_compliance
	mkdir -p $(VIVADO_RESULTS)/$(CFG)/$(RISCV_ISA)/$(COMPLIANCE_PROG)_$(RUN_INDEX) && cd $(VIVADO_RESULTS)/$(CFG)/$(RISCV_ISA)/$(COMPLIANCE_PROG)_$(RUN_INDEX)  && \
	export IMPERAS_TOOLS=$(CORE_V_VERIF)/$(CV_CORE_LC)/tests/cfg/ovpsim_no_pulp.ic && \
	$(VIVADO) -l vivado-$(COMPLIANCE_PROG).log -image $(VIVADO_IMAGE) \
		-work $(VIVADO_WORK) $(VIVADO_RUN_FLAGS) $(VIVADO_DMP_FLAGS) $(TEST_PLUSARGS) \
		-sv_lib $(UVM_HOME)/src/dpi/libuvm_dpi.so \
		-sv_lib $(DPI_DASM_LIB) \
		-sv_lib $(OVP_MODEL_DPI) \
		+UVM_TESTNAME=$(UVM_TESTNAME) \
		+firmware=$(COMPLIANCE_PKG)/work/$(RISCV_ISA)/$(COMPLIANCE_PROG).hex \
		+elf_file=$(COMPLIANCE_PKG)/work/$(RISCV_ISA)/$(COMPLIANCE_PROG).elf

################################################################################
# Commonly used targets:
#      Here for historical reasons - mostly (completely?) superceeded by the
#      custom target.
#

# Mythical no-test-program testcase.  Might never be used.  Not known tow work
no-test-program: comp
	mkdir -p $(VIVADO_RESULTS)/$(CFG)/hello-world_$(RUN_INDEX) && cd $(VIVADO_RESULTS)/$(CFG)/hello-world_$(RUN_INDEX)  && \
	$(VIVADO) -l vivado-$(UVM_TESTNAME).log -image $(VIVADO_IMAGE) \
		-work $(VIVADO_WORK) $(VIVADO_RUN_FLAGS) $(VIVADO_DMP_FLAGS) \
		-sv_lib $(UVM_HOME)/src/dpi/libuvm_dpi.so \
		-sv_lib $(DPI_DASM_LIB) \
		-sv_lib $(OVP_MODEL_DPI) \
		+UVM_TESTNAME=$(UVM_TESTNAME)
#		+firmware=$(CUSTOM_DIR)/$(CUSTOM_PROG).hex \
#		+elf_file=$(CUSTOM_DIR)/$(CUSTOM_PROG).elf


################################################################################
# VIVADO UNIT TESTS: run each test individually.
#                  Example: to run the ADDI test `make vivado-unit-test addi`
# DO NOT INVOKE rule "vivado-firmware-unit-test" directly.   It is a support
# rule for rule "vivado-unit-test" (in included ../Firmware.mk).
vivado-firmware-unit-test: comp
	mkdir -p $(VIVADO_RESULTS)/firmware_$(RUN_INDEX) && cd $(VIVADO_RESULTS)/firmware_$(RUN_INDEX) && \
	$(VIVADO) -l vivado-$(UNIT_TEST).log -image $(VIVADO_IMAGE) \
		-work $(VIVADO_WORK) $(VIVADO_RUN_FLAGS) $(VIVADO_DMP_FLAGS) \
		-sv_lib $(UVM_HOME)/src/dpi/libuvm_dpi.so \
		-sv_lib $(DPI_DASM_LIB) \
		-sv_lib $(OVP_MODEL_DPI) \
		+UVM_TESTNAME=uvmt_$(CV_CORE_LC)_firmware_test_c \
		+firmware=$(FIRMWARE)/firmware_unit_test.hex \
		+elf_file=$(FIRMWARE)/firmware_unit_test.elf

# Aliases for 'vivado-unit-test' (defined in ../Common.mk)
.PHONY: unit-test
unit-test: vivado-unit-test

###############################################################################
# Use Google instruction stream generator (RISCV-DV) to create new test-programs
#riscv-dv: clone_riscv-dv
comp_corev-dv:
	# FIXME:strichmo:Please remove this!
	mkdir -p $(COREVDV_PKG)/out_$(DATE)/vivado
	mkdir -p $(VIVADO_COREVDV_RESULTS)
	vivado -sv \
		-work $(VIVADO_COREVDV_RESULTS)/vivado \
		+incdir+$(UVM_HOME)/src \
		$(UVM_HOME)/src/uvm_pkg.sv \
		--define VIVADO \
		-suppress EnumMustBePositive \
		-suppress SliceOOB \
		+incdir+$(CV_CORE_COREVDV_PKG)/target/$(CV_CORE_LC) \
		+incdir+$(RISCVDV_PKG)/user_extension \
		+incdir+$(COREVDV_PKG) \
		+incdir+$(CV_CORE_COREVDV_PKG) \
		-f $(COREVDV_PKG)/manifest.f \
		-l $(VIVADO_COREVDV_RESULTS)/compile.log

#riscv-test: riscv-dv
#		+asm_file_name=$(RISCVDV_PKG)/out_2020-06-24/asm_tests/riscv_arithmetic_basic_test  \

gen_corev-dv: 
	mkdir -p $(VIVADO_COREVDV_RESULTS)/$(TEST)
	# Clean old assembler generated tests in results
	idx=$(GEN_START_INDEX); sum=$$(($(GEN_START_INDEX) + $(GEN_NUM_TESTS))); \
	while [ $$idx -lt $${sum} ]; do \
		rm -f ${VIVADO_COREVDV_RESULTS}/${TEST}/${TEST}_$$idx.S; \
		echo "idx = $$idx"; \
		idx=$$((idx + 1)); \
	done
	cd  $(VIVADO_COREVDV_RESULTS)/$(TEST) && \
	vivado  -sv_seed $(VIVADO_RNDSEED) \
		-sv_lib $(UVM_HOME)/src/dpi/libuvm_dpi.so \
		+acc+rwb \
		-image image \
		-work $(VIVADO_COREVDV_RESULTS)/vivado \
	 	+UVM_TESTNAME=$(GEN_UVM_TEST) \
		+num_of_tests=$(GEN_NUM_TESTS) \
		+start_idx=$(GEN_START_INDEX)  \
		+asm_file_name_opts=$(TEST) \
		-l $(TEST)_$(GEN_START_INDEX)_$(GEN_NUM_TESTS).log \
		$(GEN_PLUSARGS)
	# Copy out final assembler files to test directory
	idx=$(GEN_START_INDEX); sum=$$(($(GEN_START_INDEX) + $(GEN_NUM_TESTS))); \
	while [ $$idx -lt $${sum} ]; do \
		cp ${VIVADO_COREVDV_RESULTS}/${TEST}/${TEST}_$$idx.S ${GEN_TEST_DIR}; \
		idx=$$((idx + 1)); \
	done

corev-dv: clean_riscv-dv \
	  clone_riscv-dv \
	  comp_corev-dv

###############################################################################
# Clean up your mess!

clean:
	rm -f $(VIVADO_IMAGE)
	rm -rf $(VIVADO_RESULTS)

# All generated files plus the clone of the RTL
clean_all: clean clean_riscv-dv clean_test_programs clean-bsp clean_compliance clean_embench clean_dpi_dasm_spike
	rm -rf $(CV_CORE_PKG)

