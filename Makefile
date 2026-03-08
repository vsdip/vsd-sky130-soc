# SPDX-FileCopyrightText: 2020 Efabless Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0
MAKEFLAGS+=--warn-undefined-variables

export CARAVEL_ROOT?=$(PWD)/caravel
export UPRJ_ROOT?=$(PWD)
PRECHECK_ROOT?=${HOME}/mpw_precheck
export MCW_ROOT?=$(PWD)/mgmt_core_wrapper
SIM?=RTL

# Install lite version of caravel, (1): caravel-lite, (0): caravel
# Default to full caravel because integration targets (set_user_id/ship/final)
# require assets not present in caravel-lite.
CARAVEL_LITE?=0

# PDK switch varient
export PDK?=sky130A
#export PDK?=gf180mcuC
export PDKPATH?=$(PDK_ROOT)/$(PDK)

PYTHON_BIN ?= python3

ROOTLESS ?= 0
USER_ARGS = -u $$(id -u $$USER):$$(id -g $$USER)
ifeq ($(ROOTLESS), 1)
	USER_ARGS =
endif

# Keep cocotb docker platform optional for portability across host OS/arch.
# Users/CI can set COCOTB_DOCKER_PLATFORM explicitly when needed, e.g.:
#   COCOTB_DOCKER_PLATFORM=linux/amd64
# By default, docker decides the best available image/platform.
COCOTB_DOCKER_PLATFORM ?=
COCOTB_DOCKER_PLATFORM_ARG := $(if $(strip $(COCOTB_DOCKER_PLATFORM)),--platform=$(COCOTB_DOCKER_PLATFORM),)
COCOTB_DOCKER_PLATFORM_ENV := $(if $(strip $(COCOTB_DOCKER_PLATFORM)),DOCKER_DEFAULT_PLATFORM=$(COCOTB_DOCKER_PLATFORM),)
COCOTB_REQUIRE_RUNTIME ?= 1

export OPENLANE_ROOT?=$(PWD)/dependencies/openlane_src
export PDK_ROOT?=$(PWD)/dependencies/pdks
export DISABLE_LVS?=0

export ROOTLESS

ifeq ($(PDK),sky130A)
	SKYWATER_COMMIT=f70d8ca46961ff92719d8870a18a076370b85f6c
	export OPEN_PDKS_COMMIT_LVS?=6d4d11780c40b20ee63cc98e645307a9bf2b2ab8
	export OPEN_PDKS_COMMIT?=78b7bc32ddb4b6f14f76883c2e2dc5b5de9d1cbc
	export OPENLANE_TAG?=2023.07.19-1
	MPW_TAG ?= 2024.09.12-1

ifeq ($(CARAVEL_LITE),1)
	CARAVEL_NAME := caravel-lite
	CARAVEL_REPO := https://github.com/efabless/caravel-lite
	CARAVEL_TAG := $(MPW_TAG)
else
	CARAVEL_NAME := caravel
	CARAVEL_REPO := https://github.com/efabless/caravel
	CARAVEL_TAG := $(MPW_TAG)
endif

endif

ifeq ($(PDK),sky130B)
	SKYWATER_COMMIT=f70d8ca46961ff92719d8870a18a076370b85f6c
	export OPEN_PDKS_COMMIT_LVS?=6d4d11780c40b20ee63cc98e645307a9bf2b2ab8
	export OPEN_PDKS_COMMIT?=78b7bc32ddb4b6f14f76883c2e2dc5b5de9d1cbc
	export OPENLANE_TAG?=2023.07.19-1
	MPW_TAG ?= 2024.09.12-1

ifeq ($(CARAVEL_LITE),1)
	CARAVEL_NAME := caravel-lite
	CARAVEL_REPO := https://github.com/efabless/caravel-lite
	CARAVEL_TAG := $(MPW_TAG)
else
	CARAVEL_NAME := caravel
	CARAVEL_REPO := https://github.com/efabless/caravel
	CARAVEL_TAG := $(MPW_TAG)
endif

endif

ifeq ($(PDK),gf180mcuD)

	MPW_TAG ?= gfmpw-1c
	CARAVEL_NAME := caravel
	CARAVEL_REPO := https://github.com/efabless/caravel-gf180mcu
	CARAVEL_TAG := $(MPW_TAG)
	#OPENLANE_TAG=ddfeab57e3e8769ea3d40dda12be0460e09bb6d9
	export OPEN_PDKS_COMMIT?=78b7bc32ddb4b6f14f76883c2e2dc5b5de9d1cbc
	export OPENLANE_TAG?=2023.07.19

