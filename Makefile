# ============================================================
# FPGA TDD project Makefile — GHDL backend
# One file, project root. Targets: uvvm, green, ci, wave, clean, clean-uvvm
# ------------------------------------------------------------
#   make uvvm     compile UVVM source into the local library (one-time)
#   make green    compile RTL + TB, run sim, fail on any error
#   make ci       same as green but no waveform (fast, for pipeline)
#   make wave     open the last green waveform in GTKWave
#   make clean    remove sim build output (keeps compiled UVVM)
# ============================================================

# ---- paths --------------------------------------------------
UVVM_LIB   := sim/uvvm_lib/uvvm_util
UVVM_STAMP := $(UVVM_LIB)/uvvm_util-obj08.cf
WORK_DIR   := sim/work

GHDL_FLAGS := --std=08 -frelaxed -P$(UVVM_LIB)

# ---- design + testbench sources (compile order matters) -----
# Package first (shared types), then RTL, then TB.
SRCS := src/runner_pkg.vhd \
        src/runner.vhd \
        tb/tb_runner.vhd

TOP  := tb_runner

# ============================================================
# UVVM — compiled once into the local library.
# Stamp-file target (NOT phony): no-op once built, rebuilds only
# when the submodule's compile_order.txt or the script changes.
# ============================================================
uvvm: $(UVVM_STAMP)

$(UVVM_STAMP): sub/uvvm/uvvm_util/script/compile_order.txt scripts/compile_uvvm.sh
	bash scripts/compile_uvvm.sh

# ============================================================
# GREEN — the everyday target. Depends on UVVM so a fresh
# checkout builds the library automatically before simulating.
# ============================================================
green: $(UVVM_STAMP)
	mkdir -p $(WORK_DIR)
	ghdl -a $(GHDL_FLAGS) --workdir=$(WORK_DIR) $(SRCS)
	ghdl -e $(GHDL_FLAGS) --workdir=$(WORK_DIR) $(TOP)
	ghdl -r $(GHDL_FLAGS) --workdir=$(WORK_DIR) $(TOP) \
	     --wave=$(WORK_DIR)/$(TOP).ghw 2>&1 | tee $(WORK_DIR)/sim.log
	@grep -q "Simulation SUCCESS" $(WORK_DIR)/sim.log && echo "GREEN: all tests passed" \
	  || (echo "CI FAILED: no UVVM SUCCESS verdict" && exit 1)
# ============================================================
# CI — no waveform dump; exits nonzero on any error.
# ============================================================
ci: $(UVVM_STAMP)
	mkdir -p $(WORK_DIR)
	ghdl -a $(GHDL_FLAGS) --workdir=$(WORK_DIR) $(SRCS)
	ghdl -e $(GHDL_FLAGS) --workdir=$(WORK_DIR) $(TOP)
	ghdl -r $(GHDL_FLAGS) --workdir=$(WORK_DIR) $(TOP) 2>&1 | tee $(WORK_DIR)/ci.log
	@grep -q "Simulation SUCCESS" $(WORK_DIR)/ci.log && echo "CI: all tests passed" \
	  || (echo "CI FAILED: no UVVM SUCCESS verdict" && exit 1)

# ============================================================
# Convenience
# ============================================================
wave:
	gtkwave $(WORK_DIR)/$(TOP).ghw tb/$(TOP).gtkw &

clean:
	rm -rf $(WORK_DIR)

clean-uvvm:
	rm -rf sim/uvvm_lib

.PHONY: uvvm green ci wave clean clean-uvvm
