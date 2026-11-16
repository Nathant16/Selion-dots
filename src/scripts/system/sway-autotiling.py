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

def send_ipc(sock, msg_type, payload=""):
    data = payload.encode("utf-8") if isinstance(payload, str) else payload
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

def get_tree(cmd_sock):
    send_ipc(cmd_sock, 4)  # type 4 = GET_TREE
    _, payload = recv_ipc(cmd_sock)
    if payload:
        try:
            return json.loads(payload)
        except Exception:
            pass
    return None

def find_focused_and_parent(node, parent=None):
    if node.get("focused"):
        return node, parent
    for child in node.get("nodes", []):
        res = find_focused_and_parent(child, node)
        if res[0] is not None:
            return res
    for child in node.get("floating_nodes", []):
        res = find_focused_and_parent(child, node)
        if res[0] is not None:
            return res
    return None, None

def update_split(cmd_sock):
    tree = get_tree(cmd_sock)
    if not tree:
        return

    con, parent = find_focused_and_parent(tree)
    if not con or con.get("type") != "con":
        return

    # Exclude floating containers, popups, and fullscreen windows
    floating = con.get("floating", "")
    fullscreen = con.get("fullscreen_mode", 0)
    if floating in ("user_on", "auto_on") or fullscreen != 0:
        return

    # Exclude tabbed and stacked parent containers
    if parent and parent.get("layout") in ("tabbed", "stacked"):
        return

    rect = con.get("rect", {})
    w = rect.get("width", 0)
    h = rect.get("height", 0)
    if w <= 0 or h <= 0:
        return

    # Dynamic dwindle rule:
    # If window is taller than wide -> split vertical (splitv, opens below)
    # If window is wider than tall -> split horizontal (splith, opens to right)
    new_layout = "splitv" if h > w else "splith"
    parent_layout = parent.get("layout") if parent else None

    if new_layout != parent_layout:
        send_ipc(cmd_sock, 0, new_layout)
        recv_ipc(cmd_sock)

def run_daemon():
    # Ensure single instance
    lock_file = f"/tmp/sway-autotiling-{os.getuid()}.lock"
    try:
        lock_fd = open(lock_file, "w")
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except (IOError, OSError):
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

            # 2. Command dispatcher / tree query socket
            cmd_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            cmd_sock.connect(sock_path)

            # Subscribe to window and workspace events
            send_ipc(sub_sock, 2, '["window", "workspace"]')
            recv_ipc(sub_sock)

            # Initial split orientation update on startup
            update_split(cmd_sock)

            while True:
                msg_type, payload = recv_ipc(sub_sock)
                if not payload:
                    break

                try:
                    event = json.loads(payload)
                except Exception:
                    continue

                change = event.get("change")
                if change in ("focus", "new", "close", "move", "floating", "fullscreen_mode", "init"):
                    update_split(cmd_sock)

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