endif

# Include Caravel Makefile Targets
.PHONY: set_user_id
set_user_id: check-caravel
	@if [ -z "$(USER_ID)" ]; then \
		echo "USER_ID is undefined, please export it before running make set_user_id"; \
		exit 1; \
	fi
	@if [ -f "$(CARAVEL_ROOT)/mag/user_id_programming.mag" ] && [ -f "$(CARAVEL_ROOT)/mag/user_id_textblock.mag" ]; then \
		export CARAVEL_ROOT=$(CARAVEL_ROOT) && export MPW_TAG=$(MPW_TAG) && $(MAKE) -f $(CARAVEL_ROOT)/Makefile set_user_id; \
	else \
		echo "WARNING: Missing $(CARAVEL_ROOT)/mag/user_id_programming.mag or user_id_textblock.mag."; \
		if [ ! -d "$(CARAVEL_ROOT)/maglef" ]; then \
			echo "Detected caravel-lite checkout at $(CARAVEL_ROOT)."; \
			echo "For full integration flow (ship/fill/final), reinstall full caravel:"; \
			echo "  make uninstall && CARAVEL_LITE=0 make install"; \
		fi; \
		echo "Applying USER_ID to local RTL only (compatibility fallback)."; \
		mkdir -p ./signoff/build ./verilog/rtl ./verilog/gl; \
		cp $(CARAVEL_ROOT)/verilog/rtl/caravel_core.v ./verilog/rtl/caravel_core.v; \
		if [ -f "$(CARAVEL_ROOT)/verilog/gl/user_id_programming.v" ]; then \
			cp $(CARAVEL_ROOT)/verilog/gl/user_id_programming.v ./verilog/gl/user_id_programming.v; \
		fi; \
		sed -i -E "s/(parameter USER_PROJECT_ID = 32'h)[0-9A-F]+;/\\1$(USER_ID);/" ./verilog/rtl/caravel_core.v; \
		echo "Set user ID completed (RTL fallback)." | tee ./signoff/build/set_user_id.out; \
	fi

.PHONY: ship
ship: check-caravel
	@if [ ! -d "$(CARAVEL_ROOT)/maglef" ]; then \
		echo "ERROR: Detected caravel-lite checkout at $(CARAVEL_ROOT)."; \
		echo "This project's integration flow requires full caravel."; \
		echo "Fix: make uninstall && CARAVEL_LITE=0 make install"; \
		exit 1; \
	fi
	@if [ ! -f "$(UPRJ_ROOT)/mag/caravel_core.mag" ] && [ ! -f "$(UPRJ_ROOT)/mag/caravel_core.mag.gz" ]; then \
		mkdir -p "$(UPRJ_ROOT)/mag"; \
		if [ -f "$(CARAVEL_ROOT)/mag/caravel_core.mag" ]; then \
			cp "$(CARAVEL_ROOT)/mag/caravel_core.mag" "$(UPRJ_ROOT)/mag/caravel_core.mag"; \
		elif [ -f "$(CARAVEL_ROOT)/mag/caravel_core.mag.gz" ]; then \
			cp "$(CARAVEL_ROOT)/mag/caravel_core.mag.gz" "$(UPRJ_ROOT)/mag/caravel_core.mag.gz"; \
		fi; \
	fi
	@if { [ ! -f "$(CARAVEL_ROOT)/maglef/simple_por.mag" ] && [ ! -f "$(CARAVEL_ROOT)/maglef/simple_por.mag.gz" ]; } || \
	    { [ ! -f "$(CARAVEL_ROOT)/mag/caravel.mag" ] && [ ! -f "$(CARAVEL_ROOT)/mag/caravel.mag.gz" ]; } || \
	    { [ ! -f "$(UPRJ_ROOT)/mag/caravel_core.mag" ] && [ ! -f "$(UPRJ_ROOT)/mag/caravel_core.mag.gz" ]; }; then \
		echo "ERROR: Required MAG/MAGLEF sources for 'ship' are missing."; \
		echo "Missing one or more of: caravel/maglef/simple_por.mag, caravel/mag/caravel.mag, mag/caravel_core.mag."; \
		echo "If you are on caravel-lite, fix with: make uninstall && CARAVEL_LITE=0 make install"; \
		exit 1; \
	fi
	export CARAVEL_ROOT=$(CARAVEL_ROOT) && export MPW_TAG=$(MPW_TAG) && $(MAKE) -f $(CARAVEL_ROOT)/Makefile ship

