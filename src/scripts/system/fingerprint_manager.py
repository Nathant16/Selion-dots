#!/usr/bin/env python3
import sys
import os
import json
import subprocess
import re
import getpass

VALID_FINGERS = [
    "right-thumb",
    "right-index-finger",
    "right-middle-finger",
    "right-ring-finger",
    "right-little-finger",
    "left-thumb",
    "left-index-finger",
    "left-middle-finger",
    "left-ring-finger",
    "left-little-finger"
]

def get_current_user():
    return os.environ.get("USER") or getpass.getuser()

def get_dbus_property(obj_path, prop):
    try:
        res = subprocess.run(
            ["busctl", "get-property", "net.reactivated.Fprint", obj_path, "net.reactivated.Fprint.Device", prop],
            capture_output=True,
            text=True,
            timeout=2
        )
        if res.returncode == 0:
            val = res.stdout.strip()
            # Format like 's "Synaptics Sensors"' or 'i 9'
            parts = val.split(" ", 1)
            if len(parts) == 2:
                sig, v = parts
                if sig == "s":
                    return v.strip('"')
                elif sig == "i" or sig == "u":
                    return int(v)
                elif sig == "b":
                    return v.lower() == "true"
            return val
    except Exception:
        pass
    return None

def get_device_info():
    user = get_current_user()
    try:
        res = subprocess.run(
            ["fprintd-list", user],
            capture_output=True,
            text=True,
            timeout=4
        )
        out = res.stdout + res.stderr
        if "found 0 devices" in out or "No devices available" in out or "failed to claim" in out and "Device not found" in out:
            return {"available": False, "device": "", "scan_type": "", "stages": 0, "fingers": []}

        # Try to find device path
        dev_path = "/net/reactivated/Fprint/Device/0"
        m = re.search(r"Device at (/net/reactivated/Fprint/Device/\d+)", out)
        if m:
            dev_path = m.group(1)

        name = get_dbus_property(dev_path, "name") or "Fingerprint Reader"
        scan_type = get_dbus_property(dev_path, "scan-type") or "press"
        stages = get_dbus_property(dev_path, "num-enroll-stages") or 5

        # Parse fingers
        fingers = []
        for line in out.splitlines():
            line = line.strip()
            # Match '- #0: right-index-finger' or '#0: right-index-finger'
            fm = re.search(r"#\d+:\s*([a-zA-Z0-9_\-]+)", line)
            if fm:
                f_name = fm.group(1)
                if f_name in VALID_FINGERS:
                    fingers.append(f_name)

        return {
            "available": True,
            "device": name,
            "scan_type": scan_type,
            "stages": stages,
            "fingers": fingers
        }
    except FileNotFoundError:
        return {"available": False, "device": "", "scan_type": "", "stages": 0, "fingers": [], "error": "fprintd not installed"}
    except Exception as e:
        return {"available": False, "device": "", "scan_type": "", "stages": 0, "fingers": [], "error": str(e)}

def cmd_status():
    info = get_device_info()
    print(json.dumps({
        "available": info["available"],
        "device": info["device"],
        "scan_type": info["scan_type"],
        "stages": info["stages"]
    }))

def cmd_list():
    info = get_device_info()
    print(json.dumps({
        "available": info["available"],
        "device": info["device"],
        "fingers": info["fingers"]
    }))

def cmd_delete(finger):
    user = get_current_user()
    try:
        if finger == "all":
            cmd = ["fprintd-delete", user]
        else:
            if finger not in VALID_FINGERS:
                print(json.dumps({"success": False, "error": f"Invalid finger '{finger}'"}))
                return
            cmd = ["fprintd-delete", user, "-f", finger]

        res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if res.returncode == 0:
            print(json.dumps({"success": True}))
        else:
            err = (res.stderr or res.stdout).strip()
            print(json.dumps({"success": False, "error": err}))
    except Exception as e:
        print(json.dumps({"success": False, "error": str(e)}))

