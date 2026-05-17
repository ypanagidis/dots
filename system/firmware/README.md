# MT7927 Bluetooth firmware

This module looks for one of these files in this directory:

- `BT_RAM_CODE_MT6639_2_1_hdr.bin` (already extracted firmware)
- `mtkbt.dat` (Windows ASUS driver payload; extracted automatically during build)
- `asus-bt-driver.zip` (full ASUS driver zip; `mtkbt.dat` is auto-detected and extracted)

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
