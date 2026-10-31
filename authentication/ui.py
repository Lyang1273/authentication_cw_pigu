"""Authentication windows used for credential setup, verification and notices.

All user-facing prompts are shown as RinUI windows; nothing falls back to
native Qt dialogs. If the RinUI window cannot be shown, the interaction is
cancelled and logged.
"""

from __future__ import annotations

from typing import Callable
try:
    from loguru import logger
except ImportError:
    import logging
    logger = logging.getLogger("authentication")


class AuthDialogs:
    def __init__(self, parent_provider: Callable[[], object | None], rin_window: object | None = None):
        self.parent_provider = parent_provider
        self._rin_window = rin_window

    def password(
        self,
        title: str,
        message: str,
        verifier: Callable[[str], bool] | None = None,
        error: str | None = None,
    ) -> str | None:
        if self._rin_window is None:
            logger.error("RinUI authentication window not initialized; cancelling interaction")
            return None
        try:
            status, value = self._rin_window.open(
                title=title,
                prompt=message,
                submit_label="验证" if verifier is not None else "确定",
                verifier=verifier,
                error=error,
                parent=self.parent_provider(),
            )
        except Exception:
            logger.exception("RinUI authentication window raised unexpectedly")
            return None
        if status == "unavailable":
            logger.error("Failed to show RinUI authentication window; cancelling interaction")
            return None
        return value

    def confirm_password(self, title: str, message: str, first_value: str | None = None) -> str | None:
        if first_value is None:
            return self.password(title, message)
        return self.password(
            title,
            message,
            verifier=lambda value: value == first_value,
            error="两次输入的密码不一致，请重新输入。",
        )

    def notify(self, message: str, title: str = "身份验证") -> None:
        if self._rin_window is None:
            logger.warning("RinUI authentication window not initialized; {} : {}", title, message)
            return
        try:
            shown = self._rin_window.message(title, message, parent=self.parent_provider())
        except Exception:
            logger.exception("RinUI message window raised unexpectedly")
            shown = False
        if not shown:
            logger.warning("{}: {}", title, message)
