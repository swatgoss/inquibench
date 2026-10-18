import sys
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
from host_bridge import DOSSerialBridge

print("Connecting to DOS serial bridge (\\.\\pipe\\86box_serial)...")
b = DOSSerialBridge()
b.connect()
print("[+] Connected to pipe!\n")

print("=== 1. Test PING ===")
pong = b.ping()
print(f"[+] Pong: {pong}\n")

print("=== 2. Test EXEC 'VER' ===")
ver_out = b.exec("VER")
print(ver_out.strip())
print()

print("=== 3. Test EXEC 'DIR D:\\' ===")
dir_out = b.exec("DIR D:\\")
print(dir_out.strip())
print()

print("=== 4. Test READ SCREEN (Live VRAM) ===")
screen = b.read_screen()
print(screen)

b.close()
print("\n[+] All tests completed successfully!")
