# ソースからのビルド

## 1. この文書の範囲

この文書は、03m-6 known-good checkpoint（開発repository commit
`5bf07d106ce354603c51f2a641b18d8ec8633d60`）から抽出したsourceの関係と、確認済みの生成順を
記録する。現在のrepositoryはsource-onlyであり、この文書作成時点では公開候補treeからの再buildを
実施していない。

確認済みの元環境は次のとおり。

- AMD Kria KR260 Robotics Starter Kit
- device: `xck26-sfvc784-2LV-c`
- board part: `xilinx.com:kr260_som:part0:2.0`
- carrier board connection: KR260 carrier 2.0
- Vivado 2026.1
- AMD EDF 26.06
- EDF machine: `k26-smk-kr-sdt-multidomain`

最終的な成果物の関係は次のとおり。

```text
hardware source
  -> Vivado 2026.1
  -> stage1g4_03m6_tx_frame_buffer.bit / .xsa / .ltx

stage1g4_03m6_tx_frame_buffer.bit
stage1g4_03m6_tx_frame_buffer.xsa -> SDT artifact
03k meta-stage1g4 layer
  -> EDF 26.06 / BitBake
  -> BOOT-stage1g4-03m6-tx-frame-buffer.bin

03k baseline Ubuntu FIT
03l rgmii-id overlay
  -> materialize script
  -> image-stage1g4-03l-rgmii-id.fit
```

03m-6の実機known-goodは、03m-6 PL bitstreamを含むBoot FWと、03lの
`phy-mode = "rgmii-id"` FITを組み合わせた構成である。
この構成で、FCSを除く80、800、1500、1514-byte Ethernet frameの実機loopbackがPASSした。

## 2. Vivado hardware

`hardware/`の役割は次のとおり。

- `rtl/`: handwritten RTL
- `constraints/`: KR260 pin、RGMII I/O timing、TEMAC TX DDR関連制約
- `tcl/`: project、AMD/Xilinx IP、block design、synthesis、implementation、export手順
- `scripts/`: Vivado 2026.1 batch実行wrapper
- `sim/`: endpoint testbench

Vivado project、`.xci`、`.bd`、generated HDL/XDC、IP output productsはrepositoryに含めない。
`hardware/tcl/`がTEMAC、Clocking Wizard、ILA、AXI4-Stream Clock ConverterおよびPS block
designを生成する。

wrapperは確認済み環境の次の固定pathからVivado 2026.1設定を読み込む。

```text
/mnt/sn850x_4tb_1/vivado/tools/AMD/2026.1/Vivado/settings64.sh
```

第三者環境向けのtool path指定方法は未整備である。このpathが存在しない環境では、実行前に
wrapperのtool pathをその環境へ合わせる必要があるが、その変更後の再現性は未確認である。

### 2.1 Simulation

repository rootから次を実行する構成である。

```bash
./hardware/scripts/run_endpoint_sim.sh
```

scriptはVivado behavioral simulationを実行し、log中の
`03M6_TX_FRAME_BUFFER_PASS`をguardする。生成projectは`hardware/build/simulation/`、reportは
`hardware/reports/`へ置かれる。

元の03m-6では60-byte、80-byte、TEMAC `TREADY` stallおよびunpacker gap吸収を含むsimulationが
PASSした。公開候補treeからの再実行は未確認である。

### 2.2 Synthesis checkpoint

```bash
./hardware/scripts/run_synth.sh
```

`hardware/tcl/build.tcl`はprojectとIP/BDを生成してsynthesisを行い、構成・接続・CDC・MDIOなどの
guardを確認した後、`03M6_SYNTHESIS_CHECKPOINT_PASS`でimplementation前に停止する。projectは
`hardware/build/vivado/`、reportは`hardware/reports/`へ置かれる。

並列job数は既定8で、既存sourceは環境変数`STAGE1G4_JOBS`による変更を受け付ける。

### 2.3 Implementationとartifact export

synthesis checkpointが存在する状態で次を実行する構成である。

```bash
./hardware/scripts/run_impl_and_export.sh
```

`hardware/tcl/run_impl_and_export.tcl`は既存projectを開き、route、timing、DRC、CDC、RGMII、MDIO、
ILAおよびdatapath guardを確認してから、次を`hardware/artifacts/`へ生成する。

```text
stage1g4_03m6_tx_frame_buffer.bit
stage1g4_03m6_tx_frame_buffer.xsa
stage1g4_03m6_tx_frame_buffer.ltx
```

出力が既に存在する場合は上書きせず停止する。元の03m-6ではimplementation/sign-offとartifact
生成がPASSしたが、公開候補treeでは未確認である。

