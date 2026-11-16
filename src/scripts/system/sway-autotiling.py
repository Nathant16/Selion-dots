#!/usr/bin/env python3
"""
Sway Autotiling Daemon (Dwindle / Fibonacci dynamic tiling for Sway)
Replicates Hyprland's dwindle tiling layout by automatically alternating
horizontal and vertical splits based on the active container's aspect ratio.

Zero external dependencies - uses standard Python library only.
"""

import fcntl
import glob
import json
import os
import signal
import socket
import struct
import sys
import time

def get_sway_socket():
    sock = os.environ.get("SWAYSOCK")
    if sock and os.path.exists(sock):
        return sock
    uid = os.getuid()
    socks = sorted(glob.glob(f"/run/user/{uid}/sway-ipc.*.sock"), reverse=True)
    if socks:
        return socks[0]
    return None

def send_ipc(sock, msg_type, payload):
    data = payload.encode("utf-8")
    hdr = struct.pack("<6sII", b"i3-ipc", len(data), msg_type)
    sock.sendall(hdr + data)

def recv_ipc(sock):
    hdr = bytearray()
    while len(hdr) < 14:
        chunk = sock.recv(14 - len(hdr))
        if not chunk:
            return None, None
        hdr.extend(chunk)
    magic, length, msg_type = struct.unpack("<6sII", hdr)
    if magic != b"i3-ipc":
        return None, None
    body = bytearray()
    while len(body) < length:
        chunk = sock.recv(min(8192, length - len(body)))
        if not chunk:
            break
        body.extend(chunk)
    return msg_type, body.decode("utf-8", errors="replace")

def run_daemon():
    # Ensure single instance
    lock_file = f"/tmp/sway-autotiling-{os.getuid()}.lock"
    try:
        lock_fd = open(lock_file, "w")
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except (IOError, OSError):
        # Another instance is already active
        sys.exit(0)

    while True:
        sock_path = get_sway_socket()
        if not sock_path:
            time.sleep(1)
            continue

        sub_sock = None
        cmd_sock = None
        try:
            # 1. Event listener socket
            sub_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sub_sock.connect(sock_path)

            # 2. Command dispatcher socket
            cmd_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            cmd_sock.connect(sock_path)

            # Subscribe to window events (type 2 = SUBSCRIBE)
            send_ipc(sub_sock, 2, '["window"]')
            recv_ipc(sub_sock)

            last_con_id = None
            last_layout = None

            while True:
                msg_type, payload = recv_ipc(sub_sock)
                if not payload:
                    break

                try:
                    event = json.loads(payload)
                except Exception:
                    continue

                change = event.get("change")
                if change in ("focus", "new", "move"):
                    con = event.get("container")
                    if not con:
                        continue

                    cid = con.get("id")
                    ctype = con.get("type", "")
                    floating = con.get("floating", "")
                    fullscreen = con.get("fullscreen_mode", 0)

                    # Exclude floating containers, popups, and fullscreen windows
                    if ctype == "floating_con" or floating in ("user_on", "auto_on") or fullscreen != 0:
                        continue

                    rect = con.get("rect", {})
                    w = rect.get("width", 0)
                    h = rect.get("height", 0)
                    if w <= 0 or h <= 0:
                        continue

                    # Dynamic dwindle rule:
                    # If window is wider than it is tall -> split horizontal (new window opens to the right)
                    # If window is taller than it is wide -> split vertical (new window opens below)
                    target_layout = "splitv" if h > w else "splith"

                    if cid != last_con_id or target_layout != last_layout:
                        send_ipc(cmd_sock, 0, f"[con_id={cid}] {target_layout}")
                        recv_ipc(cmd_sock)
                        last_con_id = cid
                        last_layout = target_layout

        except (socket.error, OSError):
            time.sleep(1)
        except Exception:
            time.sleep(1)
        finally:
            if sub_sock:
                try:
                    sub_sock.close()
                except Exception:
                    pass
            if cmd_sock:
                try:
                    cmd_sock.close()
                except Exception:
                    pass

def main():
    signal.signal(signal.SIGINT, lambda *_: sys.exit(0))
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    run_daemon()

if __name__ == "__main__":
    main()

