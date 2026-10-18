"""
host_bridge.py - InquiBench Host Serial Bridge
Communicates with the InquiBench guest daemon over Named Pipes (86Box) or physical COM ports.
"""

import sys
import os
import time
import struct
import argparse
import ctypes
from ctypes import wintypes

# Win32 API constants for Named Pipe
GENERIC_READ = 0x80000000
GENERIC_WRITE = 0x40000000
OPEN_EXISTING = 3
FILE_ATTRIBUTE_NORMAL = 0x80

kernel32 = ctypes.windll.kernel32

class PipeTransport:
    def __init__(self, pipe_name):
        self.pipe_name = pipe_name
        self.handle = None

    def connect(self, timeout_sec=5.0):
        start = time.time()
        while time.time() - start < timeout_sec:
            # Wait for pipe instance to be available
            kernel32.WaitNamedPipeW(self.pipe_name, 500)
            self.handle = kernel32.CreateFileW(
                self.pipe_name,
                GENERIC_READ | GENERIC_WRITE,
                0,
                None,
                OPEN_EXISTING,
                FILE_ATTRIBUTE_NORMAL,
                None
            )
            if self.handle != -1 and self.handle != 0:
                return True
            time.sleep(0.2)
        err = kernel32.GetLastError()
        raise ConnectionError(f"Could not connect to pipe {self.pipe_name} (Win32 error: {err})")

    def write(self, data: bytes):
        written = wintypes.DWORD()
        res = kernel32.WriteFile(self.handle, data, len(data), ctypes.byref(written), None)
        if not res:
            raise IOError(f"WriteFile failed (Error {kernel32.GetLastError()})")
        return written.value

    def read(self, num_bytes: int, timeout_sec=3.0) -> bytes:
        result = bytearray()
        start = time.time()
        buf = (ctypes.c_ubyte * num_bytes)()
        read_count = wintypes.DWORD()
        
        while len(result) < num_bytes:
            to_read = num_bytes - len(result)
            res = kernel32.ReadFile(self.handle, buf, to_read, ctypes.byref(read_count), None)
            if res and read_count.value > 0:
                result.extend(bytes(buf[:read_count.value]))
            else:
                if time.time() - start > timeout_sec:
                    break
                time.sleep(0.01)
        return bytes(result)

    def close(self):
        if self.handle and self.handle != -1:
            kernel32.CloseHandle(self.handle)
            self.handle = None


class SerialTransport:
    def __init__(self, port, baudrate=115200):
        import serial
        self.port = port
        self.baudrate = baudrate
        self.ser = None

    def connect(self, timeout_sec=2.0):
        import serial
        self.ser = serial.Serial(self.port, self.baudrate, timeout=timeout_sec)
        return True

    def write(self, data: bytes):
        return self.ser.write(data)

    def read(self, num_bytes: int, timeout_sec=3.0) -> bytes:
        self.ser.timeout = timeout_sec
        return self.ser.read(num_bytes)

    def close(self):
        if self.ser:
            self.ser.close()
            self.ser = None


