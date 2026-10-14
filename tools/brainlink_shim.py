#!/usr/bin/env python3
"""BrainLink shared-memory shim for Godot (Windows). Polls SHM and writes status to user file."""

from __future__ import annotations

import json
import os
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

GROUND_TRUTH_COMMAND_TYPE = 2
CLIENT_STALE_SECONDS = 22.0
STUCK_EVENT_SECONDS = 2.5

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


def _wait_command_idle(shm, timeout_s: float = 0.25) -> bool:
    deadline = time.time() + timeout_s
    while _command_pending(shm):
        if time.time() >= deadline:
            return False
        time.sleep(0.002)
    return True


def _send_command(shm, command_type: int, event_code: int) -> bool:
    if not _wait_command_idle(shm):
        return False
    write_int32(shm, COMMAND_TYPE, command_type)
    write_int32(shm, COMMAND_EVENT_CODE, event_code)
    write_int32(shm, COMMAND_TIMESTAMP, _relative_timestamp_ms())
    write_int32(shm, COMMAND_PENDING, 1)
    return True


def _log_send(log_path: Path | None, event_name: str, ok: bool) -> None:
    if log_path is None:
        return
    try:
        line = f"{time.strftime('%H:%M:%S')} ground_truth {event_name} ok={ok}\n"
        with log_path.open("a", encoding="utf-8") as f:
            f.write(line)
    except Exception:
        pass


def _send_ground_truth(shm, event_name: str, log_path: Path | None = None) -> bool:
    code = EVENT_TO_CODE.get(event_name, 0)
    if code == 0:
        return False
    ok = _send_command(shm, GROUND_TRUTH_COMMAND_TYPE, code)
    _log_send(log_path, event_name, ok)
    return ok


class _ClientActivityWatch:
    """Live client updates SHM; after exit values freeze (e.g. stuck ml)."""

    def __init__(self) -> None:
        self._last_sig: tuple | None = None
        self._last_change = time.time()

    def reset(self) -> None:
        self._last_sig = None
        self._last_change = time.time()

    def evaluate(self, ev_code: int, conf: float, probs: dict) -> tuple[bool, str]:
        sig = (
            ev_code,
            int(conf * 1000.0),
            tuple(int(float(probs.get(k, 0.0)) * 1000.0) for k in ("ml", "mr", "mu", "md", "stop")),
        )
        now = time.time()
        if self._last_sig != sig:
            self._last_sig = sig
            self._last_change = now
        age = now - self._last_change
        event_name = CODE_TO_EVENT.get(ev_code, "")
        stuck_direction = ev_code != 0 and age > STUCK_EVENT_SECONDS
        client_active = age < CLIENT_STALE_SECONDS and not stuck_direction
        if stuck_direction or not client_active:
            event_name = ""
        return client_active, event_name


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


def _attach_shm(memory_name: str):
    from multiprocessing import shared_memory
    try:
        return shared_memory.SharedMemory(name=memory_name)
    except FileNotFoundError:
        return None


def _load_queue(queue_path: Path) -> list:
    if not queue_path.exists():
        return []
    try:
        data = json.loads(queue_path.read_text(encoding="utf-8"))
        return data if isinstance(data, list) else []
    except Exception:
        return []


def _save_queue(queue_path: Path, items: list) -> None:
    try:
        queue_path.write_text(json.dumps(items), encoding="utf-8")
    except Exception:
        pass


def _process_one_command(cmd: dict, shm, memory_name: str, log_path: Path | None) -> tuple[object, str]:
    """Returns (shm, memory_name) after optional reconnect."""
    name = cmd.get("cmd", "")
    if name == "connect":
        memory_name = str(cmd.get("memory_name", memory_name))
        if shm is not None:
            try:
                shm.close()
            except Exception:
                pass
        return _attach_shm(memory_name), memory_name
    if shm is None:
        return shm, memory_name
    if name == "disconnect":
        try:
            shm.close()
        except Exception:
            pass
        return None, memory_name
    if name == "send_ground_truth":
        _send_ground_truth(shm, str(cmd.get("event_code", "")), log_path)
        return shm, memory_name
    if name == "send_event":
        ctype = int(cmd.get("command_type", 1))
        if ctype == GROUND_TRUTH_COMMAND_TYPE:
            _send_ground_truth(shm, str(cmd.get("event_code", "")), log_path)
        elif 3 <= ctype <= 9:
            _send_command(shm, ctype, 0)
        return shm, memory_name
    if name == "minigame_event":
        ev = str(cmd.get("keyboard_event", ""))
        if ev in EVENT_TO_CODE:
            _send_ground_truth(shm, ev, log_path)
        return shm, memory_name
    if name == "config_command":
        ctype = int(cmd.get("command_type", 0))
        if 3 <= ctype <= 9:
            _send_command(shm, ctype, 0)
        return shm, memory_name
    return shm, memory_name