.PHONY: final
final: check-caravel
	@if [ -z "$(USER_ID)" ]; then \
		echo "USER_ID is undefined, please export it before running make final"; \
		exit 1; \
	fi
	@if [ -z "$(PROJECT)" ]; then \
		echo "PROJECT is undefined, please export it before running make final"; \
		exit 1; \
	fi
	@echo "INFO: Running ship prerequisite for final..."
	@$(MAKE) ship
	@echo "INFO: Running generate_fill prerequisite for final..."
	@export CARAVEL_ROOT=$(CARAVEL_ROOT) && export MPW_TAG=$(MPW_TAG) && $(MAKE) -f $(CARAVEL_ROOT)/Makefile generate_fill
	@if [ ! -f "$(UPRJ_ROOT)/gds/$(PROJECT).gds" ] || [ "$$(stat -c%s "$(UPRJ_ROOT)/gds/$(PROJECT).gds" 2>/dev/null || echo 0)" -lt 1000000 ]; then \
		echo "ERROR: $(UPRJ_ROOT)/gds/$(PROJECT).gds missing/invalid after ship"; \
		exit 1; \
	fi
	@if [ ! -f "$(UPRJ_ROOT)/gds/caravel_$(USER_ID)_fill_pattern.gds" ] || [ "$$(stat -c%s "$(UPRJ_ROOT)/gds/caravel_$(USER_ID)_fill_pattern.gds" 2>/dev/null || echo 0)" -lt 1000000 ]; then \
		echo "ERROR: $(UPRJ_ROOT)/gds/caravel_$(USER_ID)_fill_pattern.gds missing/invalid after generate_fill"; \
		exit 1; \
	fi
	@rm -f "$(UPRJ_ROOT)/gds/caravel_$(USER_ID).gds"
	@cp -f "$(UPRJ_ROOT)/gds/$(PROJECT).gds" "$(CARAVEL_ROOT)/gds/$(PROJECT).gds"
	@cp -f "$(UPRJ_ROOT)/gds/caravel_$(USER_ID)_fill_pattern.gds" "$(CARAVEL_ROOT)/gds/caravel_$(USER_ID)_fill_pattern.gds"
	@export CARAVEL_ROOT=$(CARAVEL_ROOT) && \
		export MPW_TAG=$(MPW_TAG) && \
		export PDK=$(PDK) && \
		export PDK_ROOT=$(PDK_ROOT) && \
		export MCW_ROOT=$(MCW_ROOT) && \
		python3 $(UPRJ_ROOT)/scripts/compositor.py $(USER_ID) $(PROJECT) $(UPRJ_ROOT) $(CARAVEL_ROOT)/mag $(CARAVEL_ROOT)/gds -keep
	@cp -f "$(CARAVEL_ROOT)/gds/caravel_$(USER_ID).gds" "$(UPRJ_ROOT)/gds/caravel_$(USER_ID).gds"

.PHONY: final-fast
final-fast: check-caravel
	@if [ -z "$(USER_ID)" ]; then \
		echo "USER_ID is undefined, please export it before running make final-fast"; \
		exit 1; \
	fi
	@if [ -z "$(PROJECT)" ]; then \
		echo "PROJECT is undefined, please export it before running make final-fast"; \
		exit 1; \
	fi
	@if [ ! -f "$(UPRJ_ROOT)/gds/$(PROJECT).gds" ] || [ ! -f "$(UPRJ_ROOT)/gds/caravel_$(USER_ID)_fill_pattern.gds" ]; then \
		echo "ERROR: Missing prerequisites. Run: vsdmake ship && vsdmake fill"; \
		exit 1; \
	fi
	@cp -f "$(UPRJ_ROOT)/gds/$(PROJECT).gds" "$(CARAVEL_ROOT)/gds/$(PROJECT).gds"
	@cp -f "$(UPRJ_ROOT)/gds/caravel_$(USER_ID)_fill_pattern.gds" "$(CARAVEL_ROOT)/gds/caravel_$(USER_ID)_fill_pattern.gds"
	@rm -f "$(CARAVEL_ROOT)/gds/caravel_$(USER_ID).gds" "$(UPRJ_ROOT)/gds/caravel_$(USER_ID).gds"
	@export PDK=$(PDK) && \
		export PDK_ROOT=$(PDK_ROOT) && \
		export MCW_ROOT=$(MCW_ROOT) && \
		python3 $(UPRJ_ROOT)/scripts/compositor.py $(USER_ID) $(PROJECT) $(UPRJ_ROOT) $(CARAVEL_ROOT)/mag $(CARAVEL_ROOT)/gds -keep
	@if [ "$$(stat -c%s "$(CARAVEL_ROOT)/gds/caravel_$(USER_ID).gds" 2>/dev/null || echo 0)" -lt 1000000000 ]; then \
		echo "ERROR: final GDS is too small/invalid at $(CARAVEL_ROOT)/gds/caravel_$(USER_ID).gds"; \
		exit 1; \
	fi
	@cp -f "$(CARAVEL_ROOT)/gds/caravel_$(USER_ID).gds" "$(UPRJ_ROOT)/gds/caravel_$(USER_ID).gds"