class DOSSerialBridge:
    SYNC_BYTES = b'\x55\xAA'
    
    CMD_PING        = 0x01
    CMD_EXEC        = 0x02
    CMD_READ_SCREEN = 0x03
    CMD_SEND_KEY    = 0x04
    CMD_PUT_FILE    = 0x05
    CMD_QUIT        = 0xFF
    
    ACK_OK          = 0x80
    ACK_PONG        = 0x81
    ACK_EXEC        = 0x82
    ACK_SCREEN      = 0x83
    ACK_ERR         = 0xE0

    def __init__(self, endpoint=r'\\.\pipe\86box_serial', baudrate=115200):
        self.endpoint = endpoint
        self.baudrate = baudrate
        if endpoint.lower().startswith(r'\\.\pipe'):
            self.transport = PipeTransport(endpoint)
        else:
            self.transport = SerialTransport(endpoint, baudrate)

    def connect(self):
        return self.transport.connect()

    def close(self):
        self.transport.close()

    def _send_packet(self, cmd: int, payload: bytes = b''):
        header = self.SYNC_BYTES + struct.pack('<BH', cmd, len(payload))
        self.transport.write(header + payload)

    def _recv_packet(self, timeout_sec=5.0):
        # Look for sync bytes
        start = time.time()
        while time.time() - start < timeout_sec:
            b1 = self.transport.read(1, timeout_sec=0.5)
            if b1 == b'\x55':
                b2 = self.transport.read(1, timeout_sec=0.5)
                if b2 == b'\xAA':
                    break
        else:
            raise TimeoutError("Timeout waiting for response sync bytes (0x55 0xAA)")

        hdr = self.transport.read(3, timeout_sec=timeout_sec)
        if len(hdr) < 3:
            raise TimeoutError("Incomplete response header")
        
        ack_cmd, payload_len = struct.unpack('<BH', hdr)
        payload = b''
        if payload_len > 0:
            payload = self.transport.read(payload_len, timeout_sec=timeout_sec)
            if len(payload) < payload_len:
                raise TimeoutError(f"Incomplete payload: expected {payload_len}, got {len(payload)}")
        
        return ack_cmd, payload

    def ping(self) -> str:
        self._send_packet(self.CMD_PING)
        ack_cmd, payload = self._recv_packet(timeout_sec=3.0)
        if ack_cmd == self.ACK_PONG:
            return payload.decode('latin1', errors='replace')
        raise RuntimeError(f"Unexpected ping response: {hex(ack_cmd)}")

    def exec(self, command: str, timeout_sec=15.0) -> str:
        payload = command.encode('ascii', errors='replace') + b'\x00'
        self._send_packet(self.CMD_EXEC, payload)
        ack_cmd, payload = self._recv_packet(timeout_sec=timeout_sec)
        if ack_cmd == self.ACK_EXEC:
            return payload.decode('cp437', errors='replace')
        raise RuntimeError(f"Command execution failed (ACK: {hex(ack_cmd)})")

    def read_screen(self) -> str:
        """Reads 80x25 text screen from VRAM and returns 25 lines of text."""
        self._send_packet(self.CMD_READ_SCREEN)
        ack_cmd, payload = self._recv_packet(timeout_sec=4.0)
        if ack_cmd != self.ACK_SCREEN or len(payload) < 4000:
            raise RuntimeError(f"Failed to read screen (ACK: {hex(ack_cmd)}, len: {len(payload)})")
        
        # 4000 bytes = 80 chars * 25 lines * 2 bytes (ASCII, Attribute)
        lines = []
        for row in range(25):
            line_chars = []
            for col in range(80):
                offset = (row * 80 + col) * 2
                char_byte = payload[offset]
                # Convert CP437 byte to displayable character
                line_chars.append(bytes([char_byte]).decode('cp437', errors='replace'))
            lines.append("".join(line_chars).rstrip())
        return "\n".join(lines)

    def send_key(self, ascii_char: str, scancode: int = 0):
        ascii_byte = ord(ascii_char) if ascii_char else 0
        payload = struct.pack('<BB', ascii_byte, scancode)
        self._send_packet(self.CMD_SEND_KEY, payload)
        ack_cmd, _ = self._recv_packet(timeout_sec=2.0)
        return ack_cmd == self.ACK_OK

    def put_file(self, local_path: str, remote_name: str):
        with open(local_path, 'rb') as f:
            data = f.read()
        payload = remote_name.encode('ascii') + b'\x00' + data
        self._send_packet(self.CMD_PUT_FILE, payload)
        ack_cmd, _ = self._recv_packet(timeout_sec=10.0)
        if ack_cmd != self.ACK_OK:
            raise RuntimeError(f"Failed to upload file (ACK: {hex(ack_cmd)})")
        return True

    def quit(self):
        try:
            self._send_packet(self.CMD_QUIT)
        except Exception:
            pass


def main():
    parser = argparse.ArgumentParser(description="DOS Serial Bridge Client")
    parser.add_argument('--endpoint', default=r'\\.\pipe\86box_serial', help='Named Pipe or COM port (e.g. COM3)')
    parser.add_argument('--baud', type=int, default=115200, help='Baud rate')
    subparsers = parser.add_subparsers(dest='action', required=True)

    subparsers.add_parser('ping', help='Send PING to DOS agent')
    
    exec_p = subparsers.add_parser('exec', help='Execute DOS command and print output')
    exec_p.add_argument('cmd', help='Command string to execute (e.g. "DIR C:")')

    subparsers.add_parser('screen', help='Dump 80x25 text screen from VRAM')

    put_p = subparsers.add_parser('put', help='Upload file to DOS')
    put_p.add_argument('local_path', help='Local file path')
    put_p.add_argument('remote_name', help='Remote DOS file path (e.g. D:\\TEST.TXT)')

    subparsers.add_parser('shell', help='Interactive DOS remote shell')

    args = parser.parse_args()

    bridge = DOSSerialBridge(endpoint=args.endpoint, baudrate=args.baud)
    print(f"Connecting to {args.endpoint}...")
    bridge.connect()
    print("Connected!")

    try:
        if args.action == 'ping':
            resp = bridge.ping()
            print(f"[+] Response: {resp}")

        elif args.action == 'exec':
            out = bridge.exec(args.cmd)
            print(out)

        elif args.action == 'screen':
            screen = bridge.read_screen()
            print("=" * 80)
            print(screen)
            print("=" * 80)

        elif args.action == 'put':
            bridge.put_file(args.local_path, args.remote_name)
            print(f"[+] File {args.local_path} uploaded as {args.remote_name}")

        elif args.action == 'shell':
            print("=== Remote DOS Shell (type 'exit' to quit) ===")
            bridge.ping()
            while True:
                try:
                    cmd = input("DOS> ").strip()
                    if not cmd:
                        continue
                    if cmd.lower() in ['exit', 'quit']:
                        break
                    if cmd.lower() == 'screen':
                        print(bridge.read_screen())
                        continue
                    print(bridge.exec(cmd))
                except KeyboardInterrupt:
                    break
    finally:
        bridge.close()

if __name__ == '__main__':
    main()
