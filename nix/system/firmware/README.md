# MT7927 Bluetooth firmware

This module fetches the current ASUS driver archives by URL and hash. It can
also use one of these local files when the file is visible to Nix evaluation:

- `BT_RAM_CODE_MT6639_2_1_hdr.bin` (already extracted firmware)
- `WIFI_RAM_CODE_MT6639_2_1.bin` and `WIFI_MT6639_PATCH_MCU_2_1_hdr.bin`
  (already extracted Wi-Fi firmware)
- `mtkbt.dat` (Windows ASUS driver payload; extracted automatically during build)
- `asus-bt-driver.zip` (full ASUS driver zip; `mtkbt.dat` is auto-detected and extracted)
- `asus-wifi-driver.zip` (full ASUS Wi-Fi driver zip; MT6639 Bluetooth/Wi-Fi
  payloads are auto-detected and extracted)

Current ASUS ProArt X870E-CREATOR WIFI downloads:

- Bluetooth: `MTK Bluetooth Driver V1.1146.0.576`, `2026/04/20`,
  `DRV_Bluetooth_MTK_MT7925_27_TP_W11_64_V111460576_20260417R.zip`,
  SHA-256 `7F59CDB1BA6AA947270C7AD579BCC8D4863FFA07B875D4126FF50C0EE3645D42`.
- Wi-Fi: `MTK WiFi Driver V5.7.0.5659`, `2026/04/20`,
  `DRV_WiFi_MTK_MT7925_27_TP_W11_64_V5705659_20260417R.zip`,
  SHA-256 `4E2AB1F7FBF37B0AA87BB78B65B1D6C845A8445FE921E76CBBD6DE8DAF1D453B`.

The Wi-Fi firmware is paired with an out-of-tree `morrownr/mt76` test branch
until MT7927 support lands in the kernel used here. The branch is
`series/mt7927-v5-1085548`, pinned at
`fe66fdd55ccdc03dd1a44188da5a7d6946599107`. It carries the v5 MT7927 series
and builds `mt7925e_git`, which advertises the `14c3:6639` PCI alias used by
this board.

Known status on this ProArt X870E-CREATOR WIFI: Wi-Fi works with that branch
and the MT6639 Wi-Fi firmware. Bluetooth also works with the local `btusb` /
`btmtk` override and the ASUS `BT_RAM_CODE_MT6639_2_1_hdr.bin` firmware. If
`mt7927-bt-check` reports no `0489:*` or `13d3:*` USB device after switching to
this setup, do a full power cycle; a warm reboot can leave the Bluetooth USB
function unenumerated.

If you only have `mtkbt.dat`, extract manually with:

```bash
python3 -c "
import struct
data = open('mtkbt.dat', 'rb').read()
offset = 0x10
data_offset = struct.unpack_from('<I', data, offset + 64)[0]
data_size = struct.unpack_from('<I', data, offset + 68)[0]
fw = data[data_offset:data_offset + data_size]
open('BT_RAM_CODE_MT6639_2_1_hdr.bin', 'wb').write(fw)
print(f'Extracted {len(fw)} bytes')
"
```

The source `mtkbt.dat` file is typically in the ASUS Bluetooth driver archive under `BT/`.

After `nixos-rebuild switch`, run:

```bash
mt7927-bt-check
```

This verifies module override, firmware presence, service state, adapter visibility, and recent kernel logs.
