# VSD Sky130 SoC (Caravel User Project Flow)

This repository is based on `caravel_user_project` and is set up so users can run the flow with `vsdmake`.

## Pre-requisites (Ubuntu/Debian)

Install base tools:

```bash
sudo apt-get update
sudo apt-get install -y \
  git make curl wget ca-certificates \
  build-essential pkg-config \
  python3 python3-pip python3-venv python3-dev \
  libffi-dev libssl-dev
```

Install Docker (required by OpenLane/cocotb/precheck flows):

```bash
sudo apt-get install -y docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker
docker --version
docker run --rm hello-world
```

Install Magic (recommended `>= 8.3.411`):

```bash
sudo apt-get install -y \
  m4 tcsh csh libx11-dev tcl-dev tk-dev \
  libcairo2-dev mesa-common-dev libglu1-mesa-dev

cd ~
git clone --depth=1 https://github.com/RTimothyEdwards/magic.git
cd magic
./configure
make -j"$(nproc)"
sudo make install
```

Verify Magic version:

```bash
magic -dnull -noconsole <<'EOF'
version
quit -noprompt
EOF
```

[OPTIONAL, NEEDED ONLY FOR GLS STAGE] If you are on a low-memory VM, configure swap before long GL/final runs:

```bash
sudo fallocate -l 24G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## System Requirements (Recommended)

- Disk space:
  - Minimum: `120 GB` free
  - Recommended: `180 GB+` free
- RAM:
  - Minimum: `8 GB` (slow)
  - Recommended: `16 GB+`
- Swap (especially for low-RAM VMs): `16–24 GB`

Heavy steps:
- Gate-level cocotb (`*-gl`)
- Full-chip generation (`ship`, `fill`, `final`)

## 1) Clone

```bash
cd ~
git clone https://github.com/vsdip/vsd-sky130-soc.git
cd vsd-sky130-soc
```

## 2) Use `vsdmake` command

You can use either:

```bash
./vsdmake <target>
```

or create a command alias once:

```bash
alias vsdmake="$PWD/vsdmake"
```

Then use:

```bash
vsdmake --help
```

## 3) Initial setup (from scratch)

```bash
vsdmake setup
```

This downloads/builds required project dependencies (`caravel`, `mgmt_core_wrapper`, `openlane`, PDK via volare, cocotb environment, precheck setup).

## 4) Harden example design

```bash
vsdmake user_proj_example
vsdmake user_project_wrapper
```

## 5) Full-chip integration artifacts

```bash
export USER_ID=1234ABCD
export PROJECT=caravel
vsdmake set_user_id
vsdmake ship
vsdmake fill
vsdmake final
```

Notes:
- `vsdmake fill` maps to `make generate_fill`.
- Final integrated GDS: `gds/caravel_${USER_ID}.gds`

## 6) Verification

RTL:

```bash
vsdmake cocotb-verify-all-rtl
```

Cocotb docker portability note (Linux/macOS, x86_64/arm64):

- By default, docker selects platform automatically.
- If needed, force platform explicitly:

```bash
COCOTB_DOCKER_PLATFORM=linux/amd64 vsdmake cocotb-verify-all-rtl
```

- Quick runtime check (required before cocotb runs):

```bash
docker run --rm --platform=linux/amd64 alpine uname -m
```

If this fails with `exec format error` on arm64, enable amd64 emulation in Docker (or run cocotb on x86_64 host/CI).

GL (recommended one by one on low-memory VMs):

```bash
vsdmake cocotb-verify-counter_wb-gl
vsdmake cocotb-verify-counter_la-gl
vsdmake cocotb-verify-counter_la_reset-gl
vsdmake cocotb-verify-counter_la_clk-gl
```

Precheck:

```bash
vsdmake precheck
vsdmake run-precheck
```

## 7) Extra docs

Project documentation inherited from upstream flow:

- `docs/source/index.md`

## 8) Technical Changes vs original `caravel_user_project`

This repository intentionally includes a small set of technical deltas from upstream to make the flow reproducible with `vsdmake` and more robust for typical VM environments.

1. Added wrapper command: `vsdmake`
   File: `vsdmake`
   What changed:
   - Added a repo-local executable wrapper over `make`.
   - Pass-through behavior for normal targets.
   - Added alias target mapping: `fill` -> `generate_fill`.
   Why:
   - Gives a single user-facing command (`vsdmake ...`) for setup/build/verify commands.

2. Updated top-level usage and requirements documentation
   File: `README.md`
   What changed:
   - Added end-to-end flow using `vsdmake`.
   - Added resource recommendations (disk/RAM/swap).
   - Added guidance for heavy steps (`*-gl`, `ship/fill/final`).
   Why:
   - Reduces setup ambiguity and avoids common VM resource failures.

3. Added GL compatibility shim for missing fill-cell module name
   File: `verilog/gl/sky130_ef_sc_hd__fill_4.v`
   What changed:
   - Added module `sky130_ef_sc_hd__fill_4` that wraps `sky130_fd_sc_hd__fill_4`.
   - Includes full power-pin interface (`VGND`, `VNB`, `VPB`, `VPWR`).
   Why:
   - Some Caravel GL netlists instantiate `sky130_ef_sc_hd__fill_4`, while available simulation libraries expose `sky130_fd_sc_hd__fill_4`.
   - Prevents GL elaboration failures due to missing module type.

4. Enabled required GL include files for GPIO default blocks
   File: `verilog/includes/includes.gl.caravel_user_project`
   What changed:
   - Enabled inclusion of:
     - `gpio_defaults_block_0403.v`
     - `gpio_defaults_block_0801.v`
     - `gpio_defaults_block_1803.v`
   - Added inclusion of the shim file:
     - `sky130_ef_sc_hd__fill_4.v`
   Why:
   - Fixes GL compilation errors for unresolved `gpio_defaults_block_*` modules.
   - Ensures the fill-cell compatibility shim is visible to `iverilog`.

5. Made GPIO default macro parser-friendly for generated collateral
   File: `verilog/rtl/user_defines.v`
   What changed:
   - Set `GPIO_MODE_INVALID` to literal `13'h0403` (instead of placeholder `13'hXXXX`).
   Why:
   - `gen_gpio_defaults` expects parseable 4-digit hex values.
   - Avoids repetitive generation errors during cocotb GL flow setup.

6. Adjusted cocotb timeout for `counter_wb`
   File: `verilog/dv/cocotb/user_proj_tests/counter_wb/counter_wb.py`
   What changed:
   - Increased `test_configure(... timeout_cycles=...)` from `22620` to `59844`.
   Why:
   - Prevents premature timeout in environments where firmware setup/Wishbone activity starts later.
   - Aligns timeout behavior closer to other counter tests.

7. Updated ignore policy for large/generated local artifacts
   File: `.gitignore`
   What changed:
   - Added ignores for local env/build outputs (`venv-cocotb`, cocotb sim runs, large generated `caravel*.gds` and fill-pattern GDS files).
   Why:
   - Keeps repository lean and source-focused.
   - Prevents accidental commits of large machine-generated outputs.
