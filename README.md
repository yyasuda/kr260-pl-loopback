# KR260 TEMAC–P4Fab PL loopback reference implementation

AMD Kria KR260のJ10B Ethernet portで受信したframeを、PL内の32-bit P4Fab boundaryを経由して同じportへ返送するsource-only reference implementationです。

このtreeは、開発repository `stage1_p4fab_datapath` の03m-6 known-good checkpoint、commit `5bf07d106ce354603c51f2a641b18d8ec8633d60` から、第三者による再生成に必要なhandwritten sourceだけを抽出して整理したものです。開発repositoryの履歴や生成済みprojectをそのまま公開するものではありません。

## 確認済みdatapath

外部hostのEthernet cableは、KR260 carrier boardの`J10B` RJ45へ接続します。`J10B`は同じboard上の`U79 DP83867`
PHYを介してPL TEMACとRGMII接続されています。受信frameはTEMAC RXからP4Fab 32-bit boundaryへ入り、
direct loopback後にTEMAC TXから同じPHYと`J10B`を通って外部hostへ返ります。

```text
                        External Ethernet host
                            |           ^
            1000BASE-T RX  |           |  1000BASE-T TX
                            v           |
                 KR260 carrier J10B RJ45 (single port)
                            |           ^
                            v           |
                     U79 DP83867 PHY (single PHY)
                            |           ^
                   RGMII RX |           | RGMII TX
                            v           |
+--------------------------- KR260 PL ----------------------------+
|                                                                 |
|  TEMAC RX AXI4-Stream (8-bit)                                   |
|       |                                                         |
|       v                                                         |
|  RX store-and-forward frame buffer                              |
|       |                                                         |
|       v                                                         |
|  8-to-32 packer                                                 |
|       |                                                         |
|       v                                                         |
|  AXI4-Stream Clock Converter                                    |
|       |                                                         |
|       v                                                         |
|  P4Fab boundary (32-bit)                                        |
|       |                                                         |
|       +------------- direct loopback -------------+             |
|                                                     |             |
|                                                     v             |
|                                             32-to-8 unpacker     |
|                                                     |             |
|                                                     v             |
|                                             TX store-and-forward |
|                                             frame buffer         |
|                                                     |             |
|                                                     v             |
|                                             TEMAC TX AXI4-Stream |
|                                             (8-bit)              |
|                                                     |             |
+-----------------------------------------------------|-------------+
                                                      |
                                                      +-- RGMII TX --^

Management path to the same U79 PHY:

  PS GEM2
     |
     +-- EMIO MDC/MDIO ------------------------> U79 DP83867
         management-only                        management registers

  PS GEM2 GMII packet signals --> gmii_idle_terminator
  (not connected to the Ethernet packet datapath above)
```

PS GEM2は`U79 DP83867`のMDIO managementにだけ使用します。EMIO MDC/MDIOはPHYへ接続されますが、
GEM2のGMII packet signalsは上記Ethernet packet datapathに入らず、PL内の`gmii_idle_terminator`で終端されます。

元の03m-6 checkpointでは、FCSを除く80、800、1500、1514-byte Ethernet frameのKR260実機loopbackがPASSし、1514-byte frameでも送信内容と返送内容の一致を確認しています。

## 対象環境

- Board: AMD Kria KR260 Robotics Starter Kit
- Device: `xck26-sfvc784-2LV-c`
- Vivado: 2026.1
- Board part: `xilinx.com:kr260_som:part0:2.0`
- Carrier board connection: KR260 carrier 2.0
- Physical port: KR260 J10B / DP83867

`hardware/scripts/`は03m-6 known-good環境の
`/mnt/sn850x_4tb_1/vivado/tools/AMD/2026.1/Vivado/settings64.sh`を参照します。第三者環境では、Vivado 2026.1のinstall先に合わせてこのpathの調整が必要です。

## Source-only方針

Vivado projectとAMD/Xilinx IPは`hardware/tcl/`のTclから生成します。このtreeには以下を収録しません。

- Vivado generated project、HDL、XDC、IP output products
- TEMAC protected/encrypted source
- `.xci`、`.bd`、`.xpr`
- `.runs`、`.gen`、`.cache`、`.Xil`などのbuild状態
- `.bit`、`.xsa`、`.ltx`
- `BOOT.bin`、Ubuntu FIT、その他のbinary release artifact

binary artifactは収録していません。また、このpublic repositoryのsource treeからのVivado build、simulation、EDF / BitBake build、FIT再生成、第三者環境での再生成はまだ確認していません。

## 現在の構成

```text
hardware/
  rtl/          handwritten RTL
  constraints/  board pinおよび実装時制約
  tcl/          IP/BD生成、synthesis、implementation/export、simulation Tcl
  scripts/      Vivado 2026.1実行wrapper
  sim/          endpoint testbench
boot/
  stage1g4_03k_bootfw/
    meta-stage1g4/  03m-6 PL bitstreamをBOOT.binに収録するEDF/Yocto layer
  stage1g4_03l_fit/
    scripts/        03k FITから03l FITをmaterializeするscript
    *.dts           `phy-mode = "rgmii-id"`のDevice Tree overlay
```

`boot/`はBoot FWとUbuntu FITを後で再生成するためのhandwritten sourceだけを収録しています。03m-6の実機known-good構成では、03m-6 PL bitstreamを含むBoot FWと03lの`phy-mode = "rgmii-id"` Ubuntu FITを組み合わせました。BOOT.bin、FIT、bitstream、XSA、SDT generated artifactは現段階では含めていません。

実機試験script、完全なbuild/deployment手順、release artifactは収録していません。

## 文書

- [ソースからのビルド](docs/BUILD.ja.md)
- [実機状態の再現手順](docs/REPRODUCE.ja.md)

どちらも現時点で確認済みの入力関係と安全条件を記録した最小文書です。完全な新規EDF環境構築、SDT artifact生成、03k baseline FIT生成は未整備です。

## ライセンス

このrepositoryには現時点で包括的なライセンスを設定していません。AMD/Xilinx IPやその生成物等には各提供元のライセンス条件が適用され得ます。利用・再配布時には、利用者側で適切なライセンス条件を確認してください。
