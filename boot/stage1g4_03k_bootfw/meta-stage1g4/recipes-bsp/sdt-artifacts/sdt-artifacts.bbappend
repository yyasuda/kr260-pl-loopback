# Force every multiconfig (including the FSBL build) to consume the
# Vivado 2026.1 SDT generated from the Stage 1g-4 clock-off XSA.
FILESEXTRAPATHS:prepend := "${THISDIR}/../../../artifacts:"

SDT_URI = "file://sdt-stage1g4-txc975-usb-gem2-mdio-clkoff.tar.gz"
SDT_URI[sha256sum] = "356980008b936254d038d5957b2646462eeb112b85ebca2b7c10699c96ab8434"
SDT_URI[S] = "${WORKDIR}/sdt-gem2-j10b"
