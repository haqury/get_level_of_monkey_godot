#!/usr/bin/env python3
"""BrainLink shared-memory shim for Godot (Windows). Polls SHM and writes status to user file."""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

CODE_TO_EVENT = {0: "", 1: "ml", 2: "mr", 3: "mu", 4: "md", 5: "stop", 6: "ne"}
EVENT_TO_CODE = {v: k for k, v in CODE_TO_EVENT.items() if v}

EVENT_CODE_OFF = 13
COMMAND_PENDING = 21
COMMAND_TYPE = 22
COMMAND_EVENT_CODE = 23
COMMAND_TIMESTAMP = 24
ML_CONFIDENCE = 25
ML_PROB_ML = 26
ML_PROB_MR = 27
ML_PROB_MU = 28
ML_PROB_MD = 29
ML_PROB_STOP = 30
ML_STATS_SIZE = 31 * 4

INT32_MAX = 2147483647
INT32_MIN = -2147483648
_start_time = time.time()


def read_int32(shm, offset: int) -> int:
    import struct
    return struct.unpack_from("<i", shm.buf, offset * 4)[0]


def write_int32(shm, offset: int, value: int) -> None:
    import struct
    if value > INT32_MAX:
        value = INT32_MAX
    elif value < INT32_MIN:
        value = INT32_MIN
    struct.pack_into("<i", shm.buf, offset * 4, value)


def _relative_timestamp_ms() -> int:
    return int((time.time() - _start_time) * 1000)


def _command_pending(shm) -> bool:
    try:
        return read_int32(shm, COMMAND_PENDING) == 1
    except Exception:
        return False


def _send_command(shm, command_type: int, event_code: int) -> bool:
    if _command_pending(shm):
        time.sleep(0.001)
        if _command_pending(shm):
            return False
    write_int32(shm, COMMAND_TYPE, command_type)
    write_int32(shm, COMMAND_EVENT_CODE, event_code)
    write_int32(shm, COMMAND_TIMESTAMP, _relative_timestamp_ms())
    write_int32(shm, COMMAND_PENDING, 1)
    return True


def _read_ml_stats(shm) -> tuple[float, dict]:
    if len(shm.buf) < ML_STATS_SIZE:
        return 0.0, {}
    try:
        conf = max(0.0, min(1.0, read_int32(shm, ML_CONFIDENCE) / 1000.0))
        probs = {
            "ml": read_int32(shm, ML_PROB_ML) / 1000.0,
            "mr": read_int32(shm, ML_PROB_MR) / 1000.0,
            "mu": read_int32(shm, ML_PROB_MU) / 1000.0,
            "md": read_int32(shm, ML_PROB_MD) / 1000.0,
            "stop": read_int32(shm, ML_PROB_STOP) / 1000.0,
        }
        return conf, probs
    except Exception:
        return 0.0, {}


def main() -> None:
    from multiprocessing import shared_memory

    status_path = Path.home() / "AppData/Roaming/Godot/app_userdata/GetLevelOfAMonkey/brainlink_status.json"
    cmd_path = status_path.parent / "brainlink_cmd.json"
    memory_name = "brainlink_data"
    if len(sys.argv) > 1:
        status_path = Path(sys.argv[1])
        cmd_path = status_path.parent / "brainlink_cmd.json"
    shm = None
    while True:
        if cmd_path.exists():
            try:
                cmd = json.loads(cmd_path.read_text(encoding="utf-8"))
                cmd_path.unlink(missing_ok=True)
                if cmd.get("cmd") == "connect":
                    memory_name = cmd.get("memory_name", memory_name)
                    if cmd.get("status_path"):
                        status_path = Path(cmd["status_path"])
                        cmd_path = status_path.parent / "brainlink_cmd.json"
                    try:
                        if shm:
                            shm.close()
                        shm = shared_memory.SharedMemory(name=memory_name)
                    except FileNotFoundError:
                        shm = None
                elif cmd.get("cmd") == "disconnect" and shm:
                    shm.close()
                    shm = None
                elif cmd.get("cmd") == "send_event" and shm:
                    code = EVENT_TO_CODE.get(cmd.get("event_code", ""), 0)
                    if cmd.get("event_code") and code == 0:
                        code = 0
                    _send_command(shm, int(cmd.get("command_type", 1)), code)
                elif cmd.get("cmd") == "minigame_event" and shm:
                    ev = str(cmd.get("keyboard_event", ""))
                    if ev in EVENT_TO_CODE:
                        _send_command(shm, 2, EVENT_TO_CODE[ev])
                elif cmd.get("cmd") == "config_command" and shm:
                    ctype = int(cmd.get("command_type", 0))
                    if 3 <= ctype <= 9:
                        _send_command(shm, ctype, 0)
            except Exception:
                pass
        status = {"connected": shm is not None, "event": "", "confidence": 0.0, "probs": {}}
        if shm:
            try:
                ev = read_int32(shm, EVENT_CODE_OFF)
                status["event"] = CODE_TO_EVENT.get(ev, "")
                conf, probs = _read_ml_stats(shm)
                status["confidence"] = conf
                status["probs"] = probs
            except Exception:
                status["connected"] = False
                shm = None
        try:
            status_path.write_text(json.dumps(status), encoding="utf-8")
        except Exception:
            pass
        time.sleep(0.016)


if __name__ == "__main__":
    main()
