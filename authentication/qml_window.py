"""RinUI-based authentication and message windows.

Creates an independent RinUI window instance per prompt, runs a modal
event loop and returns the captured password. Any failure reports the
window as unavailable so callers can cancel the interaction.
"""

from __future__ import annotations
from pathlib import Path
from typing import Any, Callable
import os
import sys

try:
    from loguru import logger
except ImportError:
    import logging
    logger = logging.getLogger("authentication")

from PySide6.QtCore import QCoreApplication, QEventLoop, QObject, Signal, Slot
from PySide6.QtWidgets import QApplication


def _rinui_ready() -> bool:
    """Ensure the RinUI package can be imported."""
    try:
        import RinUI  # noqa: F401
        return True
    except Exception:
        return False


class _AuthBridge(QObject):
    """Object exposed to QML as ``authContext``."""

    feedback = Signal(str)

    def __init__(self, verifier: Callable[[str], bool] | None, error_message: str | None):
        super().__init__()
        self.verifier = verifier
        self.error_message = error_message or "你输入的密码不匹配，请再试一次。"
        self.value: str | None = None
        self._loop: QEventLoop | None = None

    @Slot(str)
    def accept(self, value: str) -> None:
        if self.verifier is None:
            self.value = value
            self._quit()
            return
        try:
            ok = bool(self.verifier(value))
        except Exception:
            logger.exception("Verifier raised during authentication")
            ok = False
        if ok:
            self.value = value
            self._quit()
        else:
            logger.debug("Authentication attempt failed, prompting again")
            self.feedback.emit(self.error_message)

    @Slot()
    def cancel(self) -> None:
        self._quit()

    @Slot()
    def show_keyboard(self) -> None:
        if sys.platform != "win32":
            return
        try:
            os.system("start osk.exe")
        except Exception as exc:
            logger.error(f"Failed to launch osk.exe: {exc}")

    def _quit(self) -> None:
        loop = self._loop
        self._loop = None
        if loop is not None:
            loop.quit()


class RinAuthWindow:
    """Owns one RinUI window per authentication prompt."""

    def __init__(self, qml_path: Path):
        self.qml_path = Path(qml_path)
        self.last_error: Exception | None = None

    def open(
        self,
        title: str,
        prompt: str,
        submit_label: str = "确定",
        verifier: Callable[[str], bool] | None = None,
        error: str | None = None,
    ) -> tuple[str, str | None]:
        return self._run(self.qml_path, title, prompt, submit_label, verifier, error, overlay=True)

    def message(self, title: str, prompt: str) -> bool:
        message_qml = self.qml_path.parent / "MessageWindow.qml"
        status, _ = self._run(message_qml, title, prompt, "确定", None, None)
        return status != "unavailable"

    def choose(self, title: str, prompt: str, options: list[dict[str, str]]) -> tuple[str, str | None]:
        chooser_qml = self.qml_path.parent / "MethodWindow.qml"
        normalized = [{"key": str(item.get("key", "")), "label": str(item.get("label", ""))} for item in options]
        return self._run(chooser_qml, title, prompt, "", None, None, {"authOptions": normalized}, overlay=True)

    def _run(
        self,
        qml_path: Path,
        title: str,
        prompt: str,
        submit_label: str,
        verifier: Callable[[str], bool] | None,
        error: str | None,
        extra: dict[str, Any] | None = None,
        overlay: bool = False,
    ) -> tuple[str, str | None]:
        self.last_error = None
        if not qml_path.exists() or not _rinui_ready():
            self.last_error = FileNotFoundError(str(qml_path))
            return "unavailable", None
        bridge = _AuthBridge(verifier, error)
        rin = None
        try:
            from RinUI import RinUIWindow

            rin = RinUIWindow(shared_engine=False)
            try:
                app = QCoreApplication.instance()
                if app is not None:
                    app.aboutToQuit.disconnect(rin.theme_manager.clean_up)
            except Exception:
                pass

            context = rin.engine.rootContext()
            context.setContextProperty("authContext", bridge)
            context.setContextProperty("authTitle", title)
            context.setContextProperty("authPrompt", prompt)
            context.setContextProperty("authSubmitLabel", submit_label)
            for key, value in (extra or {}).items():
                context.setContextProperty(key, value)

            rin.load(qml_path)
            window = rin.root_window
            if window is None:
                raise RuntimeError("RinUI window failed to load")
            window.setProperty("title", title)

            if overlay:
                window.showFullScreen()
            else:
                screen = QApplication.primaryScreen()
                if screen is not None:
                    geometry = screen.availableGeometry()
                    window.setX(geometry.center().x() - window.width() // 2)
                    window.setY(geometry.center().y() - window.height() // 2)
                window.show()

            loop = QEventLoop()
            bridge._loop = loop
            window.requestActivate()
            logger.debug("RinUI window shown: {}", title)
            loop.exec()
            if bridge.value is not None:
                logger.debug("RinUI authentication window accepted password input")
                return ("verified" if verifier is not None else "ok"), bridge.value
            logger.debug("RinUI window closed")
            return "ok", None
        except Exception as exc:
            logger.exception("Failed to show RinUI window")
            self.last_error = exc
            return "unavailable", None
        finally:
            if rin is not None:
                self._release(rin)

    @staticmethod
    def _release(rin) -> None:
        try:
            app = QApplication.instance()
            if app is not None and getattr(rin, "win_event_filter", None) is not None:
                app.removeNativeEventFilter(rin.win_event_filter)
        except Exception:
            logger.debug("Remove RinUI native event filter failed", exc_info=True)
        try:
            window = getattr(rin, "root_window", None)
            if window is not None:
                window.hide()
                window.releaseResources()
                window.deleteLater()
        except Exception:
            logger.debug("Release RinUI window failed", exc_info=True)
        try:
            engine = getattr(rin, "engine", None)
            if engine is not None:
                engine.clearComponentCache()
                engine.collectGarbage()
                engine.deleteLater()
        except Exception:
            logger.debug("Release RinUI engine failed", exc_info=True)