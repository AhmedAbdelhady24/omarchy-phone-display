"""Probe a running local WayVNC without requesting frames or sending input.

Usage: python3 tests/probe_vnc_auth.py /path/to/private/wayvnc.conf
Only the owner should run this; the config contains the session password.
"""
from pathlib import Path
import socket
import ssl
import struct
import sys


def receive(sock, count):
    data = b""
    while len(data) < count:
        chunk = sock.recv(count - len(data))
        if not chunk:
            raise ConnectionError("Server closed the handshake")
        data += chunk
    return data


def greeting(sock):
    assert receive(sock, 12) == b"RFB 003.008\n"
    sock.sendall(b"RFB 003.008\n")
    count = receive(sock, 1)[0]
    assert count > 0, "Server offers no security types"
    types = receive(sock, count)
    assert 1 not in types, "Unauthenticated access is offered"
    assert 2 not in types, "Legacy DES authentication is offered"
    assert 30 not in types, "Unencrypted Apple DH authentication is offered"
    assert 19 in types, "VeNCrypt is not offered"


def authenticate(config, username, password):
    context = ssl.create_default_context(cafile=config["certificate_file"])
    with socket.create_connection(("127.0.0.1", 5900), timeout=5) as sock:
        greeting(sock)
        sock.sendall(bytes([19]))
        assert receive(sock, 2) == b"\x00\x02"
        sock.sendall(b"\x00\x02")
        assert receive(sock, 1) == b"\x00"
        count = receive(sock, 1)[0]
        subtypes = struct.unpack(f"!{count}I", receive(sock, count * 4))
        assert subtypes == (262,), f"Expected only X509Plain, got {subtypes}"
        sock.sendall(struct.pack("!I", 262))
        assert receive(sock, 1) == b"\x01"
        with context.wrap_socket(sock, server_hostname="127.0.0.1") as tls:
            user, secret = username.encode(), password.encode()
            tls.sendall(struct.pack("!II", len(user), len(secret)) + user + secret)
            return struct.unpack("!I", receive(tls, 4))[0]


if __name__ == "__main__":
    config = dict(line.split("=", 1) for line in Path(sys.argv[1]).read_text().splitlines())
    with socket.create_connection(("127.0.0.1", 5900), timeout=5) as sock:
        greeting(sock)
        sock.sendall(b"\x01")  # Try None even though it was not advertised.
        try:
            result = receive(sock, 4)
        except (ConnectionError, ConnectionResetError):
            result = None
        assert result != b"\x00\x00\x00\x00", "Server accepted None authentication"
    assert authenticate(config, "", "") != 0, "Empty credentials accepted"
    assert authenticate(config, config["username"], "incorrect-password") != 0, "Wrong password accepted"
    assert authenticate(config, config["username"], config["password"]) == 0, "Valid credentials rejected"
    print("PASS: None, empty credentials, and wrong password rejected; valid credentials accepted over verified TLS.")
