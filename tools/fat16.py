"""
fat16.py - Tool to list, put, and get files directly on a FAT16 raw MBR disk image.
"""
import sys
import os
import struct
import time

def parse_fs(f):
    f.seek(0)
    mbr = f.read(512)
    if mbr[510:512] != b'\x55\xaa':
        raise ValueError("Invalid MBR signature")
    
    # Read first partition
    part = mbr[446:462]
    status, chs1, ptype, chs2, lba_start, num_sectors = struct.unpack_from('<B3sB3sII', part)
    
    # Read VBR
    f.seek(lba_start * 512)
    vbr = f.read(512)
    bps, spc, res_sec, fats, root_entries, total_sec16, media, spf = struct.unpack_from('<HBHBHHBH', vbr, 11)
    
    fat1_offset = (lba_start + res_sec) * bps
    fat2_offset = fat1_offset + spf * bps
    root_offset = (lba_start + res_sec + fats * spf) * bps
    root_size = root_entries * 32
    data_offset = root_offset + root_size
    cluster_size = spc * bps
    
    return {
        'bps': bps,
        'spc': spc,
        'spf': spf,
        'fats': fats,
        'root_entries': root_entries,
        'fat1_offset': fat1_offset,
        'fat2_offset': fat2_offset,
        'root_offset': root_offset,
        'data_offset': data_offset,
        'cluster_size': cluster_size
    }

def list_files(img_path):
    with open(img_path, 'rb') as f:
        fs = parse_fs(f)
        f.seek(fs['root_offset'])
        root_data = f.read(fs['root_entries'] * 32)
        
        entries = []
        for i in range(fs['root_entries']):
            e = root_data[i*32:(i+1)*32]
            if e[0] == 0x00:
                break
            if e[0] == 0xE5:
                continue
            name = e[:8].decode('latin1', errors='ignore').strip()
            ext = e[8:11].decode('latin1', errors='ignore').strip()
            attr = e[11]
            cluster, size = struct.unpack_from('<HI', e, 26)
            full_name = f"{name}.{ext}" if ext else name
            entries.append((full_name, size, cluster, attr))
            print(f"{full_name:12}  {size:10} bytes  cluster {cluster:5}  attr {hex(attr)}")
        return entries

def put_file(img_path, host_path, dos_name):
    with open(host_path, 'rb') as hf:
        data = hf.read()
    
    file_size = len(data)
    
    # Format 8.3 filename
    base, ext = os.path.splitext(dos_name.upper())
    ext = ext.lstrip('.')[:3]
    base = base[:8]
    dos_83 = base.ljust(8) + ext.ljust(3)
    
    with open(img_path, 'r+b') as f:
        fs = parse_fs(f)
        
        # Read FAT1
        f.seek(fs['fat1_offset'])
        fat_data = bytearray(f.read(fs['spf'] * fs['bps']))
        
        # Read root dir
        f.seek(fs['root_offset'])
        root_data = bytearray(f.read(fs['root_entries'] * 32))
        
        # Calculate needed clusters
        cluster_size = fs['cluster_size']
        num_clusters = (file_size + cluster_size - 1) // cluster_size
        if num_clusters == 0:
            num_clusters = 1 # at least 1 cluster for non-empty or empty
        
        # Find free clusters in FAT16 (each entry is 2 bytes, free = 0x0000)
        free_clusters = []
        total_clusters = len(fat_data) // 2
        for c in range(2, total_clusters):
            entry_val = struct.unpack_from('<H', fat_data, c * 2)[0]
            if entry_val == 0x0000:
                free_clusters.append(c)
                if len(free_clusters) == num_clusters:
                    break
        
        if len(free_clusters) < num_clusters:
            raise RuntimeError("Not enough free space on FAT16 disk!")
        
        # Link clusters in FAT
        for idx in range(len(free_clusters)):
            c = free_clusters[idx]
            if idx == len(free_clusters) - 1:
                next_val = 0xFFFF # EOF
            else:
                next_val = free_clusters[idx + 1]
            struct.pack_into('<H', fat_data, c * 2, next_val)
        
        # Write file data into clusters
        for idx in range(len(free_clusters)):
            c = free_clusters[idx]
            chunk = data[idx * cluster_size : (idx + 1) * cluster_size]
            if len(chunk) < cluster_size:
                chunk = chunk + b'\x00' * (cluster_size - len(chunk))
            
            cluster_offset = fs['data_offset'] + (c - 2) * cluster_size
            f.seek(cluster_offset)
            f.write(chunk)
        
        # Write updated FAT1 and FAT2
        f.seek(fs['fat1_offset'])
        f.write(fat_data)
        f.seek(fs['fat2_offset'])
        f.write(fat_data)
        
        # Find free root directory entry or overwrite existing with same name
        target_idx = None
        for i in range(fs['root_entries']):
            e = root_data[i*32:(i+1)*32]
            if e[0] == 0x00 or e[0] == 0xE5:
                if target_idx is None:
                    target_idx = i
                if e[0] == 0x00:
                    break
            elif e[:11].decode('latin1', errors='ignore') == dos_83:
                target_idx = i
                break
        
        if target_idx is None:
            raise RuntimeError("Root directory is full!")
        
        # Time / Date in DOS format
        now = time.localtime()
        dos_time = (now.tm_hour << 11) | (now.tm_min << 5) | (now.tm_sec // 2)
        dos_date = ((now.tm_year - 1980) << 9) | (now.tm_mon << 5) | now.tm_mday
        
        # 32-byte dir entry:
        # 0..10: name (11 bytes)
        # 11: attr (0x20 = Archive)
        # 12..21: reserved (10 bytes)
        # 22..23: time (2 bytes)
        # 24..25: date (2 bytes)
        # 26..27: starting cluster (2 bytes)
        # 28..31: file size (4 bytes)
        entry = struct.pack('<11sB10sHHHI',
            dos_83.encode('ascii'),
            0x20, # Archive
            b'\x00' * 10,
            dos_time,
            dos_date,
            free_clusters[0],
            file_size
        )
        
        f.seek(fs['root_offset'] + target_idx * 32)
        f.write(entry)
        
        print(f"Successfully injected '{dos_name}' ({file_size} bytes, starting cluster {free_clusters[0]}) into {img_path}")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage:")
        print("  python fat16.py list <disk.img>")
        print("  python fat16.py put <disk.img> <host_file> <dos_name>")
        sys.exit(1)
    
    cmd = sys.argv[1].lower()
    if cmd == 'list':
        list_files(sys.argv[2])
    elif cmd == 'put':
        put_file(sys.argv[2], sys.argv[3], sys.argv[4])