def cmd_enroll(finger):
    if finger not in VALID_FINGERS:
        print(json.dumps({"type": "failed", "status": "invalid_finger", "message": f"Invalid finger '{finger}'"}), flush=True)
        return

    user = get_current_user()
    info = get_device_info()
    if not info["available"]:
        print(json.dumps({"type": "failed", "status": "no_device", "message": "No fingerprint device found"}), flush=True)
        return

    total_stages = info["stages"] or 5
    current_stage = 0

    print(json.dumps({
        "type": "started",
        "stage": 0,
        "total": total_stages,
        "percent": 0,
        "finger": finger,
        "scan_type": info["scan_type"],
        "status": "ready",
        "message": "Place your finger on the sensor"
    }), flush=True)

    try:
        proc = subprocess.Popen(
            ["fprintd-enroll", user, "-f", finger],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )

        completed = False
        for raw_line in proc.stdout:
            line = raw_line.strip()
            if not line:
                continue

            if "enroll-stage-passed" in line:
                current_stage += 1
                percent = min(100, int((current_stage / total_stages) * 100))
                print(json.dumps({
                    "type": "progress",
                    "stage": current_stage,
                    "total": total_stages,
                    "percent": percent,
                    "status": "stage_passed",
                    "message": "Stage passed. Lift finger and press again."
                }), flush=True)
            elif "enroll-retry-scan" in line:
                percent = min(100, int((current_stage / total_stages) * 100))
                print(json.dumps({
                    "type": "progress",
                    "stage": current_stage,
                    "total": total_stages,
                    "percent": percent,
                    "status": "retry_scan",
                    "message": "Finger not recognized. Try again."
                }), flush=True)
            elif "enroll-swipe-too-short" in line:
                percent = min(100, int((current_stage / total_stages) * 100))
                print(json.dumps({
                    "type": "progress",
                    "stage": current_stage,
                    "total": total_stages,
                    "percent": percent,
                    "status": "swipe_too_short",
                    "message": "Swipe too short. Try again."
                }), flush=True)
            elif "enroll-finger-not-centered" in line:
                percent = min(100, int((current_stage / total_stages) * 100))
                print(json.dumps({
                    "type": "progress",
                    "stage": current_stage,
                    "total": total_stages,
                    "percent": percent,
                    "status": "not_centered",
                    "message": "Center your finger on the sensor."
                }), flush=True)
            elif "enroll-remove-and-retry" in line:
                percent = min(100, int((current_stage / total_stages) * 100))
                print(json.dumps({
                    "type": "progress",
                    "stage": current_stage,
                    "total": total_stages,
                    "percent": percent,
                    "status": "remove_retry",
                    "message": "Remove finger and place it again."
                }), flush=True)
            elif "enroll-completed" in line:
                completed = True
                print(json.dumps({
                    "type": "completed",
                    "stage": total_stages,
                    "total": total_stages,
                    "percent": 100,
                    "status": "completed",
                    "message": "Fingerprint enrolled successfully!"
                }), flush=True)
            elif "enroll-failed" in line or "Enrollment failed" in line:
                print(json.dumps({
                    "type": "failed",
                    "stage": current_stage,
                    "total": total_stages,
                    "percent": min(100, int((current_stage / total_stages) * 100)),
                    "status": "failed",
                    "message": "Enrollment failed."
                }), flush=True)
            elif "enroll-disconnected" in line:
                print(json.dumps({
                    "type": "failed",
                    "status": "disconnected",
                    "message": "Fingerprint reader disconnected."
                }), flush=True)

        proc.wait()
        print(json.dumps({
            "type": "finished",
            "success": completed or proc.returncode == 0,
            "code": proc.returncode
        }), flush=True)

    except Exception as e:
        print(json.dumps({
            "type": "failed",
            "status": "exception",
            "message": str(e)
        }), flush=True)

def main():
    if len(sys.argv) < 2:
        print("Usage: fingerprint_manager.py [status|list|delete <finger|all>|enroll <finger>]")
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "status":
        cmd_status()
    elif cmd == "list":
        cmd_list()
    elif cmd == "delete":
        finger = sys.argv[2] if len(sys.argv) > 2 else "all"
        cmd_delete(finger)
    elif cmd == "enroll":
        if len(sys.argv) < 3:
            print(json.dumps({"type": "failed", "status": "missing_arg", "message": "Specify finger to enroll"}))
            sys.exit(1)
        cmd_enroll(sys.argv[2])
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)

if __name__ == "__main__":
    main()