.PHONY: % : check-caravel
%:
	export CARAVEL_ROOT=$(CARAVEL_ROOT) && export MPW_TAG=$(MPW_TAG) && $(MAKE) -f $(CARAVEL_ROOT)/Makefile $@

.PHONY: install
install:
	if [ -d "$(CARAVEL_ROOT)" ]; then\
		echo "Deleting exisiting $(CARAVEL_ROOT)" && \
		rm -rf $(CARAVEL_ROOT) && sleep 2;\
	fi
	echo "Installing $(CARAVEL_NAME).."
	git clone -b $(CARAVEL_TAG) $(CARAVEL_REPO) $(CARAVEL_ROOT) --depth=1

# Install DV setup
.PHONY: simenv
simenv:
	docker pull efabless/dv:latest

# Install cocotb docker
.PHONY: simenv-cocotb
simenv-cocotb:
	docker pull $(COCOTB_DOCKER_PLATFORM_ARG) efabless/dv:cocotb

.PHONY: setup
setup: check_dependencies install check-env install_mcw openlane pdk-with-volare setup-timing-scripts setup-cocotb precheck

# Openlane
blocks=$(shell cd openlane && find * -maxdepth 0 -type d)
.PHONY: $(blocks)
$(blocks): % :
	$(MAKE) -C openlane $*

dv_patterns=$(shell cd verilog/dv && find * -maxdepth 0 -type d)
cocotb-dv_patterns=$(shell cd verilog/dv/cocotb && find . -name "*.c"  | sed -e 's|^.*/||' -e 's/.c//')
dv-targets-rtl=$(dv_patterns:%=verify-%-rtl)
cocotb-dv-targets-rtl=$(cocotb-dv_patterns:%=cocotb-verify-%-rtl)
dv-targets-gl=$(dv_patterns:%=verify-%-gl)
cocotb-dv-targets-gl=$(cocotb-dv_patterns:%=cocotb-verify-%-gl)
dv-targets-gl-sdf=$(dv_patterns:%=verify-%-gl-sdf)

TARGET_PATH=$(shell pwd)
verify_command="source ~/.bashrc && cd ${TARGET_PATH}/verilog/dv/$* && export SIM=${SIM} && make"
dv_base_dependencies=simenv
docker_run_verify=\
	docker run \
		$(USER_ARGS) \
		-v ${TARGET_PATH}:${TARGET_PATH} -v ${PDK_ROOT}:${PDK_ROOT} \
		-v ${CARAVEL_ROOT}:${CARAVEL_ROOT} \
		-v ${MCW_ROOT}:${MCW_ROOT} \
		-e TARGET_PATH=${TARGET_PATH} -e PDK_ROOT=${PDK_ROOT} \
		-e CARAVEL_ROOT=${CARAVEL_ROOT} \
		-e TOOLS=/foss/tools/riscv-gnu-toolchain-rv32i/217e7f3debe424d61374d31e33a091a630535937 \
		-e DESIGNS=$(TARGET_PATH) \
		-e USER_PROJECT_VERILOG=$(TARGET_PATH)/verilog \
		-e PDK=$(PDK) \
		-e CORE_VERILOG_PATH=$(TARGET_PATH)/mgmt_core_wrapper/verilog \
		-e CARAVEL_VERILOG_PATH=$(TARGET_PATH)/caravel/verilog \
		-e MCW_ROOT=$(MCW_ROOT) \
		efabless/dv:latest \
		sh -c $(verify_command)

