{
  config,
  lib,
  pkgs,
  ...
}:

let
  kernel = config.boot.kernelPackages.kernel;

  firmwareDir = toString ./firmware;
  firmwareBinName = "BT_RAM_CODE_MT6639_2_1_hdr.bin";
  firmwareBinPath = "${firmwareDir}/${firmwareBinName}";
  firmwareDatPath = "${firmwareDir}/mtkbt.dat";
  firmwareZipPath = "${firmwareDir}/asus-bt-driver.zip";

  firmwareBinExists = builtins.pathExists firmwareBinPath;
  firmwareDatExists = builtins.pathExists firmwareDatPath;
  firmwareZipExists = builtins.pathExists firmwareZipPath;

  firmwareBin =
    if firmwareBinExists then
      builtins.path {
        path = firmwareBinPath;
        name = firmwareBinName;
      }
    else
      null;

  firmwareDat =
    if firmwareDatExists then
      builtins.path {
        path = firmwareDatPath;
        name = "mtkbt.dat";
      }
    else
      null;

  firmwareZip =
    if firmwareZipExists then
      builtins.path {
        path = firmwareZipPath;
        name = "asus-bt-driver.zip";
      }
    else
      null;

  mt7927BluetoothModules = pkgs.stdenv.mkDerivation {
    pname = "mt7927-bluetooth-modules";
    version = kernel.version;

    src = kernel.src;
    setSourceRoot = ''
      sourceRoot="$(echo linux-*)"
    '';

    nativeBuildInputs = kernel.moduleBuildDependencies ++ [ pkgs.python3 ];

    strictDeps = true;
    enableParallelBuilding = true;
    hardeningDisable = [
      "pic"
      "format"
    ];
    dontConfigure = true;

    buildPhase = ''
      runHook preBuild

      mkdir -p module-src
      for f in btusb.c btmtk.c btmtk.h btrtl.c btrtl.h btintel.c btintel.h btbcm.c btbcm.h btqca.c btqca.h; do
        cp "drivers/bluetooth/$f" "module-src/$f"
      done

      python3 - <<'PY'
      from pathlib import Path


      def replace_once(path: str, old: str, new: str) -> None:
          text = Path(path).read_text()
          if old not in text:
              raise SystemExit(f"pattern not found in {path}: {old!r}")
          Path(path).write_text(text.replace(old, new, 1))


      replace_once(
          "module-src/btusb.c",
          "\t/* Additional MediaTek MT7925 Bluetooth devices */",
          "\t/* MediaTek MT7927 Bluetooth devices */\n"
          "\t{ USB_DEVICE(0x0489, 0xe13a), .driver_info = BTUSB_MEDIATEK |\n"
          "\t\t\t\t\t\t     BTUSB_WIDEBAND_SPEECH },\n"
          "\t{ USB_DEVICE(0x0489, 0xe0fa), .driver_info = BTUSB_MEDIATEK |\n"
          "\t\t\t\t\t\t     BTUSB_WIDEBAND_SPEECH },\n"
          "\t{ USB_DEVICE(0x0489, 0xe10f), .driver_info = BTUSB_MEDIATEK |\n"
          "\t\t\t\t\t\t     BTUSB_WIDEBAND_SPEECH },\n"
          "\t{ USB_DEVICE(0x0489, 0xe110), .driver_info = BTUSB_MEDIATEK |\n"
          "\t\t\t\t\t\t     BTUSB_WIDEBAND_SPEECH },\n"
          "\t{ USB_DEVICE(0x0489, 0xe116), .driver_info = BTUSB_MEDIATEK |\n"
          "\t\t\t\t\t\t     BTUSB_WIDEBAND_SPEECH },\n"
          "\t{ USB_DEVICE(0x13d3, 0x3588), .driver_info = BTUSB_MEDIATEK |\n"
          "\t\t\t\t\t\t     BTUSB_WIDEBAND_SPEECH },\n\n"
          "\t/* Additional MediaTek MT7925 Bluetooth devices */",
      )

      replace_once(
          "module-src/btmtk.h",
          "#define FIRMWARE_MT7925\t\t\"mediatek/mt7925/BT_RAM_CODE_MT7925_1_1_hdr.bin\"",
          "#define FIRMWARE_MT7925\t\t\"mediatek/mt7925/BT_RAM_CODE_MT7925_1_1_hdr.bin\"\n"
          "#define FIRMWARE_MT7927\t\t\"mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin\"",
      )

      replace_once(
          "module-src/btmtk.h",
          "\tBTMTK_ISOPKT_RUNNING,\n};",
          "\tBTMTK_ISOPKT_RUNNING,\n"
          "\tBTMTK_FIRMWARE_DL_RETRY,\n};",
      )

      replace_once(
          "module-src/btmtk.h",
          "int btmtk_setup_firmware_79xx(struct hci_dev *hdev, const char *fwname,\n"
          "\t\t\t      wmt_cmd_sync_func_t wmt_cmd_sync);",
          "int btmtk_setup_firmware_79xx(struct hci_dev *hdev, const char *fwname,\n"
          "\t\t\t      wmt_cmd_sync_func_t wmt_cmd_sync,\n"
          "\t\t\t      u32 dev_id);",
      )

      replace_once(
          "module-src/btmtk.h",
          "static inline int btmtk_setup_firmware_79xx(struct hci_dev *hdev,\n"
          "\t\t\t\t\t    const char *fwname,\n"
          "\t\t\t\t\t    wmt_cmd_sync_func_t wmt_cmd_sync)\n"
          "{\n"
          "\treturn -EOPNOTSUPP;\n"
          "}",
          "static inline int btmtk_setup_firmware_79xx(struct hci_dev *hdev,\n"
          "\t\t\t\t\t    const char *fwname,\n"
          "\t\t\t\t\t    wmt_cmd_sync_func_t wmt_cmd_sync,\n"
          "\t\t\t\t\t    u32 dev_id)\n"
          "{\n"
          "\treturn -EOPNOTSUPP;\n"
          "}",
      )

      replace_once(
          "module-src/btmtk.c",
          "#define MTK_ISO_THRESHOLD\t264",
          "#define MTK_ISO_THRESHOLD\t264\n\n"
          "static const struct {\n"
          "\tu16 vendor;\n"
          "\tu16 product;\n"
          "} btmtk_mt6639_devs[] = {\n"
          "\t{ 0x0489, 0xe13a },\n"
          "\t{ 0x0489, 0xe0fa },\n"
          "\t{ 0x0489, 0xe10f },\n"
          "\t{ 0x0489, 0xe110 },\n"
          "\t{ 0x0489, 0xe116 },\n"
          "\t{ 0x13d3, 0x3588 },\n"
          "};",
      )

      replace_once(
          "module-src/btmtk.c",
          "\tif (dev_id == 0x7925)",
          "\tif (dev_id == 0x6639)\n"
          "\t\tsnprintf(buf, size,\n"
          "\t\t\t \"mediatek/mt7927/BT_RAM_CODE_MT%04x_2_%x_hdr.bin\",\n"
          "\t\t\t dev_id & 0xffff, (fw_ver & 0xff) + 1);\n"
          "\telse if (dev_id == 0x7925)",
      )

      replace_once(
          "module-src/btmtk.c",
          "int btmtk_setup_firmware_79xx(struct hci_dev *hdev, const char *fwname,\n"
          "\t\t\t      wmt_cmd_sync_func_t wmt_cmd_sync)",
          "int btmtk_setup_firmware_79xx(struct hci_dev *hdev, const char *fwname,\n"
          "\t\t\t      wmt_cmd_sync_func_t wmt_cmd_sync,\n"
          "\t\t\t      u32 dev_id)",
      )

      replace_once(
          "module-src/btmtk.c",
          "\t\tsection_offset = le32_to_cpu(sectionmap->secoffset);\n"
          "\t\tdl_size = le32_to_cpu(sectionmap->bin_info_spec.dlsize);\n\n"
          "\t\tif (dl_size > 0) {",
          "\t\tsection_offset = le32_to_cpu(sectionmap->secoffset);\n"
          "\t\tdl_size = le32_to_cpu(sectionmap->bin_info_spec.dlsize);\n\n"
          "\t\tif (dev_id == 0x6639 && dl_size > 0 &&\n"
          "\t\t    (le32_to_cpu(sectionmap->bin_info_spec.dlmodecrctype) & 0xff) != 0x01)\n"
          "\t\t\tcontinue;\n\n"
          "\t\tif (dl_size > 0) {",
      )

      replace_once(
          "module-src/btmtk.c",
          "\t} else if (dev_id == 0x7925) {",
          "\t} else if (dev_id == 0x7925 || dev_id == 0x6639) {",
      )

      replace_once(
          "module-src/btmtk.c",
          "\tif (err < 0 || !val)\n"
          "\t\tbt_dev_err(hdev, \"Can't get device id, subsys reset fail.\");",
          "\tif (err < 0 || (!val && dev_id != 0x6639))\n"
          "\t\tbt_dev_err(hdev, \"Can't get device id, subsys reset fail.\");",
      )

      replace_once(
          "module-src/btmtk.c",
          "\tbtmtk_data->dev_id = dev_id;",
          "\tif (!dev_id) {\n"
          "\t\tu16 vid = le16_to_cpu(btmtk_data->udev->descriptor.idVendor);\n"
          "\t\tu16 pid = le16_to_cpu(btmtk_data->udev->descriptor.idProduct);\n"
          "\t\tint i;\n\n"
          "\t\tfor (i = 0; i < ARRAY_SIZE(btmtk_mt6639_devs); i++) {\n"
          "\t\t\tif (vid == btmtk_mt6639_devs[i].vendor &&\n"
          "\t\t\t    pid == btmtk_mt6639_devs[i].product) {\n"
          "\t\t\t\tdev_id = 0x6639;\n"
          "\t\t\t\tbreak;\n"
          "\t\t\t}\n"
          "\t\t}\n\n"
          "\t\tif (dev_id)\n"
          "\t\t\tbt_dev_info(hdev, \"MT6639: CHIPID=0x0000 with VID=%04x PID=%04x, using 0x6639\",\n"
          "\t\t\t\t    vid, pid);\n"
          "\t}\n\n"
          "\tbtmtk_data->dev_id = dev_id;",
      )

      replace_once(
          "module-src/btmtk.c",
          "\tcase 0x7922:\n\tcase 0x7925:\n\tcase 0x7961:",
          "\tcase 0x7922:\n\tcase 0x7925:\n\tcase 0x6639:\n\tcase 0x7961:",
      )

      replace_once(
          "module-src/btmtk.c",
          "btmtk_usb_hci_wmt_sync);",
          "btmtk_usb_hci_wmt_sync, dev_id);",
      )

      replace_once(
          "module-src/btmtk.c",
          "\t\tif (err < 0) {\n"
          "\t\t\tbt_dev_err(hdev, \"Failed to set up firmware (%d)\", err);\n"
          "\t\t\treturn err;\n"
          "\t\t}",
          "\t\tif (err < 0) {\n"
          "\t\t\tif (!test_and_set_bit(BTMTK_FIRMWARE_DL_RETRY, &btmtk_data->flags))\n"
          "\t\t\t\tbtmtk_reset_sync(hdev);\n"
          "\t\t\tbt_dev_err(hdev, \"Failed to set up firmware (%d)\", err);\n"
          "\t\t\treturn err;\n"
          "\t\t}",
      )

      replace_once(
          "module-src/btmtk.c",
          "\t\thci_set_msft_opcode(hdev, 0xFD30);\n"
          "\t\thci_set_aosp_capable(hdev);\n\n"
          "\t\t/* Set up ISO interface after protocol enabled */",
          "\t\thci_set_msft_opcode(hdev, 0xFD30);\n"
          "\t\thci_set_aosp_capable(hdev);\n\n"
          "\t\ttest_and_clear_bit(BTMTK_FIRMWARE_DL_RETRY, &btmtk_data->flags);\n\n"
          "\t\t/* Set up ISO interface after protocol enabled */",
      )

      replace_once(
          "module-src/btmtk.c",
          "\terr = usb_set_interface(btmtk_data->udev, MTK_ISO_IFNUM, 1);",
          "\terr = usb_set_interface(btmtk_data->udev, MTK_ISO_IFNUM,\n"
          "\t\t\t       (intf->num_altsetting > 1) ? 1 : 0);",
      )

      replace_once(
          "module-src/btmtk.c",
          "MODULE_FIRMWARE(FIRMWARE_MT7925);",
          "MODULE_FIRMWARE(FIRMWARE_MT7925);\n"
          "MODULE_FIRMWARE(FIRMWARE_MT7927);",
      )
      PY

      cat > module-src/Makefile <<'EOF'
      obj-m += btusb.o btmtk.o btrtl.o btintel.o btbcm.o btqca.o
      EOF

      make \
        -C "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build" \
        M="$PWD/module-src" \
        modules

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      installDir="$out/lib/modules/${kernel.modDirVersion}/updates/drivers/bluetooth"
      mkdir -p "$installDir"
      cp module-src/*.ko "$installDir/"

      runHook postInstall
    '';
  };

  mt7927Firmware =
    if firmwareBinExists then
      pkgs.runCommandNoCC "mt7927-bluetooth-firmware" { } ''
        install -Dm644 \
          ${firmwareBin} \
          $out/lib/firmware/mediatek/mt7927/${firmwareBinName}
      ''
    else if firmwareDatExists then
      pkgs.runCommand "mt7927-bluetooth-firmware" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        python3 - <<'PY'
        import struct
        from pathlib import Path

        data = Path("${firmwareDat}").read_bytes()
        offset = 0x10
        data_offset = struct.unpack_from("<I", data, offset + 64)[0]
        data_size = struct.unpack_from("<I", data, offset + 68)[0]
        fw = data[data_offset:data_offset + data_size]
        Path("BT_RAM_CODE_MT6639_2_1_hdr.bin").write_bytes(fw)
        PY

        install -Dm644 \
          BT_RAM_CODE_MT6639_2_1_hdr.bin \
          $out/lib/firmware/mediatek/mt7927/${firmwareBinName}
      ''
    else if firmwareZipExists then
      pkgs.runCommand "mt7927-bluetooth-firmware" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        python3 - <<'PY'
        import struct
        import zipfile
        from pathlib import Path


        with zipfile.ZipFile("${firmwareZip}") as zf:
            members = [name for name in zf.namelist() if name.lower().endswith("/mtkbt.dat") or name.lower() == "mtkbt.dat"]
            if not members:
                raise SystemExit("mtkbt.dat was not found in asus-bt-driver.zip")
            data = zf.read(members[0])

        offset = 0x10
        data_offset = struct.unpack_from("<I", data, offset + 64)[0]
        data_size = struct.unpack_from("<I", data, offset + 68)[0]
        fw = data[data_offset:data_offset + data_size]
        Path("BT_RAM_CODE_MT6639_2_1_hdr.bin").write_bytes(fw)
        PY

        install -Dm644 \
          BT_RAM_CODE_MT6639_2_1_hdr.bin \
          $out/lib/firmware/mediatek/mt7927/${firmwareBinName}
      ''
    else
      null;

  mt7927BtCheck = pkgs.writeShellScriptBin "mt7927-bt-check" ''
    set -euo pipefail

    rc=0
    fw_rel="mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin"

    printf '== MT7927 Bluetooth sanity check ==\n'

    btusb_path="$(${pkgs.kmod}/bin/modinfo -n btusb 2>/dev/null || true)"
    if [ -z "$btusb_path" ]; then
      printf '[FAIL] btusb module metadata not found\n'
      rc=1
    else
      printf '[INFO] btusb path: %s\n' "$btusb_path"
      if printf '%s' "$btusb_path" | ${pkgs.ripgrep}/bin/rg -q '/updates/drivers/bluetooth/'; then
        printf '[ OK ] patched btusb override is active\n'
      else
        printf '[WARN] btusb does not appear to come from updates/ override\n'
        rc=1
      fi
    fi

    if [ -f "/run/current-system/firmware/$fw_rel" ] || [ -f "/run/current-system/firmware/$fw_rel.zst" ] || [ -f "/run/current-system/firmware/$fw_rel.xz" ] || [ -f "/lib/firmware/$fw_rel" ] || [ -f "/lib/firmware/$fw_rel.zst" ] || [ -f "/lib/firmware/$fw_rel.xz" ]; then
      printf '[ OK ] firmware present (%s or compressed variant)\n' "$fw_rel"
    else
      printf '[FAIL] firmware missing (%s)\n' "$fw_rel"
      rc=1
    fi

    if ${pkgs.systemd}/bin/systemctl is-active --quiet bluetooth.service; then
      printf '[ OK ] bluetooth.service is active\n'
    else
      printf '[WARN] bluetooth.service is not active\n'
    fi

    adapter_out="$(${pkgs.coreutils}/bin/timeout 5 ${pkgs.bluez}/bin/bluetoothctl list 2>/dev/null || true)"
    if [ -n "$adapter_out" ]; then
      printf '[ OK ] bluetoothctl list:\n%s\n' "$adapter_out"
    else
      printf '[WARN] bluetoothctl reported no controllers\n'
    fi

    printf '\n[INFO] recent kernel lines (if accessible):\n'
    if ${pkgs.util-linux}/bin/dmesg 2>/dev/null | ${pkgs.ripgrep}/bin/rg -i 'btmtk|mt7927|6639|btusb' | ${pkgs.coreutils}/bin/tail -n 25; then
      :
    else
      printf 'dmesg not accessible or no matching lines\n'
    fi

    if [ "$rc" -eq 0 ]; then
      printf '\nAll critical checks passed.\n'
    else
      printf '\nOne or more critical checks failed.\n'
    fi

    exit "$rc"
  '';
in
{
  boot.extraModulePackages = [ mt7927BluetoothModules ];

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  hardware.firmware = lib.optionals (mt7927Firmware != null) [ mt7927Firmware ];

  environment.systemPackages = [ mt7927BtCheck ];

  warnings = lib.optionals (mt7927Firmware == null) [
    ''
      MT7927 firmware is missing.
      Put either:
      - system/firmware/BT_RAM_CODE_MT6639_2_1_hdr.bin
      - system/firmware/mtkbt.dat
      - system/firmware/asus-bt-driver.zip
      See system/firmware/README.md for extraction details.
    ''
  ];
}