## 3. XSAからSDT artifact

03k layerは次のSDT artifactを必要とする。

```text
boot/stage1g4_03k_bootfw/artifacts/
  sdt-stage1g4-txc975-usb-gem2-mdio-clkoff.tar.gz
```

元のknown-goodでは、Vivado 2026.1でStage 1g-4 clock-off XSAから生成したSDT artifactを使用した。
layer内には、そのファイル名と確認済みSHA-256が記録されている。

現在のrepositoryにはSDT artifact自体と生成scriptを含めていない。新しい
`stage1g4_03m6_tx_frame_buffer.xsa`から同artifactを生成するcommand、board DTS指定、生成物の
再照合手順は未整備・未確認である。03m-6ではPLだけを変更し、03k以前から確認済みの同じSDT
artifactを再利用した。

## 4. EDF 26.06 Boot FW

`boot/stage1g4_03k_bootfw/meta-stage1g4/`は03m-6で使用したEDF/Yocto layerである。

- `bitstream_%.bbappend`: `stage1g4_03m6_tx_frame_buffer.bit`を`virtual/bitstream`へ供給
- `xilinx-bootbin.bbappend`: boot-time flat PL bitstream partitionを有効化
- `sdt-artifacts.bbappend`: Stage 1g-4 SDT artifactを全multiconfigへ供給
- `device-tree.bbappend`: 同じSDTを使用し、FSBL multiconfigへGEM2 permission patchを適用
- FSBL patch: GEM2 (`0xff0d0000`)をA53 clusterのaddress mapへ追加

元の03m-6では、既存EDF 26.06 source treeの正規`edf-init-build-env`から新しい03k専用build
directoryを初期化し、`MACHINE=k26-smk-kr-sdt-multidomain`で次のtargetをbuildした。

```bash
bitbake xilinx-bootbin
```

bitstreamとSDT artifactは次の配置をlayerが参照する。

```text
boot/stage1g4_03k_bootfw/artifacts/
  stage1g4_03m6_tx_frame_buffer.bit
  sdt-stage1g4-txc975-usb-gem2-mdio-clkoff.tar.gz
```

生成BOOT.binはFSBL、PMUFW、PL bitstream、TF-A、machine DTB、U-Bootを収録し、PL partitionは
`destination_device=PL`であることが元のbuildで確認された。

EDF 26.06 sourceの新規取得、固定revision、`edf-init-build-env`の実path、`local.conf`、
`bblayers.conf`、downloads/sstateの構築を含む完全な新規環境手順は、現在のrepositoryでは未整備で
ある。したがって上記は生成関係の記録であり、第三者向けの完結したbuild recipeではない。

## 5. 03l Ubuntu FIT

03l FITはBoot FWとは別の共有Ubuntu FITである。PL bitstreamはFITではなくBOOT.binに入る。

materialize scriptは次を入力として固定guardする。

```text
boot/stage1g4_03k_bootfw/artifacts/image-stage1g4-03k-rx-axis-ila.fit
SHA-256: e4b5a1b292956edd4fe38cd63fcf8076cb4e251123c1f7210f8dc2516ad3765c
```

EDF build後にnative `dtc`、`fdtoverlay`、`fdtget`、`fdtput`、`dumpimage`が利用できる状態で、
repository rootから次を実行する構成である。

```bash
./boot/stage1g4_03l_fit/scripts/materialize_stage1g4_03l_fit.sh
```

scriptはFIT position 5のKR260 revB DTBへ
`boot/stage1g4_03l_fit/stage1g4_03l_rgmii_id_overlay.dts`を適用し、次を生成する。

```text
boot/stage1g4_03l_fit/artifacts/image-stage1g4-03l-rgmii-id.fit
```

guardはDTの意味差分が`phy-mode = "rgmii-txid"`から`"rgmii-id"`への1 propertyだけであること、
他のFIT payload/configurationが変化しないことを確認する。

03k baseline FITの生成方法は未整備であり、binaryもrepositoryに含めていない。異なるFIT layoutや
hashの入力へscriptを適用する手順も未確認である。

## 6. 未整備・未確認事項

- 公開候補treeからのVivado simulation/synthesis/implementation再実行
- 第三者PCでのVivado/Board Store/tool path設定
- XSAからSDT artifactを生成するsource/scriptとcommand
- EDF 26.06環境の完全な新規構築手順
- 03k baseline Ubuntu FITの生成または正規入手方法
- generated artifactとbinary artifactの公開可否・ライセンス条件
- 完全自動のend-to-end再生成
