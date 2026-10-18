"""Persistent plugin settings."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

DEFAULTS: dict[str, Any] = {
    "password_hash": "", "password_salt": "", "iterations": 310_000,
    "auth_methods": [],
    "events": {"startup": False, "settings": False, "course_editor": False,
               "install_uninstall": False, "update": False, "exit": False},
}


class Settings:
    def __init__(self, path: Path):
        self.path = path
        self.data = self._read()

    def _read(self) -> dict[str, Any]:
        data = json.loads(json.dumps(DEFAULTS))
        try:
            saved = json.loads(self.path.read_text(encoding="utf-8"))
            if isinstance(saved, dict):
                saved = dict(saved)
                saved_events = saved.pop("events", None)
                saved_methods = saved.pop("auth_methods", None)
                saved_method = saved.pop("method", None)
                data.update(saved)
                if isinstance(saved_events, dict):
                    data["events"].update({k: bool(v) for k, v in saved_events.items() if k in data["events"]})
                if isinstance(saved_methods, list):
                    data["auth_methods"] = saved_methods
                elif saved_method:
                    data["method"] = saved_method
        except (OSError, ValueError, TypeError):
            pass
        # Migrate the previous selector value into the new enabled-method list.
        if "auth_methods" not in data or not isinstance(data.get("auth_methods"), list):
            old_method = data.pop("method", "password")
            data["auth_methods"] = ["password"] if old_method in ("password", "either") else []
            if old_method in ("hello", "either"):
                data["auth_methods"].append("hello")
        data["auth_methods"] = list(dict.fromkeys(
            method for method in data["auth_methods"] if method in ("password", "hello")
        ))
        return data

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_suffix(self.path.suffix + ".tmp")
        temporary.write_text(json.dumps(self.data, ensure_ascii=False, indent=2), encoding="utf-8")
        temporary.replace(self.path)