def _drain_command_queue(
    queue_path: Path,
    cmd_path: Path,
    shm,
    memory_name: str,
    log_path: Path | None,
    max_ground_truth_per_tick: int = 1,
) -> tuple[object, str]:
    queue = _load_queue(queue_path)
    legacy = None
    if cmd_path.exists():
        try:
            legacy = json.loads(cmd_path.read_text(encoding="utf-8"))
            cmd_path.unlink(missing_ok=True)
        except Exception:
            cmd_path.unlink(missing_ok=True)
    if legacy is not None:
        queue.insert(0, legacy)
    if not queue:
        return shm, memory_name

    gt_sent = 0
    remaining: list = []
    for cmd in queue:
        if not isinstance(cmd, dict):
            continue
        is_gt = cmd.get("cmd") in ("send_ground_truth", "minigame_event") or (
            cmd.get("cmd") == "send_event" and int(cmd.get("command_type", 0)) == GROUND_TRUTH_COMMAND_TYPE
        )
        if is_gt and gt_sent >= max_ground_truth_per_tick:
            remaining.append(cmd)
            continue
        if is_gt and shm is None:
            remaining.append(cmd)
            continue
        before_shm = shm
        shm, memory_name = _process_one_command(cmd, shm, memory_name, log_path)
        if is_gt:
            if before_shm is None and shm is None:
                remaining.append(cmd)
            else:
                gt_sent += 1
        elif cmd.get("cmd") == "connect" and shm is None:
            remaining.append(cmd)

    _save_queue(queue_path, remaining)
    return shm, memory_name


def main() -> None:
    default_status = Path.home() / "AppData/Roaming/Godot/app_userdata/GetLevelOfAMonkey/brainlink_status.json"
    status_path = Path(sys.argv[1]) if len(sys.argv) > 1 else default_status
    memory_name = sys.argv[2] if len(sys.argv) > 2 else "brainlink_data"
    queue_path = status_path.parent / "brainlink_cmd_queue.json"
    cmd_path = status_path.parent / "brainlink_cmd.json"
    log_path = status_path.parent / "brainlink_shim.log"
    pid_path = status_path.parent / "brainlink_shim.pid"
    try:
        pid_path.write_text(str(os.getpid()), encoding="utf-8")
    except Exception:
        pass

    client_watch = _ClientActivityWatch()
    shm = _attach_shm(memory_name)
    had_shm = shm is not None
    while True:
        shm, memory_name = _drain_command_queue(queue_path, cmd_path, shm, memory_name, log_path)
        if shm is None:
            shm = _attach_shm(memory_name)
        if (shm is not None) != had_shm:
            client_watch.reset()
            had_shm = shm is not None

        status = {
            "shm_attached": shm is not None,
            "client_active": False,
            "connected": False,
            "event": "",
            "confidence": 0.0,
            "probs": {},
            "heartbeat_ms": int(time.time() * 1000),
        }
        if shm:
            try:
                ev_code = read_int32(shm, EVENT_CODE_OFF)
                conf, probs = _read_ml_stats(shm)
                client_active, event_name = client_watch.evaluate(ev_code, conf, probs)
                status["client_active"] = client_active
                status["connected"] = client_active
                status["event"] = event_name
                status["confidence"] = conf if client_active else 0.0
                status["probs"] = probs if client_active else {}
            except Exception:
                status["shm_attached"] = False
                try:
                    shm.close()
                except Exception:
                    pass
                shm = None
                had_shm = False
                client_watch.reset()
        try:
            status_path.write_text(json.dumps(status), encoding="utf-8")
        except Exception:
            pass
        time.sleep(0.016)


if __name__ == "__main__":
    main()
