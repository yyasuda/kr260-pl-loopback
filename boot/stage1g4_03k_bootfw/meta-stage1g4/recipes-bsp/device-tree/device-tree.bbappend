FILESEXTRAPATHS:prepend := "${THISDIR}/files:${THISDIR}/../../../artifacts:"

# Keep BOOT manifest SDT provenance aligned with the custom sdt-artifacts
# provider selected by this layer.
SDT_URI = "file://sdt-stage1g4-txc975-usb-gem2-mdio-clkoff.tar.gz"
SDT_URI[sha256sum] = "356980008b936254d038d5957b2646462eeb112b85ebca2b7c10699c96ab8434"
SDT_URI[S] = "${WORKDIR}/sdt-gem2-j10b"

python __anonymous () {
    machine = d.getVar("MACHINE")
    mc = d.getVar("BB_CURRENT_MC")

    if (machine == "k26-smk-kr-sdt-multidomain" and
            mc == "k26-smk-kr-sdt-multidomain-cortexa53-fsbl"):
        d.appendVar("SRC_URI", " file://0001-k26-kr260-fsbl-assign-gem2-to-a53.patch")
}
