#!/usr/bin/env bash
set -euo pipefail

tree=$(cd "$(dirname "$0")/.." && pwd)
input="$tree/../stage1g4_03k_bootfw/artifacts/image-stage1g4-03k-rx-axis-ila.fit"
expected_input_sha256=e4b5a1b292956edd4fe38cd63fcf8076cb4e251123c1f7210f8dc2516ad3765c
output="$tree/artifacts/image-stage1g4-03l-rgmii-id.fit"
overlay="$tree/stage1g4_03l_rgmii_id_overlay.dts"
records="$tree/records"
tool_build="$tree/../stage1g4_03k_bootfw/build"

actual_input_sha256=$(sha256sum "$input" | awk '{print $1}')
if [[ "$actual_input_sha256" != "$expected_input_sha256" ]]; then
	echo "ERROR: input FIT SHA-256 mismatch" >&2
	echo "expected: $expected_input_sha256" >&2
	echo "actual:   $actual_input_sha256" >&2
	exit 1
fi

if [[ -e "$output" ]]; then
	echo "ERROR: refusing to overwrite existing output: $output" >&2
	exit 1
fi

native_bin=$(find "$tool_build" -type f -path '*/dtc-native/usr/bin/dtc' -print -quit)
dtc=${native_bin:?dtc-native not found}
native_dir=${native_bin%/dtc}
fdtoverlay="$native_dir/fdtoverlay"
fdtget="$native_dir/fdtget"
fdtput="$native_dir/fdtput"
dumpimage=$(find "$tool_build" -type f -name dumpimage -print -quit)
: "${dumpimage:?dumpimage not found}"

for tool in "$dtc" "$fdtoverlay" "$fdtget" "$fdtput" "$dumpimage"; do
	[[ -x "$tool" ]] || { echo "ERROR: required tool is not executable: $tool" >&2; exit 1; }
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

extract_position() {
	local fit=$1
	local position=$2
	local destination=$3
	"$dumpimage" -T flat_dt -p "$position" -o "$destination" "$fit" >/dev/null
}

snapshot_node() {
	local blob=$1
	local path=$2
	local child prop
	echo "NODE $path"
	while IFS= read -r prop; do
		[[ -n "$prop" ]] || continue
		printf 'PROP %s ' "$prop"
		"$fdtget" -t bx "$blob" "$path" "$prop"
	done < <("$fdtget" -p "$blob" "$path" | LC_ALL=C sort)
	while IFS= read -r child; do
		[[ -n "$child" ]] || continue
		if [[ "$path" == "/" ]]; then
			snapshot_node "$blob" "/$child"
		else
			snapshot_node "$blob" "$path/$child"
		fi
	done < <("$fdtget" -l "$blob" "$path" | LC_ALL=C sort)
}

extract_position "$input" 5 "$tmp/03k-position5.dtb"
before_phy_mode=$("$fdtget" -t s "$tmp/03k-position5.dtb" /axi/ethernet@ff0d0000 phy-mode)
[[ "$before_phy_mode" == "rgmii-txid" ]] || {
	echo "ERROR: input position 5 phy-mode is not rgmii-txid: $before_phy_mode" >&2
	exit 1
}

"$dtc" -@ -I dts -O dtb -o "$tmp/03l.dtbo" "$overlay"
"$fdtoverlay" -i "$tmp/03k-position5.dtb" -o "$tmp/03l-position5.dtb" "$tmp/03l.dtbo"
after_phy_mode=$("$fdtget" -t s "$tmp/03l-position5.dtb" /axi/ethernet@ff0d0000 phy-mode)
[[ "$after_phy_mode" == "rgmii-id" ]] || {
	echo "ERROR: output position 5 phy-mode is not rgmii-id: $after_phy_mode" >&2
	exit 1
}

"$dtc" -I dtb -O dts -o "$tmp/03k-position5.dts" "$tmp/03k-position5.dtb"
"$dtc" -I dtb -O dts -o "$tmp/03l-position5.dts" "$tmp/03l-position5.dtb"
if diff -u "$tmp/03k-position5.dts" "$tmp/03l-position5.dts" > "$tmp/position5-semantic.diff"; then
	echo "ERROR: position 5 DTB has no semantic difference" >&2
	exit 1
