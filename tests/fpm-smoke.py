#!/usr/bin/env python3
import socket
import struct
import sys
import time

port = int(sys.argv[1])
version = sys.argv[2]


def record(kind, data=b""):
    padding = -len(data) % 8
    return struct.pack("!BBHHBB", 1, kind, 1, len(data), padding, 0) + data + b"\0" * padding


def parameter(name, value):
    name, value = name.encode(), value.encode()
    return bytes((len(name), len(value))) + name + value


def receive(sock, size):
    result = b""
    while len(result) < size:
        block = sock.recv(size - len(result))
        if not block:
            raise RuntimeError("premature FastCGI EOF")
        result += block
    return result


params = b"".join(parameter(k, v) for k, v in {
    "SCRIPT_FILENAME": "/var/www/html/index.php",
    "SCRIPT_NAME": "/index.php",
    "REQUEST_METHOD": "GET",
    "SERVER_PROTOCOL": "HTTP/1.1",
    "SERVER_NAME": "localhost",
}.items())

for attempt in range(10):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=10) as sock:
            sock.sendall(record(1, struct.pack("!HB5x", 1, 0)) +
                         record(4, params) + record(4) + record(5))
            output = b""
            while True:
                _, kind, _, size, padding, _ = struct.unpack("!BBHHBB", receive(sock, 8))
                data = receive(sock, size)
                receive(sock, padding)
                if kind == 6:
                    output += data
                elif kind == 7:
                    print(data.decode(errors="replace"), file=sys.stderr)
                elif kind == 3:
                    break
        break
    except (ConnectionRefusedError, ConnectionResetError, BrokenPipeError):
        if attempt == 9:
            raise
        time.sleep(1)

if b"Status:" in output and b"Status: 200" not in output:
    raise RuntimeError(output)
if ("filc-fpm-ok " + version).encode() not in output:
    raise RuntimeError(output)
print(output.decode(errors="replace").strip())
