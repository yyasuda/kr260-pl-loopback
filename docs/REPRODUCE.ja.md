# 実機状態の再現手順

## 1. この文書の範囲

この文書は、既存のknown-good Boot FWと03l Ubuntu FITをKR260へ導入するときの安全条件と順序を
記録する。現在のrepositoryにはbinary artifactを含めていないため、この文書だけで実機状態を
再現することはできない。
対応するsourceは03m-6 known-good checkpoint、開発repository commit
`5bf07d106ce354603c51f2a641b18d8ec8633d60`に由来する。

03m-6で確認済みの組合せは次のとおり。

- Boot FW: `BOOT-stage1g4-03m6-tx-frame-buffer.bin`
- Ubuntu FIT: `image-stage1g4-03l-rgmii-id.fit`
- physical port: KR260 J10B / U79 DP83867
- PL packet datapath: TEMAC RXから32-bit P4Fab boundaryを経由するdirect loopback、TEMAC TXへ返送
- management: PS GEM2はpacket転送に使わず、DP83867のMDIO managementに使用

元の03m-6ではFCSを除く80、800、1500、1514-byte frameがPASSし、1514-byte frameでも送信内容と
返送内容が一致した。

## 2. Boot FW A/Bの安全条件

書込み前にUART consoleを115200 bpsで利用できる状態にし、現在のA/B状態を確認する。

```bash
sudo xmutil bootfw_status
```

少なくとも次を記録する。

- Image AのBootable状態
- Image BのBootable状態
- Requested Boot Image
- Last Booted Image

固定的にAまたはBをrecovery側とみなさない。現在起動中で正常動作が確認できているimageを
known-goodとして残し、その時点のinactive imageだけをtrial更新する。唯一のknown-good imageを
上書きする状態なら停止する。

`/boot/firmware/image.fit`はA/B別ではなく共有される。Boot FWのfallbackが存在しても、共有FITの
誤りを自動的に元へ戻せるわけではないため、FITは置換前に固有名でバックアップする。

## 3. 03l Ubuntu FIT

03m-6では03l FITを使用した。03lはKR260 revB Linux DTBのGEM2 nodeについて、03kの
`phy-mode = "rgmii-txid"`を`phy-mode = "rgmii-id"`へ変更した構成である。PHY address 2、delay
code 7/7、RXCTRL strap quirk、FIFO depth、aliases、converter削除状態、GEM2 MDIO management構成は
維持された。

既存known-good手順では、共有FITをバックアップしてから一時名へcopyし、hashを確認して
`/boot/firmware/image.fit`へrenameした。現在のrepositoryには03l FITと`SHA256SUMS`を含めていない
ため、具体的な配布fileの転送・照合手順は未整備である。確認済み03l artifactの記録値は次である。

```text
file: image-stage1g4-03l-rgmii-id.fit
size: 67,611,660 bytes
SHA-256: 9785f951501d6b6647e7257a1ca6cd1df5ca9c38f5a279924a17bfbd8edfb6ef
```

別のUbuntu FITへ同じoverlayを盲目的に適用しない。materialize scriptは元の03k FITのhashとposition
5 layoutを固定guardしている。

## 4. dfx-mgrを停止する

この構成はfull bitstreamをBOOT.binへ収録し、physical cold boot時にFSBLがロードするflat PL
designである。Ubuntuの`dfx-mgr.service`が別designをロードすると、boot時のPL designが上書き
される。

既存known-good手順では次を実行した。

```bash
sudo systemctl mask dfx-mgr.service
systemctl is-enabled dfx-mgr.service
systemctl is-active dfx-mgr.service
```

導入前後に`masked`かつ`inactive`であることを確認する。`xmutil loadapp`で別designをロードする
運用とは併用しない。

## 5. inactive imageへのtrial update

Boot FWを実機へ転送し、host側と実機側のsize/hashが一致することを確認した後、書込み直前に
もう一度A/B状態を確認する。

