"""Protocol-level USB relay test against a fake Apple device service (no phone needed)."""
import pathlib
import plistlib
import socket
import struct
import subprocess
import threading
import time

def exact(sock, count):
    result = b''
    while len(result) < count:
        data = sock.recv(count - len(result))
        if not data:
            raise EOFError()
        result += data
    return result

def request(sock):
    size, version, message, tag = struct.unpack('<IIII', exact(sock, 16))
    assert version == 1 and message == 8
    return plistlib.loads(exact(sock, size - 16))

def response(sock, value):
    body = plistlib.dumps(value)
    packet = struct.pack('<IIII', len(body) + 16, 1, 8, 1) + body
    # Exercise reads that do not receive an entire packet at once.
    sock.sendall(packet[:7]); sock.sendall(packet[7:])

service = socket.socket()
service.bind(('127.0.0.1', 0)); service.listen()
service.settimeout(0.2)
online = threading.Event(); online.set()
stopped = threading.Event()
failures = []

def handle(sock):
    with sock:
        try:
            value = request(sock)
            if value['MessageType'] == 'ListDevices':
                response(sock, {'DeviceList': [{'DeviceID': 7, 'Properties': {'ConnectionType': 'USB', 'SerialNumber': 'TEST'}}] if online.is_set() else []})
            else:
                assert value['MessageType'] == 'Connect' and value['DeviceID'] == 7
                assert value['PortNumber'] == socket.htons(8080)
                response(sock, {'Number': 0})
                data = b''
                while b'\r\n\r\n' not in data:
                    chunk = sock.recv(4096)
                    if not chunk:
                        return
                    data += chunk
                assert b'/status?token=test' in data
                sock.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK')
        except (EOFError, ConnectionError):
            pass
        except Exception as exc:
            failures.append(str(exc))

def serve():
    while not stopped.is_set():
        try:
            sock, _ = service.accept()
        except socket.timeout:
            continue
        except OSError:
            if stopped.is_set(): return
            raise
        threading.Thread(target=handle, args=(sock,), daemon=True).start()

threading.Thread(target=serve, daemon=True).start()
reserve = socket.socket(); reserve.bind(('127.0.0.1', 0)); port = reserve.getsockname()[1]; reserve.close()
script = pathlib.Path(__file__).with_name('Run-Bridge.ps1')
process = subprocess.Popen(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script), '-LocalPort', str(port), '-MuxPort', str(service.getsockname()[1])], creationflags=subprocess.CREATE_NO_WINDOW, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
try:
    for attempt in range(100):
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=.2):
                break
        except OSError:
            if process.poll() is not None:
                raise RuntimeError(process.communicate())
            time.sleep(.1)
    def get():
        with socket.create_connection(('127.0.0.1', port), timeout=5) as client:
            client.sendall(b'GET /status?token=test HTTP/1.1\r\nHost: localhost\r\n\r\n')
            result = b''
            while True:
                try:
                    data = client.recv(4096)
                except ConnectionResetError:
                    break
                if not data: break
                result += data
            return result
    assert get().endswith(b'OK')
    online.clear()
    offline = get()
    assert b'503 Service Unavailable' in offline, offline
    online.set()
    assert get().endswith(b'OK')
    assert not failures, failures
    print('PASS: USB handshake, bidirectional HTTP forwarding, unplug handling, and reconnect')
finally:
    process.terminate(); process.wait(timeout=5)
    stopped.set(); service.close()

