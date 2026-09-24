#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
hardware_dir="$(cd "$script_dir/.." && pwd)"
mkdir -p "$hardware_dir/reports"
source /mnt/sn850x_4tb_1/vivado/tools/AMD/2026.1/Vivado/settings64.sh
exec vivado -mode batch -nojournal -notrace \
  -source "$hardware_dir/tcl/build.tcl" \
  -log "$hardware_dir/reports/vivado_synth.log"