.PHONY: harden
harden: $(blocks)

.PHONY: verify
verify: $(dv-targets-rtl)

.PHONY: verify-all-rtl
verify-all-rtl: $(dv-targets-rtl)

.PHONY: verify-all-gl
verify-all-gl: $(dv-targets-gl)

.PHONY: verify-all-gl-sdf
verify-all-gl-sdf: $(dv-targets-gl-sdf)

$(dv-targets-rtl): SIM=RTL
$(dv-targets-rtl): verify-%-rtl: $(dv_base_dependencies)
	$(docker_run_verify)

$(dv-targets-gl): SIM=GL
$(dv-targets-gl): verify-%-gl: $(dv_base_dependencies)
	$(docker_run_verify)

$(dv-targets-gl-sdf): SIM=GL_SDF
$(dv-targets-gl-sdf): verify-%-gl-sdf: $(dv_base_dependencies)
	$(docker_run_verify)

clean-targets=$(blocks:%=clean-%)
.PHONY: $(clean-targets)
$(clean-targets): clean-% :
	rm -f ./verilog/gl/$*.v
	rm -f ./spef/$*.spef
	rm -f ./sdc/$*.sdc
	rm -f ./sdf/$*.sdf
	rm -f ./gds/$*.gds
	rm -f ./mag/$*.mag
	rm -f ./lef/$*.lef
	rm -f ./maglef/*.maglef

make_what=setup $(blocks) $(dv-targets-rtl) $(dv-targets-gl) $(dv-targets-gl-sdf) $(clean-targets)
.PHONY: what
what:
	# $(make_what)

# Install Openlane
.PHONY: openlane
openlane:
	@if [ "$$(realpath $${OPENLANE_ROOT})" = "$$(realpath $$(pwd)/openlane)" ]; then\
		echo "OPENLANE_ROOT is set to '$$(pwd)/openlane' which contains openlane config files"; \
		echo "Please set it to a different directory"; \
		exit 1; \
	fi
	cd openlane && $(MAKE) openlane

#### Not sure if the targets following are of any use

# Create symbolic links to caravel's main files
.PHONY: simlink
simlink: check-caravel
### Symbolic links relative path to $CARAVEL_ROOT
	$(eval MAKEFILE_PATH := $(shell realpath --relative-to=openlane $(CARAVEL_ROOT)/openlane/Makefile))
	$(eval PIN_CFG_PATH  := $(shell realpath --relative-to=openlane/user_project_wrapper $(CARAVEL_ROOT)/openlane/user_project_wrapper_empty/pin_order.cfg))
	mkdir -p openlane
	mkdir -p openlane/user_project_wrapper
	cd openlane &&\
	ln -sf $(MAKEFILE_PATH) Makefile
	cd openlane/user_project_wrapper &&\
	ln -sf $(PIN_CFG_PATH) pin_order.cfg

# Update Caravel
.PHONY: update_caravel
update_caravel: check-caravel
	cd $(CARAVEL_ROOT)/ && git checkout $(CARAVEL_TAG) && git pull

# Uninstall Caravel
.PHONY: uninstall
uninstall:
	rm -rf $(CARAVEL_ROOT)


# Install Pre-check
# Default installs to the user home directory, override by "export PRECHECK_ROOT=<precheck-installation-path>"
.PHONY: precheck
precheck:
	if [ -d "$(PRECHECK_ROOT)" ]; then\
		echo "Deleting exisiting $(PRECHECK_ROOT)" && \
		rm -rf $(PRECHECK_ROOT) && sleep 2;\
	fi
	@echo "Installing Precheck.."
	@git clone --depth=1 --branch $(MPW_TAG) https://github.com/efabless/mpw_precheck.git $(PRECHECK_ROOT)
	@docker pull efabless/mpw_precheck:latest

.PHONY: run-precheck
run-precheck: check-pdk check-precheck enable-lvs-pdk
	@if [ "$$DISABLE_LVS" = "1" ]; then\
		$(eval INPUT_DIRECTORY := $(shell pwd)) \
		cd $(PRECHECK_ROOT) && \
		docker run -it -v $(PRECHECK_ROOT):$(PRECHECK_ROOT) \
		-v $(INPUT_DIRECTORY):$(INPUT_DIRECTORY) \
		-v $(PDK_ROOT):$(PDK_ROOT) \
		-v $(HOME)/.ipm:$(HOME)/.ipm \
		-e INPUT_DIRECTORY=$(INPUT_DIRECTORY) \
		-e PDK_PATH=$(PDK_ROOT)/$(PDK) \
		-e PDK_ROOT=$(PDK_ROOT) \
		-e PDKPATH=$(PDKPATH) \
		-u $(shell id -u $(USER)):$(shell id -g $(USER)) \
		efabless/mpw_precheck:latest bash -c "cd $(PRECHECK_ROOT) ; python3 mpw_precheck.py --input_directory $(INPUT_DIRECTORY) --pdk_path $(PDK_ROOT)/$(PDK) license makefile default documentation consistency gpio_defines xor magic_drc klayout_feol klayout_beol klayout_offgrid klayout_met_min_ca_density klayout_pin_label_purposes_overlapping_drawing klayout_zeroarea"; \
	else \
		$(eval INPUT_DIRECTORY := $(shell pwd)) \
		cd $(PRECHECK_ROOT) && \
		docker run -it -v $(PRECHECK_ROOT):$(PRECHECK_ROOT) \
		-v $(INPUT_DIRECTORY):$(INPUT_DIRECTORY) \
		-v $(PDK_ROOT):$(PDK_ROOT) \
		-v $(HOME)/.ipm:$(HOME)/.ipm \
		-e INPUT_DIRECTORY=$(INPUT_DIRECTORY) \
		-e PDK_PATH=$(PDK_ROOT)/$(PDK) \
		-e PDK_ROOT=$(PDK_ROOT) \
		-e PDKPATH=$(PDKPATH) \
		-u $(shell id -u $(USER)):$(shell id -g $(USER)) \
		efabless/mpw_precheck:latest bash -c "cd $(PRECHECK_ROOT) ; python3 mpw_precheck.py --input_directory $(INPUT_DIRECTORY) --pdk_path $(PDK_ROOT)/$(PDK)"; \
	fi

.PHONY: enable-lvs-pdk
enable-lvs-pdk:
	$(UPRJ_ROOT)/venv/bin/volare enable $(OPEN_PDKS_COMMIT_LVS)

BLOCKS = $(shell cd lvs && find * -maxdepth 0 -type d)
LVS_BLOCKS = $(foreach block, $(BLOCKS), lvs-$(block))
$(LVS_BLOCKS): lvs-% : ./lvs/%/lvs_config.json check-pdk check-precheck
	@$(eval INPUT_DIRECTORY := $(shell pwd))
	@cd $(PRECHECK_ROOT) && \
	docker run -v $(PRECHECK_ROOT):$(PRECHECK_ROOT) \
	-v $(INPUT_DIRECTORY):$(INPUT_DIRECTORY) \
	-v $(PDK_ROOT):$(PDK_ROOT) \
	-u $(shell id -u $(USER)):$(shell id -g $(USER)) \
	efabless/mpw_precheck:latest bash -c "export PYTHONPATH=$(PRECHECK_ROOT) ; cd $(PRECHECK_ROOT) ; python3 checks/lvs_check/lvs.py --pdk_path $(PDK_ROOT)/$(PDK) --design_directory $(INPUT_DIRECTORY) --output_directory $(INPUT_DIRECTORY)/lvs --design_name $* --config_file $(INPUT_DIRECTORY)/lvs/$*/lvs_config.json"

