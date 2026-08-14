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
  wifiRamName = "WIFI_RAM_CODE_MT6639_2_1.bin";
  wifiPatchName = "WIFI_MT6639_PATCH_MCU_2_1_hdr.bin";
  mt76Mt7927Rev = "fe66fdd55ccdc03dd1a44188da5a7d6946599107";
  asusBtDriverUrl = "https://dlcdnets.asus.com/pub/ASUS/mb/02BT/DRV_Bluetooth_MTK_MT7925_27_TP_W11_64_V111460576_20260417R.zip";
  asusWifiDriverUrl = "https://dlcdnets.asus.com/pub/ASUS/mb/08WIRELESS/DRV_WiFi_MTK_MT7925_27_TP_W11_64_V5705659_20260417R.zip";
  firmwareBinPath = "${firmwareDir}/${firmwareBinName}";
  wifiRamPath = "${firmwareDir}/${wifiRamName}";
  wifiPatchPath = "${firmwareDir}/${wifiPatchName}";
  firmwareDatPath = "${firmwareDir}/mtkbt.dat";
  firmwareZipPath = "${firmwareDir}/asus-bt-driver.zip";
  wifiZipPath = "${firmwareDir}/asus-wifi-driver.zip";

  firmwareBinExists = builtins.pathExists firmwareBinPath;
  wifiRamExists = builtins.pathExists wifiRamPath;
  wifiPatchExists = builtins.pathExists wifiPatchPath;
  firmwareDatExists = builtins.pathExists firmwareDatPath;
  firmwareZipExists = builtins.pathExists firmwareZipPath;
  wifiZipExists = builtins.pathExists wifiZipPath;

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

  wifiRam =
    if wifiRamExists then
      builtins.path {
        path = wifiRamPath;
        name = wifiRamName;
      }
    else
      null;

  wifiPatch =
    if wifiPatchExists then
      builtins.path {
        path = wifiPatchPath;
        name = wifiPatchName;
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
      pkgs.fetchurl {
        url = asusBtDriverUrl;
        hash = "sha256-f1nNsbpqqUcnDHrVebzI1IY/+ge4ddQSb/UMDuNkXUI=";
      };

  wifiZip =
    if wifiZipExists then
      builtins.path {
        path = wifiZipPath;
        name = "asus-wifi-driver.zip";
      }
    else
      pkgs.fetchurl {
        url = asusWifiDriverUrl;
        hash = "sha256-Tiqx9/vzewqoe7eLZbHWyEWoRF/pIedsu9beja8dRTs=";
      };

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
          "\t\tif (!skb_pull_data(data->evt_skb,\n"
          "\t\t\t\t   sizeof(wmt_evt_funcc->status))) {\n"
          "\t\t\terr = -EINVAL;\n"
          "\t\t\tgoto err_free_skb;\n"
          "\t\t}",
          "\t\tif (!skb_pull_data(data->evt_skb,\n"
          "\t\t\t\t   sizeof(wmt_evt_funcc->status))) {\n"
          "\t\t\tif (data->dev_id == 0x6639) {\n"
          "\t\t\t\tstatus = BTMTK_WMT_ON_DONE;\n"
          "\t\t\t\tbreak;\n"
          "\t\t\t}\n"
          "\t\t\terr = -EINVAL;\n"
          "\t\t\tgoto err_free_skb;\n"
          "\t\t}",
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
          "\t/* Wait a few moments for firmware activation done */\n"
          "\tusleep_range(100000, 120000);",
          "\t/* MT6639 needs longer before it answers the next WMT command. */\n"
          "\tif (dev_id == 0x6639)\n"
          "\t\tmsleep(3000);\n"
          "\telse\n"
          "\t\tusleep_range(100000, 120000);",
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

  mt7927WifiModules = pkgs.stdenv.mkDerivation {
    pname = "mt7927-wifi-modules";
    version = "2026-04-27-${lib.substring 0 7 mt76Mt7927Rev}-${kernel.version}";

    src = pkgs.fetchFromGitHub {
      owner = "morrownr";
      repo = "mt76";
      rev = mt76Mt7927Rev;
      hash = "sha256-/AyNFGXk8iZEAy9zuSHLZ5bEBGz83IASdYpLXz84xrk=";
    };

    nativeBuildInputs = kernel.moduleBuildDependencies ++ [ pkgs.bc ];

    strictDeps = true;
    enableParallelBuilding = true;
    hardeningDisable = [ "pic" ];
    dontConfigure = true;

    buildPhase = ''
      runHook preBuild

      make \
        -C "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build" \
        M="$PWD" \
        NPROC="$NIX_BUILD_CORES" \
        modules

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      installDir="$out/lib/modules/${kernel.modDirVersion}/updates/drivers/net/wireless/mediatek/mt76"
      mkdir -p "$installDir"
      find . -name '*_git.ko' -exec cp {} "$installDir/" \;

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
    else if firmwareZip != null then
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
    else if wifiZip != null then
      pkgs.runCommand "mt7927-bluetooth-firmware" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        python3 - <<'PY'
        import struct
        import zipfile
        from pathlib import Path


        with zipfile.ZipFile("${wifiZip}") as zf:
            members = [name for name in zf.namelist() if name.lower().endswith("/mtkwlan.dat") or name.lower() == "mtkwlan.dat"]
            if not members:
                raise SystemExit("mtkwlan.dat was not found in asus-wifi-driver.zip")
            data = zf.read(members[0])

        offset = 0x10
        record_size = 0x4c
        while offset + 72 <= len(data):
            name = data[offset:offset + 64].split(b"\0", 1)[0].decode("ascii", "ignore")
            if not name:
                break
            data_offset = struct.unpack_from("<I", data, offset + 64)[0]
            data_size = struct.unpack_from("<I", data, offset + 68)[0]
            if name == "${firmwareBinName}":
                if data_offset + data_size > len(data):
                    raise SystemExit(f"invalid payload range for {name}")
                Path(name).write_bytes(data[data_offset:data_offset + data_size])
                break
            offset += record_size
        else:
            raise SystemExit("${firmwareBinName} was not found in mtkwlan.dat")
        PY

        install -Dm644 \
          ${firmwareBinName} \
          $out/lib/firmware/mediatek/mt7927/${firmwareBinName}
      ''
    else
      null;

  mt7927WifiFirmware =
    if wifiRamExists && wifiPatchExists then
      pkgs.runCommandNoCC "mt7927-wifi-firmware" { } ''
        install -Dm644 \
          ${wifiRam} \
          $out/lib/firmware/mediatek/mt7927/${wifiRamName}
        install -Dm644 \
          ${wifiPatch} \
          $out/lib/firmware/mediatek/mt7927/${wifiPatchName}
      ''
    else if wifiZip != null then
      pkgs.runCommand "mt7927-wifi-firmware" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        python3 - <<'PY'
        import struct
        import zipfile
        from pathlib import Path


        required = {
            "${wifiRamName}",
            "${wifiPatchName}",
        }

        with zipfile.ZipFile("${wifiZip}") as zf:
            members = [name for name in zf.namelist() if name.lower().endswith("/mtkwlan.dat") or name.lower() == "mtkwlan.dat"]
            if not members:
                raise SystemExit("mtkwlan.dat was not found in asus-wifi-driver.zip")
            data = zf.read(members[0])

        offset = 0x10
        record_size = 0x4c
        while offset + 72 <= len(data):
            name = data[offset:offset + 64].split(b"\0", 1)[0].decode("ascii", "ignore")
            if not name:
                break
            data_offset = struct.unpack_from("<I", data, offset + 64)[0]
            data_size = struct.unpack_from("<I", data, offset + 68)[0]
            if name in required:
                if data_offset + data_size > len(data):
                    raise SystemExit(f"invalid payload range for {name}")
                Path(name).write_bytes(data[data_offset:data_offset + data_size])
            offset += record_size

        missing = [name for name in required if not Path(name).exists()]
        if missing:
            raise SystemExit(f"missing firmware in mtkwlan.dat: {', '.join(missing)}")
        PY

        install -Dm644 \
          ${wifiRamName} \
          $out/lib/firmware/mediatek/mt7927/${wifiRamName}
        install -Dm644 \
          ${wifiPatchName} \
          $out/lib/firmware/mediatek/mt7927/${wifiPatchName}
      ''
    else
      null;

  mt7927BtCheck = pkgs.writeShellScriptBin "mt7927-bt-check" ''
    set -euo pipefail

    rc=0
    fw_rel="mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin"
    wifi_ram_rel="mediatek/mt7927/WIFI_RAM_CODE_MT6639_2_1.bin"
    wifi_patch_rel="mediatek/mt7927/WIFI_MT6639_PATCH_MCU_2_1_hdr.bin"

    printf '== MT7927 Bluetooth sanity check ==\n'

    bt_usb_out="$(${pkgs.usbutils}/bin/lsusb 2>/dev/null | ${pkgs.ripgrep}/bin/rg -i '0489:|13d3:' || true)"
    if [ -n "$bt_usb_out" ]; then
      printf '[ OK ] possible MT7927 Bluetooth USB device present:\n%s\n' "$bt_usb_out"
    else
      printf '[FAIL] expected MT7927 Bluetooth USB device is not enumerated (expected 0489:* or 13d3:*)\n'
      rc=1
    fi

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

    printf '\n== MT7927 Wi-Fi status ==\n'

    wifi_pci="$(${pkgs.pciutils}/bin/lspci -Dnn -d 14c3:6639 2>/dev/null || true)"
    if [ -n "$wifi_pci" ]; then
      printf '[INFO] MT7927/MT6639 PCI device:\n%s\n' "$wifi_pci"
    else
      printf '[WARN] no 14c3:6639 Wi-Fi PCI device found\n'
    fi

    if ${pkgs.kmod}/bin/modinfo mt7925e_git 2>/dev/null | ${pkgs.ripgrep}/bin/rg -q 'pci:v000014C3d00006639'; then
      printf '[ OK ] mt7925e_git advertises the 14c3:6639 alias\n'
    elif ${pkgs.kmod}/bin/modinfo mt7925e 2>/dev/null | ${pkgs.ripgrep}/bin/rg -q 'pci:v000014C3d00006639'; then
      printf '[ OK ] mt7925e advertises the 14c3:6639 alias\n'
    else
      printf '[WARN] neither mt7925e_git nor mt7925e advertises the 14c3:6639 alias\n'
    fi

    for wifi_rel in "$wifi_ram_rel" "$wifi_patch_rel"; do
      if [ -f "/run/current-system/firmware/$wifi_rel" ] || [ -f "/run/current-system/firmware/$wifi_rel.zst" ] || [ -f "/run/current-system/firmware/$wifi_rel.xz" ] || [ -f "/lib/firmware/$wifi_rel" ] || [ -f "/lib/firmware/$wifi_rel.zst" ] || [ -f "/lib/firmware/$wifi_rel.xz" ]; then
        printf '[ OK ] Wi-Fi firmware present (%s or compressed variant)\n' "$wifi_rel"
      else
        printf '[WARN] Wi-Fi firmware missing (%s)\n' "$wifi_rel"
      fi
    done

    if [ -f "/run/current-system/firmware/$fw_rel" ] || [ -f "/run/current-system/firmware/$fw_rel.zst" ] || [ -f "/run/current-system/firmware/$fw_rel.xz" ] || [ -f "/lib/firmware/$fw_rel" ] || [ -f "/lib/firmware/$fw_rel.zst" ] || [ -f "/lib/firmware/$fw_rel.xz" ]; then
      printf '[ OK ] firmware present (%s or compressed variant)\n' "$fw_rel"
    else
      printf '[FAIL] firmware missing (%s)\n' "$fw_rel"
      rc=1
    fi

    if ${pkgs.systemd}/bin/systemctl is-active --quiet bluetooth.service; then
      printf '[ OK ] bluetooth.service is active\n'
    else
      printf '[FAIL] bluetooth.service is not active\n'
      rc=1
    fi

    adapter_out="$(${pkgs.coreutils}/bin/timeout 5 ${pkgs.bluez}/bin/bluetoothctl list 2>/dev/null || true)"
    if [ -n "$adapter_out" ]; then
      printf '[ OK ] bluetoothctl list:\n%s\n' "$adapter_out"
    else
      printf '[FAIL] bluetoothctl reported no controllers\n'
      rc=1
    fi

    printf '\n[INFO] recent kernel lines (if accessible):\n'
    if ${pkgs.util-linux}/bin/dmesg 2>/dev/null | ${pkgs.ripgrep}/bin/rg -i 'btmtk|mt7927|mt7925|6639|mt76|btusb|firmware' | ${pkgs.coreutils}/bin/tail -n 25; then
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
  boot.extraModulePackages = [
    mt7927BluetoothModules
    mt7927WifiModules
  ];

  boot.blacklistedKernelModules = [
    "mt76"
    "mt76_connac_lib"
    "mt792x_lib"
    "mt792x_usb"
    "mt7925_common"
    "mt7925e"
    "mt7925u"
  ];

  boot.extraModprobeConfig = ''
    options btusb enable_autosuspend=0
    options mt7925_common_git disable_clc=N
  '';

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  hardware.firmware =
    lib.optionals (mt7927Firmware != null) [ mt7927Firmware ]
    ++ lib.optionals (mt7927WifiFirmware != null) [ mt7927WifiFirmware ];

  environment.systemPackages = [ mt7927BtCheck ];

  systemd.services.mt7927-bluetooth-recover = {
    description = "Recover MT7927 Bluetooth controller when BlueZ sees no adapter";
    wantedBy = [ "multi-user.target" ];
    after = [
      "bluetooth.service"
      "systemd-udev-settle.service"
    ];
    wants = [ "bluetooth.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      adapter_out="$(${pkgs.coreutils}/bin/timeout 5 ${pkgs.bluez}/bin/bluetoothctl list 2>/dev/null || true)"
      if [ -n "$adapter_out" ]; then
        exit 0
      fi

      for dev in /sys/bus/usb/devices/*; do
        [ -f "$dev/idVendor" ] || continue
        [ -f "$dev/idProduct" ] || continue
        [ -w "$dev/authorized" ] || continue

        vid="$(<"$dev/idVendor")"
        pid="$(<"$dev/idProduct")"

        case "$vid:$pid" in
          0489:e13a|0489:e0fa|0489:e10f|0489:e110|0489:e116|13d3:3588)
            ${pkgs.systemd}/bin/systemctl stop bluetooth.service
            printf 0 > "$dev/authorized"
            ${pkgs.coreutils}/bin/sleep 2
            printf 1 > "$dev/authorized"
            ${pkgs.coreutils}/bin/sleep 5
            ${pkgs.systemd}/bin/systemctl start bluetooth.service
            exit 0
            ;;
        esac
      done

      exit 0
    '';
  };

  warnings = lib.optionals (mt7927Firmware == null) [
    ''
      MT7927 firmware is missing.
      Put either:
      - system/firmware/BT_RAM_CODE_MT6639_2_1_hdr.bin
      - system/firmware/mtkbt.dat
      - system/firmware/asus-bt-driver.zip
      - system/firmware/asus-wifi-driver.zip
      See system/firmware/README.md for extraction details.
    ''
  ];
}
