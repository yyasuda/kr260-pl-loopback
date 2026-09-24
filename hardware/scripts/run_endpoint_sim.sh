#!/usr/bin/env bash
set -euo pipefail

tree_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
hardware_dir=$(cd -- "$tree_dir/.." && pwd)
mkdir -p "$hardware_dir/reports"
source /mnt/sn850x_4tb_1/vivado/tools/AMD/2026.1/Vivado/settings64.sh
vivado -mode batch -nojournal -notrace \
  -source "$hardware_dir/tcl/create_ip_and_sim_project.tcl" \
  -log "$hardware_dir/reports/vivado_endpoint_sim.log"
grep -q '03M6_TX_FRAME_BUFFER_PASS' "$hardware_dir/reports/vivado_endpoint_sim.log"