.PHONY: clean
clean:
	cd ./verilog/dv/ && \
		$(MAKE) -j$(THREADS) clean

check-caravel:
	@if [ ! -d "$(CARAVEL_ROOT)" ]; then \
		echo "Caravel Root: "$(CARAVEL_ROOT)" doesn't exists, please export the correct path before running make. "; \
		exit 1; \
	fi

check-precheck:
	@if [ ! -d "$(PRECHECK_ROOT)" ]; then \
		echo "Pre-check Root: "$(PRECHECK_ROOT)" doesn't exists, please export the correct path before running make. "; \
		exit 1; \
	fi

check-pdk:
	@if [ ! -d "$(PDK_ROOT)" ]; then \
		echo "PDK Root: "$(PDK_ROOT)" doesn't exists, please export the correct path before running make. "; \
		exit 1; \
	fi

.PHONY: help
help:
	cd $(CARAVEL_ROOT) && $(MAKE) help
	@$(MAKE) -pRrq -f $(lastword $(MAKEFILE_LIST)) : 2>/dev/null | awk -v RS= -F: '/^# File/,/^# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' | sort | egrep -v -e '^[^[:alnum:]]' -e '^$@$$'

.PHONY: check_dependencies
check_dependencies:
	@if [ ! -d "$(PWD)/dependencies" ]; then \
		mkdir $(PWD)/dependencies; \
	fi


