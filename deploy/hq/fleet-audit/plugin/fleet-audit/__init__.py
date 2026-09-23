"""fleet-audit — the fleet's tool-call log (fleet-v1 §8, security baseline MUST #13).

Every tool call (including blocked and failed ones), every approval request and decision, every
delegation and kanban hand-off is sent to journald as one JSON line under SYSLOG_IDENTIFIER=fleet-audit.
journald stamps the sender's _UID/_PID itself (the plugin cannot forge them) and svc-hermes cannot delete
journal entries; the root-owned fleet-audit-collector copies them into append-only files under
/var/lib/fleet-audit, which the off-site backup carries.

No log, no action: if an entry cannot be written, pre_tool_call blocks the tool.

Source of truth: core/elmaati/deploy/hq/fleet-audit/ (installed root-owned by install.sh; never edit
the installed copy).
"""

from __future__ import annotations

import json
import os
import socket
import sys
import threading
import time

_SOCK_PATH = "/run/systemd/journal/socket"
_MAX_FIELD = 4000  # chars per args/result field after redaction; keeps a datagram far below the limit
_lock = threading.Lock()
_sock: socket.socket | None = None


def _profile() -> str:
    try:
        from hermes_constants import get_hermes_home
        home = str(get_hermes_home())
    except Exception:
        home = os.environ.get("HERMES_HOME", "")
    marker = "/profiles/"
    return home.split(marker, 1)[1].split("/", 1)[0] if marker in home else "default"


def _clip(value) -> str | None:
    if value is None:
        return None
    text = value if isinstance(value, str) else json.dumps(value, default=str, ensure_ascii=False)
    try:
        from agent.redact import redact_sensitive_text
        text = redact_sensitive_text(text, force=True, redact_url_credentials=True)
    except Exception:
        text = "«redaction unavailable — withheld»"
    if len(text) > _MAX_FIELD:
        text = f"{text[:_MAX_FIELD]}…«+{len(text) - _MAX_FIELD} chars»"
    return text


def _send(event: str, **fields) -> bool:
    """Write one entry; True when journald accepted it."""
    global _sock
    record = {"ts": time.time(), "event": event, "profile": _profile(), "pid": os.getpid()}
    record.update({k: v for k, v in fields.items() if v is not None})
    line = json.dumps(record, default=str, ensure_ascii=True)  # ASCII-only: no raw newlines reach journald
    payload = f"SYSLOG_IDENTIFIER=fleet-audit\nPRIORITY=6\nFLEET_EVENT={event}\nMESSAGE={line}\n".encode()
    with _lock:
        for _ in range(2):
            try:
                if _sock is None:
                    _sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
                    _sock.connect(_SOCK_PATH)
                _sock.send(payload)
                return True
            except OSError:
                try:
                    if _sock is not None:
                        _sock.close()
                finally:
                    _sock = None
    return False


def _pre_tool_call(tool_name=None, args=None, session_id=None, task_id=None, tool_call_id=None,
                   turn_id=None, **_):
    ok = _send("tool.call", tool=tool_name, args=_clip(args), session_id=session_id, task_id=task_id,
               tool_call_id=tool_call_id, turn_id=turn_id)
    if not ok:
        return {"action": "block", "message": "fleet-audit: the tool-call log is unavailable, so no tool may run."}
    return None


def _post_tool_call(tool_name=None, result=None, session_id=None, task_id=None, tool_call_id=None,
                    turn_id=None, duration_ms=None, status=None, error_type=None, error_message=None, **_):
    _send("tool.result", tool=tool_name, status=status, duration_ms=duration_ms, result=_clip(result),
          error_type=error_type, error=_clip(error_message), session_id=session_id, task_id=task_id,
          tool_call_id=tool_call_id, turn_id=turn_id)


def _approval_request(command=None, description=None, pattern_keys=None, session_key=None, surface=None,
                      tool_call_id=None, **_):
    _send("approval.request", command=_clip(command), description=_clip(description), patterns=pattern_keys,
          session_key=session_key, surface=surface, tool_call_id=tool_call_id)


def _approval_response(command=None, pattern_keys=None, session_key=None, surface=None, tool_call_id=None,
                       choice=None, decided_by=None, **_):
    _send("approval.decision", choice=choice, decided_by=decided_by, command=_clip(command),
          patterns=pattern_keys, session_key=session_key, surface=surface, tool_call_id=tool_call_id)


def _session_start(session_id=None, model=None, platform=None, **_):
    _send("session.start", session_id=session_id, model=model, platform=platform)


def _subagent_start(parent_session_id=None, child_session_id=None, child_role=None, child_goal=None, **_):
    _send("subagent.start", parent_session_id=parent_session_id, child_session_id=child_session_id,
          role=child_role, goal=_clip(child_goal))


def _subagent_stop(parent_session_id=None, child_session_id=None, child_role=None, child_status=None,
                   child_summary=None, duration_ms=None, **_):
    _send("subagent.stop", parent_session_id=parent_session_id, child_session_id=child_session_id,
          role=child_role, status=child_status, summary=_clip(child_summary), duration_ms=duration_ms)


def _kanban(event):
    def handler(task_id=None, profile_name=None, board=None, assignee=None, run_id=None, summary=None,
                reason=None, worker_pid=None, exit_kind=None, exit_code=None, **_):
        _send(event, task_id=task_id, worker_profile=profile_name, board=board, assignee=assignee,
              run_id=run_id, summary=_clip(summary), reason=_clip(reason), worker_pid=worker_pid,
              exit_kind=exit_kind, exit_code=exit_code)
    return handler


def register(ctx):
    ctx.register_hook("pre_tool_call", _pre_tool_call)
    ctx.register_hook("post_tool_call", _post_tool_call)
    ctx.register_hook("pre_approval_request", _approval_request)
    ctx.register_hook("post_approval_response", _approval_response)
    ctx.register_hook("on_session_start", _session_start)
    ctx.register_hook("subagent_start", _subagent_start)
    ctx.register_hook("subagent_stop", _subagent_stop)
    for hook, event in (("kanban_task_claimed", "kanban.claimed"), ("kanban_task_completed", "kanban.completed"),
                        ("kanban_task_blocked", "kanban.blocked"), ("on_kanban_worker_spawned", "kanban.spawned"),
                        ("on_kanban_worker_exited", "kanban.exited")):
        ctx.register_hook(hook, _kanban(event))
    # The watcher checks every live Hermes process has announced itself; a missing "loaded" = logging is off.
    _send("audit.loaded", argv=" ".join(sys.argv[:4]))