```bash
sudo xmutil bootfw_status
sudo xmutil bootfw_update -i /tmp/BOOT-stage1g4-03m6-tx-frame-buffer.bin
sudo xmutil bootfw_status
```

`bootfw_update -i`は実行時点のinactive imageを更新する。元の03m-6ではinactive Image Bを更新した
が、別環境でもImage Bになるとは限らない。

更新後は、新しいimageが`Requested Boot Image`かつ未validationの`Non Bootable`、従来の
known-good imageが`Bootable`のままであることを確認する。この時点では
`xmutil bootfw_update -v`を実行しない。同じupdate commandを根拠なく再実行しない。

## 6. Physical cold boot

trial imageのbootにはwarm rebootではなく、ユーザーがKR260の電源を完全にOFF/ONするphysical
cold bootを行う。UARTでFSBL、PMUFW、TF-A、U-Boot、Linux loginまで監視する。

起動後に次を確認する。

```bash
sudo xmutil bootfw_status
systemctl is-enabled dfx-mgr.service
systemctl is-active dfx-mgr.service
```

`Last Booted Image`がtrial imageであること、`dfx-mgr.service`が`masked` / `inactive`であること、
共有FITが意図した03l artifactであることを確認する。physical cold bootはwarm rebootで代用しない。

## 7. PHY、management path、packet path

known-good実機状態は次のとおり。

- DP83867 PHY address: 2
- PHY ID: `0x2000 / 0xa231`
- Linux live DT: `phy-mode = "rgmii-id"`
- link: 1000BASE-T Full Duplex
- `RGMIICTL`: `0x00d3`
- `RGMIIDCTL`: `0x0077`
- GEM2: DP83867へのMDIO management専用
- Ethernet packet datapath: GEM2ではなくTEMAC経由

```text
DP83867 PHY / RGMII
  -> TEMAC RX
  -> RX store-and-forward frame buffer
  -> 8-to-32 packer
  -> AXI4-Stream Clock Converter
  -> 32-bit P4Fab boundary
  -> direct PL loopback
  -> 32-to-8 unpacker
  -> TX store-and-forward frame buffer
  -> TEMAC TX
  -> RGMII / DP83867 PHY
```

GEM2のGMII packet signalsはPL内でidle terminateされ、packet pathへ接続されない。TEMAC自身の
management/MDIOは無効であり、PS GEM2のEMIO MDC/MDIOがPHY managementを担当する。

元の確認ではKR260上のbus-direct MDIO toolsを使用したが、その取得・build・install手順と公開用
確認scriptは現在のrepositoryに含めていない。したがってPHY IDや拡張registerを読む具体的な
portable commandは未整備である。

## 8. Trial validation

Linux boot、03l FIT、PHY/link、MDIO readback、flat PL design、および必要なpacket試験がすべて正常と
確認できた後に限り、trial imageをvalidationする。

```bash
sudo xmutil bootfw_update -v
sudo xmutil bootfw_status
```

03m-6ではvalidation前がImage A=`Bootable`、Image B=`Non Bootable`、Requested/Last Booted=`Image
B`で、validation後はA/Bとも`Bootable`、Requested/Last Booted=`Image B`となった。このA/B文字を
他の実機へ固定的に適用せず、実行時のstatusを基準に判断する。

## 9. 失敗時

trial bootが失敗した場合はvalidationせず、known-good imageへfallbackしてUART logを保存する。
Linuxは起動するがnetwork/PHYだけ異常な場合は、共有03l FITも原因候補として扱う。slot選択を
推測で操作したり、唯一のBootable imageを上書きしたりしない。

## 10. 未整備・未確認事項

- 配布用BOOT.bin/FITと`SHA256SUMS`
- binary artifactのライセンス条件と公開方法
- EDF 26.06環境の完全な新規構築、SDT artifact生成、03k baseline FIT生成
- artifact転送、FIT backup/restore、preflightの公開用script
- bus-direct MDIO toolsの第三者向け導入・確認script
- 公開候補treeから再生成したartifactによる実機再試験
- 異なるUbuntu版、Boot FW版、carrier revisionでの適用可否