fi
sed 's/[[:blank:]]*$//' "$tmp/position5-semantic.diff" > "$tmp/position5-semantic-clean.diff"
mv "$tmp/position5-semantic-clean.diff" "$tmp/position5-semantic.diff"

change_count=$(awk '/^[-+]/ && !/^---/ && !/^\+\+\+/ { count++ } END { print count + 0 }' "$tmp/position5-semantic.diff")
removed_count=$(grep -Ec '^-[[:space:]]*phy-mode = "rgmii-txid";' "$tmp/position5-semantic.diff" || true)
added_count=$(grep -Ec '^\+[[:space:]]*phy-mode = "rgmii-id";' "$tmp/position5-semantic.diff" || true)
if [[ "$change_count" -ne 2 || "$removed_count" -ne 1 || "$added_count" -ne 1 ]]; then
	echo "ERROR: position 5 DTB semantic difference is not limited to phy-mode" >&2
	cat "$tmp/position5-semantic.diff" >&2
	exit 1
fi

snapshot_node "$input" /configurations > "$tmp/03k-configurations.txt"
snapshot_node "$input" / > "$tmp/03k-fit-root.txt"

cp -- "$input" "$output"
chmod 0644 "$output"
bytes=( $(od -An -v -t x1 "$tmp/03l-position5.dtb") )
"$fdtput" -t bx "$output" /images/fdt-smk-k26-revA-sck-kr-g-revB.dtb data "${bytes[@]}"
read -ra hash_bytes <<< "$(sha1sum "$tmp/03l-position5.dtb" | cut -d' ' -f1 | sed 's/../& /g')"
"$fdtput" -t bx "$output" /images/fdt-smk-k26-revA-sck-kr-g-revB.dtb/hash-1 value "${hash_bytes[@]}"

"$dumpimage" -l "$output" > "$tmp/fit-list.txt"
extract_position "$output" 5 "$tmp/output-position5.dtb"
cmp -s "$tmp/03l-position5.dtb" "$tmp/output-position5.dtb" || {
	echo "ERROR: materialized position 5 DTB differs from the intended DTB" >&2
	exit 1
}

for position in 0 1 2 3 4 6 7; do
	extract_position "$input" "$position" "$tmp/03k-position${position}.bin"
	extract_position "$output" "$position" "$tmp/03l-position${position}.bin"
	cmp -s "$tmp/03k-position${position}.bin" "$tmp/03l-position${position}.bin" || {
		echo "ERROR: FIT position $position changed unexpectedly" >&2
		exit 1
	}
done

snapshot_node "$output" /configurations > "$tmp/03l-configurations.txt"
cmp -s "$tmp/03k-configurations.txt" "$tmp/03l-configurations.txt" || {
	echo "ERROR: FIT configurations changed unexpectedly" >&2
	exit 1
}

# Compare FIT root properties only. Image payload/hash differences are checked
# separately, and the configurations subtree is compared recursively above.
for prop in $("$fdtget" -p "$input" / | LC_ALL=C sort); do
	"$fdtget" -t bx "$input" / "$prop" > "$tmp/input-root-$prop"
	"$fdtget" -t bx "$output" / "$prop" > "$tmp/output-root-$prop"
	cmp -s "$tmp/input-root-$prop" "$tmp/output-root-$prop" || {
		echo "ERROR: FIT root property changed unexpectedly: $prop" >&2
		exit 1
	}
done

mkdir -p "$records"
cp -- "$tmp/position5-semantic.diff" "$records/position5-semantic.diff"
cp -- "$tmp/fit-list.txt" "$records/fit-list.txt"
{
	echo "input_fit=$input"
	echo "input_sha256=$actual_input_sha256"
	echo "output_fit=$output"
	echo "output_sha256=$(sha256sum "$output" | awk '{print $1}')"
	echo "input_phy_mode=$before_phy_mode"
	echo "output_phy_mode=$after_phy_mode"
	echo "position_0_kernel=identical"
	echo "position_1_initramfs=identical"
	echo "positions_2_3_4_6_7_dtb=identical"
	echo "configurations=identical"
	echo "position_5_semantic_diff=phy-mode-only"
} > "$records/guard-summary.txt"

echo "created: $output"
sha256sum "$output"
echo "all FIT and DT guards passed"