export CUP_ROOT=$(shell pwd)
export TIMING_ROOT?=$(shell pwd)/dependencies/timing-scripts
export PROJECT_ROOT=$(CUP_ROOT)
timing-scripts-repo=https://github.com/efabless/timing-scripts.git

$(TIMING_ROOT):
	@mkdir -p $(CUP_ROOT)/dependencies
	@git clone $(timing-scripts-repo) $(TIMING_ROOT)

.PHONY: setup-timing-scripts
setup-timing-scripts: $(TIMING_ROOT)
	@( cd $(TIMING_ROOT) && git pull )
	@#( cd $(TIMING_ROOT) && git fetch && git checkout $(MPW_TAG); )

.PHONY: install-caravel-cocotb
install-caravel-cocotb:
	rm -rf ./venv-cocotb
	$(PYTHON_BIN) -m venv ./venv-cocotb
	./venv-cocotb/bin/$(PYTHON_BIN) -m pip install --upgrade --no-cache-dir pip
	./venv-cocotb/bin/$(PYTHON_BIN) -m pip install --upgrade --no-cache-dir caravel-cocotb

.PHONY: setup-cocotb-env
setup-cocotb-env:
	@(python3 $(PROJECT_ROOT)/verilog/dv/setup-cocotb.py $(CARAVEL_ROOT) $(MCW_ROOT) $(PDK_ROOT) $(PDK) $(PROJECT_ROOT))

.PHONY: setup-cocotb
setup-cocotb: install-caravel-cocotb setup-cocotb-env simenv-cocotb

.PHONY: check-cocotb-runtime
check-cocotb-runtime:
	@if [ "$(COCOTB_REQUIRE_RUNTIME)" = "0" ]; then \
		echo "WARNING: Skipping cocotb docker runtime precheck (COCOTB_REQUIRE_RUNTIME=0)."; \
		exit 0; \
	fi
	@set -e; \
	tmp_log=$$(mktemp); \
	if $(COCOTB_DOCKER_PLATFORM_ENV) docker run --rm $(COCOTB_DOCKER_PLATFORM_ARG) --entrypoint /bin/sh efabless/dv:cocotb -c 'echo ok' >$$tmp_log 2>&1; then \
		rm -f $$tmp_log; \
	else \
		echo "ERROR: efabless/dv:cocotb is not runnable on this host."; \
		echo "Host arch: $$(uname -m)"; \
		echo "Runtime probe output:"; \
		cat $$tmp_log; \
		rm -f $$tmp_log; \
		echo "If your host is arm64 and only amd64 image is available, enable Docker x86 emulation or run in x86_64 environment."; \
		echo "Optional overrides:"; \
		echo "  COCOTB_DOCKER_PLATFORM=linux/amd64 vsdmake cocotb-verify-all-rtl"; \
		echo "  COCOTB_DOCKER_PLATFORM=linux/arm64/v8 vsdmake cocotb-verify-all-rtl"; \
		echo "  COCOTB_REQUIRE_RUNTIME=0 vsdmake cocotb-verify-all-rtl  (not recommended)"; \
		exit 1; \
	fi

.PHONY: cocotb-verify-all-rtl
cocotb-verify-all-rtl: check-cocotb-runtime
	@(cd $(PROJECT_ROOT)/verilog/dv/cocotb && $(COCOTB_DOCKER_PLATFORM_ENV) $(PROJECT_ROOT)/venv-cocotb/bin/caravel_cocotb -tl user_proj_tests/user_proj_tests.yaml )
	
.PHONY: cocotb-verify-all-gl
cocotb-verify-all-gl: check-cocotb-runtime
	@(cd $(PROJECT_ROOT)/verilog/dv/cocotb && $(COCOTB_DOCKER_PLATFORM_ENV) $(PROJECT_ROOT)/venv-cocotb/bin/caravel_cocotb -tl user_proj_tests/user_proj_tests_gl.yaml -sim GL)

