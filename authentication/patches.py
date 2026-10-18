"""Reversible monkey-patching helpers."""

from __future__ import annotations

import functools
from typing import Any, Callable
try:
    from loguru import logger
except ImportError:
    import logging
    logger = logging.getLogger("authentication")


class PatchManager:
    def __init__(self):
        self._originals: list[tuple[Any, str, Any]] = []

    def wrap(self, owner: Any, name: str, before: Callable[..., bool]) -> bool:
        original = getattr(owner, name, None)
        if not callable(original) or getattr(original, "__authentication_patch__", False):
            return False

        @functools.wraps(original)
        def guarded(*args: Any, **kwargs: Any):
            if not before(*args, **kwargs):
                if name == "closeEvent" and args:
                    event = args[-1]
                    if hasattr(event, "ignore"):
                        event.ignore()
                    return None
                # Qt slots returning None must preserve their declared result;
                # bool-returning operations use False to report cancellation.
                return False if getattr(original, "__annotations__", {}).get("return") is bool else None
            return original(*args, **kwargs)

        guarded.__authentication_patch__ = True
        try:
            setattr(owner, name, guarded)
        except (AttributeError, TypeError):
            logger.exception("Failed to install authentication patch {}.{}", getattr(owner, "__name__", type(owner).__name__), name)
            return False
        self._originals.append((owner, name, original))
        return True

    def restore(self) -> None:
        for owner, name, original in reversed(self._originals):
            try:
                setattr(owner, name, original)
                logger.debug("Restored patched method {}.{}", getattr(owner, "__name__", type(owner).__name__), name)
            except (AttributeError, TypeError):
                logger.exception("Failed to restore patched method {}.{}", getattr(owner, "__name__", type(owner).__name__), name)
        self._originals.clear()
