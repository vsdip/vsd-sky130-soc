# VSD SCL180 SoC (Caravel User Project Flow)

This repository is based on `caravel_user_project` and is set up so users can run the flow with `vsdmake`.

## 1) Clone

```bash
git clone https://github.com/vsdip/vsd-scl180-soc.git
cd vsd-scl180-soc
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