$(cocotb-dv-targets-rtl): cocotb-verify-%-rtl: check-cocotb-runtime
	@(cd $(PROJECT_ROOT)/verilog/dv/cocotb && $(COCOTB_DOCKER_PLATFORM_ENV) $(PROJECT_ROOT)/venv-cocotb/bin/caravel_cocotb -t $*  )
	
$(cocotb-dv-targets-gl): cocotb-verify-%-gl: check-cocotb-runtime
	@(cd $(PROJECT_ROOT)/verilog/dv/cocotb && $(COCOTB_DOCKER_PLATFORM_ENV) $(PROJECT_ROOT)/venv-cocotb/bin/caravel_cocotb -t $* -sim GL)

./verilog/gl/user_project_wrapper.v:
	$(error you don't have $@)

./env/spef-mapping.tcl: 
	@echo "run the following:"
	@echo "make extract-parasitics"
	@echo "make create-spef-mapping"
	exit 1

.PHONY: create-spef-mapping
create-spef-mapping: ./verilog/gl/user_project_wrapper.v
	docker run \
		--rm \
		$(USER_ARGS) \
		-v $(PDK_ROOT):$(PDK_ROOT) \
		-v $(CUP_ROOT):$(CUP_ROOT) \
		-v $(CARAVEL_ROOT):$(CARAVEL_ROOT) \
		-v $(MCW_ROOT):$(MCW_ROOT) \
		-v $(TIMING_ROOT):$(TIMING_ROOT) \
		-w $(shell pwd) \
		efabless/timing-scripts:latest \
		python3 $(TIMING_ROOT)/scripts/generate_spef_mapping.py \
			-i ./verilog/gl/user_project_wrapper.v \
			-o ./env/spef-mapping.tcl \
			--pdk-path $(PDK_ROOT)/$(PDK) \
			--macro-parent chip_core/mprj \
			--project-root "$(CUP_ROOT)"


.PHONY: extract-parasitics
extract-parasitics: ./verilog/gl/user_project_wrapper.v
	docker run \
		--rm \
		$(USER_ARGS) \
		-v $(PDK_ROOT):$(PDK_ROOT) \
		-v $(CUP_ROOT):$(CUP_ROOT) \
		-v $(CARAVEL_ROOT):$(CARAVEL_ROOT) \
		-v $(MCW_ROOT):$(MCW_ROOT) \
		-v $(TIMING_ROOT):$(TIMING_ROOT) \
		-w $(shell pwd) \
		efabless/timing-scripts:latest \
		python3 $(TIMING_ROOT)/scripts/get_macros.py \
			-i ./verilog/gl/user_project_wrapper.v \
			-o ./tmp-macros-list \
			--project-root "$(CUP_ROOT)" \
			--pdk-path $(PDK_ROOT)/$(PDK)
	@cat ./tmp-macros-list | cut -d " " -f2 \
		| xargs -I % bash -c "$(MAKE) -C $(TIMING_ROOT) \
			-f $(TIMING_ROOT)/timing.mk rcx-% || echo 'Cannot extract %. Probably no def for this macro'"
	@$(MAKE) -C $(TIMING_ROOT) -f $(TIMING_ROOT)/timing.mk rcx-user_project_wrapper
	@cat ./tmp-macros-list
	@rm ./tmp-macros-list
	
.PHONY: caravel-sta
caravel-sta: ./env/spef-mapping.tcl
	@$(MAKE) -C $(TIMING_ROOT) -f $(TIMING_ROOT)/timing.mk caravel-timing-typ -j3
	@$(MAKE) -C $(TIMING_ROOT) -f $(TIMING_ROOT)/timing.mk caravel-timing-fast -j3
	@$(MAKE) -C $(TIMING_ROOT) -f $(TIMING_ROOT)/timing.mk caravel-timing-slow -j3
	@echo =============================================Summary=============================================
	@find $(PROJECT_ROOT)/signoff/caravel/openlane-signoff/timing/*/ -name "summary.log" | head -n1 \
		| xargs head -n5 | tail -n1
	@find $(PROJECT_ROOT)/signoff/caravel/openlane-signoff/timing/*/ -name "summary.log" \
		| xargs -I {} bash -c "head -n7 {} | tail -n1"
	@echo =================================================================================================
	@echo "You can find results for all corners in $(CUP_ROOT)/signoff/caravel/openlane-signoff/timing/"
	@echo "Check summary.log of a specific corner to point to reports with reg2reg violations" 
	@echo "Cap and slew violations are inside summary.log file itself"
