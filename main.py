"""Class Widgets 2 identity verification plugin entry point."""

from __future__ import annotations

import os
import sys
import threading
import time
from pathlib import Path
from typing import Any
try:
    from loguru import logger
except ImportError:  # Class Widgets provides loguru; this keeps standalone dev checks importable.
    import logging
    logger = logging.getLogger("authentication")

# Vendored dependencies live in libs/ next to the entry file; make sure they
# are importable even if the host loads the entry outside its usual context.
_LIBS_DIR = Path(__file__).resolve().parent / "libs"
if _LIBS_DIR.is_dir() and str(_LIBS_DIR) not in sys.path:
    sys.path.insert(0, str(_LIBS_DIR))

from ClassWidgets.SDK import CW2Plugin, PluginAPI
from PySide6.QtCore import Signal, Slot

from authentication.config import Settings
from authentication.credentials import Credentials
from authentication.patches import PatchManager
from authentication.qml_window import RinAuthWindow
from authentication.ui import AuthDialogs


class Plugin(CW2Plugin):
    """Password/Windows Hello guard with reversible host hooks."""

    # The RinUI settings page binds to this to re-read state after every change.
    stateChanged = Signal()

    def __init__(self, api: PluginAPI):
        super().__init__(api)
        # SDK contract exposes PATH and api through CW2Plugin.
        self.api = api
        self._root = Path(getattr(self, "PATH", Path(__file__).resolve().parent))
        self.settings = Settings(self._root / "authentication.json")
        self.credentials = Credentials(self.settings)
        self.window: RinAuthWindow | None = None
        self.dialogs = AuthDialogs(self._main_window)
        self.patches = PatchManager()
        self._page_registered = False
        self._auth_inflight = False
        self._hello_busy = False
        self._recent_grant: dict[str, Any] = {"event": None, "t": 0.0}

    def _main_window(self):
        try:
            from PySide6.QtWidgets import QApplication
            return QApplication.activeWindow()
        except Exception:
            return None

    def _pump_until_finished(self, thread: threading.Thread) -> None:
        """Keep processing Qt/Windows messages while a WinRT call waits.

        Blocking the GUI thread outright makes the whole process look
        "not responding" while the Windows Hello consent dialog is open.
        """
        from PySide6.QtCore import QEventLoop, QTimer

        loop = QEventLoop()
        timer = QTimer()
        timer.setInterval(50)

        def check() -> None:
            if not thread.is_alive():
                loop.quit()

        timer.timeout.connect(check)
        timer.start()
        try:
            loop.exec()
        finally:
            timer.stop()

    def on_load(self) -> None:
        super().on_load()
        logger.info("Authentication plugin loading (plugin_id={})", self.meta.get("id", "unknown"))
        self._root = Path(self.PATH)
        self._initialize_settings_path()
        self._register_settings_page()
        self._install_host_hooks()
        if "hello" in self.settings.data["auth_methods"]:
            logger.info("Windows Hello availability: {}", self.credentials.hello_available(waiter=self._pump_until_finished))
        if self.settings.data["events"].get("startup"):
            if not self.authenticate("startup"):
                logger.error("Startup authentication cancelled or failed; exiting immediately")
                os._exit(0)
        logger.info("Authentication plugin loaded; methods={}, active_hooks={}", self.settings.data["auth_methods"], len(self.patches._originals))

    def _initialize_settings_path(self) -> None:
        try:
            from src.core.storage.directories import CONFIGS_PATH
            config_path = Path(CONFIGS_PATH) / "plugins" / "authentication.lyang1273.json"
        except ImportError:
            config_path = self._root / "authentication.json"
        self.settings = Settings(config_path)
        self.credentials = Credentials(self.settings)
        self.window = RinAuthWindow(self._root / "ui" / "AuthWindow.qml")
        self.dialogs = AuthDialogs(self._main_window, self.window)

    def on_unload(self) -> None:
        logger.info("Authentication plugin unloading")
        self.patches.restore()
        if self._page_registered:
            try:
                self.api.ui.unregister_settings_page("ui/Settings.qml")
            except Exception:
                pass
            self._page_registered = False
        super().on_unload()
        logger.info("Authentication plugin unloaded")

    def _settings_qml(self) -> Path:
        return self._root / "ui" / "Settings.qml"

    def _register_settings_page(self) -> None:
        try:
            self.api.ui.register_settings_page("ui/Settings.qml", title="Authentication", icon="ic_fluent_shield_lock_20_regular")
            self._page_registered = True
        except Exception as exc:
            logger.exception("Failed to register RinUI settings page: {}", exc)

    def _install_host_hooks(self) -> None:
        """Patch only verified application entry points when present.

        The host has no public interception API. Hooks are intentionally explicit
        and idempotent; missing methods are reported instead of silently claiming
        that a trigger is protected.
        """
        window_names = (("src.core.windows.manager", "AppWindowManager"),)
        candidates: dict[str, tuple[tuple[str, str, tuple[str, ...]], ...]] = {
            "install_uninstall": (("src.core.plugin.manager", "PluginManager",
                                   ("uninstallPlugin", "importPlugin", "importPluginWithPath",
                                    "installFromPlaza", "installPlazaUpdate", "setPluginEnabled")),),
            "update": (("src.core.updater.bridge", "UpdaterBridge", ("startInstall",)),),
            "exit": (("src.core.central", "AppCentral", ("quit", "restart")),),
        }
        import importlib
        patched_before = len(self.patches._originals)
        for module_name, class_name in window_names:
            try:
                owner = getattr(importlib.import_module(module_name), class_name)
            except (ImportError, AttributeError):
                logger.debug("Hook target not available: {}.{}", module_name, class_name)
                continue
            # 通用的 open(name) 统一挂在 AppWindowManager.open 上：钩子按窗口名
            # （settings / editor）查表，只有对应事件（settings 或 course_editor）
            # 启用时才验证，其他窗口（如插件广场）直接放行，避免事件互相串扰。
            # 不单独钩 open_settings/open_editor，因为它们在内部仍调用 open()，
            # 由统一钩子覆盖，且 3 秒同事件去重可消化重入。
            if self.patches.wrap(owner, "open", self._host_before_window_open):
                logger.info("Installed window-name filter authentication hook: AppWindowManager.open")
        for event, targets in candidates.items():
            if not self.settings.data["events"].get(event):
                continue
            for module_name, class_name, methods in targets:
                try:
                    owner = getattr(importlib.import_module(module_name), class_name)
                except (ImportError, AttributeError):
                    logger.debug("Hook target not available: {}.{}", module_name, class_name)
                    continue
                for name in methods:
                    if self.patches.wrap(owner, name, lambda *args, _event=event, _name=name, **kwargs: self._host_before(_event, _name, args, kwargs)):
                        logger.info("Installed {} authentication hook: {}.{}", event, class_name, name)
                    else:
                        logger.debug("{} hook skipped for {}.{} (already wrapped or missing)", event, class_name, name)
        # Parent classes are already imported by the host. Directly patch the
        # actual manager instance as well, so bound Qt-slot aliases are covered.
        app = getattr(self.api, "_app", None)
        direct_targets = (
            ("install_uninstall", getattr(getattr(app, "plugin_manager", None), "__class__", None),
             ("uninstallPlugin", "importPlugin", "importPluginWithPath",
              "installFromPlaza", "installPlazaUpdate", "setPluginEnabled")),
            ("update", getattr(getattr(app, "updater_bridge", None), "__class__", None), ("startInstall",)),
            ("exit", getattr(app, "__class__", None), ("quit", "restart")),
        )
        for event, owner, methods in direct_targets:
            if owner is None or not self.settings.data["events"].get(event):
                continue
            for name in methods:
                if self.patches.wrap(owner, name, lambda *args, _event=event, _name=name, **kwargs: self._host_before(_event, _name, args, kwargs)):
                    logger.info("Installed {} authentication hook on host instance class: {}.{}", event, owner.__name__, name)
        active = len(self.patches._originals) - patched_before
        installed = [getattr(owner, "__name__", str(owner)) + "." + name
                     for owner, name, _ in self.patches._originals[patched_before::]]
        logger.info("Hooked targets for event toggle state: {}", ", ".join(installed) if installed else "<none>")
        if active == 0 and any(value for key, value in self.settings.data["events"].items() if key != "startup"):
            logger.warning("Configured authentication triggers are enabled but no host hook was installed")

    def _before_host_event(self, event: str, *args: Any, **kwargs: Any) -> bool:
        # 开启“退出验证”时，AppCentral.quit/restart 在密码取消后必须不再继续。
        return self.authenticate(event)

    def _host_before(self, event: str, method: str, *args: Any, **kwargs: Any) -> bool:
        logger.info("Authentication hook fired: event={} method={}", event, method)
        if self._auth_inflight:
            # An authentication prompt is already on screen. Do not let
            # user clicks that land during the prompt (e.g. through the
            # GUI pump) authorize themselves.
            logger.debug("Nested authentication request for event={} denied while another prompt is active", event)
            return False
        now = time.monotonic()
        if event == self._recent_grant.get("event") and now - self._recent_grant.get("t", 0.0) < 3.0:
            # Same-chain re-entry (e.g. open_open_settings() calls open()): the
            # user already authorized this event a moment ago.
            return True
        parent = self._host_parent_for(method, args)
        self.dialogs.parent_provider = lambda: parent
        self._auth_inflight = True
        try:
            allowed = self.authenticate(event)
            if allowed:
                self._recent_grant = {"event": event, "t": time.monotonic()}
            return allowed
        finally:
            self._auth_inflight = False
            self.dialogs.parent_provider = self._main_window

    _WINDOW_NAME_EVENTS = {
        "settings": "settings",
        "editor": "course_editor",
    }

    def _host_before_window_open(self, *args: Any, **kwargs: Any) -> bool:
        """Guard for the generic AppWindowManager.open(name) entry point.

        The hook wraps the class-level method, so the first positional argument
        is the manager instance itself; the window name is the second one.
        Only requires authentication when the target window's event is enabled,
        so plugin_plaza or any other window passes through untouched.
        """
        name = args[1] if len(args) > 1 else kwargs.get("name")
        event = self._WINDOW_NAME_EVENTS.get(name)
        if event is None or not self.settings.data["events"].get(event):
            return True
        return self._host_before(event, "open", args, kwargs)

    def _host_parent_for(self, method: str, args: tuple[Any, ...]) -> Any:
        # open/open_settings/open_editor are wrapped on the class: args[0] is
        # the AppWindowManager instance, which holds the central app.
        if method in ("open", "open_settings", "open_editor") and args:
            return getattr(args[0], "central", None)
        if method in ("quit", "restart"):
            return args[0] if args else self.api._app if hasattr(self.api, "_app") else None
        if method in ("uninstallPlugin", "importPluginWithPath", "installFromPlaza", "installPlazaUpdate"):
            return getattr(self.api, "_app", None)
        return None

    _METHOD_LABELS = {
        "hello": "Windows Hello",
        "password": "密码",
    }

    def _verify_hello_guarded(self) -> bool:
        if self._hello_busy:
            logger.warning("Windows Hello verification already in progress; ignoring request")
            return False
        if not self.credentials.hello_available(waiter=self._pump_until_finished):
            return False
        self._hello_busy = True
        try:
            return self.credentials.verify_hello(waiter=self._pump_until_finished)
        finally:
            self._hello_busy = False

    def authenticate(self, event: str) -> bool:
        methods = [m for m in ("hello", "password") if m in self.settings.data.get("auth_methods", [])]
        logger.info("Authentication requested for event={} using methods={}", event, methods)
        if not methods:
            logger.warning("No usable authentication method configured; rejecting event={}", event)
            return False

        chosen = methods[0]
        if len(methods) > 1:
            options = [{"key": method, "label": self._METHOD_LABELS[method]} for method in methods]
            status, value = self.window.choose(
                "身份验证",
                "请选择一种验证方式以继续：",  # 去掉了事件名
                options,
            )
            if status != "ok" or not value:
                logger.debug("Method selection cancelled for event={}", event)
                return False
            chosen = value

        if chosen == "hello":
            if self._verify_hello_guarded():
                logger.info("Windows Hello authentication succeeded for event={}", event)
                return True
            logger.warning("Windows Hello authentication failed or cancelled for event={}", event)
            return False

        if not self.credentials.password_configured:
            logger.warning("Password authentication selected but no password exists")
            password = self.dialogs.password("设置验证密码", "首次使用，请设置密码：")
            if not password:
                logger.warning("Password setup cancelled for event={}", event)
                return False
            confirm = self.dialogs.confirm_password("确认验证密码", "请再次输入密码：", first_value=password)
            if confirm is None:
                logger.warning("Password setup cancelled during confirmation for event={}", event)
                return False
            self.credentials.set_password(password)
            logger.info("Password credential initialized")
            return True

        entered = self.dialogs.password(
            "确保那是你",
            "验证你的身份以继续使用 Class Widgets。",  # 去掉了事件名
            verifier=self.credentials.verify_password,
        )
        if entered is not None and self.credentials.verify_password(entered):
            logger.info("Password authentication succeeded for event={}", event)
            return True
        logger.warning("Password authentication failed or cancelled for event={}", event)
        return False

    # Settings.qml calls these invokable slots via the plugin QObject.
    def _notify_state_changed(self) -> None:
        try:
            self.stateChanged.emit()
        except (AttributeError, RuntimeError):
            # Standalone/dev SDK placeholder is not a QObject; nothing to notify.
            pass

    def _enable_method(self, method: str) -> None:
        methods = self.settings.data["auth_methods"]
        if method not in methods:
            methods.append(method)

    @Slot(str, result=bool)
    def add_auth_method(self, method: str) -> bool:
        if method not in ("password", "hello"):
            return False
        if method in self.settings.data["auth_methods"]:
            return True
        if method == "password" and not self.configure_password():
            return False
        if method == "hello" and not self._verify_hello_guarded():
            logger.warning("Could not add Windows Hello: unavailable or verification declined")
            return False
        self._enable_method(method)
        self.settings.save()
        logger.info("Added authentication method={}", method)
        self._notify_state_changed()
        return True

    @Slot(str, result=bool)
    def remove_auth_method(self, method: str) -> bool:
        if method not in self.settings.data["auth_methods"]:
            return True

        remaining = [item for item in self.settings.data["auth_methods"] if item != method]
        if not remaining and any(self.settings.data["events"].values()):
            logger.warning("Refused to remove last authentication method while events are enabled")
            self.dialogs.notify("至少保留一种认证方式，或先关闭所有触发验证的事件。")
            return False

        # 核心逻辑：移除前必须进行身份验证，防止被恶意篡改/移除
        logger.info("Authentication required to remove auth method={}", method)
        if not self.authenticate("remove_auth"):
            logger.warning("Removal of authentication method={} cancelled or failed during verification", method)
            return False

        # 验证通过，执行移除
        self.settings.data["auth_methods"] = remaining

        # 如果移除的是密码，彻底清空持久化的哈希和盐值
        if method == "password":
            self.settings.data["password_hash"] = ""
            self.settings.data["password_salt"] = ""

        self.settings.save()
        logger.info("Removed authentication method={}", method)
        self._notify_state_changed()
        return True

    @Slot(result=str)
    def get_auth_methods(self) -> str:
        return ",".join(self.settings.data.get("auth_methods", []))

    @Slot(str, result=bool)
    def has_auth_method(self, method: str) -> bool:
        return method in self.settings.data.get("auth_methods", [])

    @Slot(str, result=bool)
    def get_event_enabled(self, event: str) -> bool:
        return bool(self.settings.data["events"].get(event, False))

    @Slot(str, bool, result=bool)
    def set_event_enabled(self, event: str, enabled: bool) -> bool:
        if event not in self.settings.data["events"]:
            return False
        if enabled and not self.settings.data.get("auth_methods"):
            logger.warning("Refused to enable event={} without an authentication method", event)
            self.dialogs.notify("启用验证触发项前，请先添加至少一种认证方式。")
            self._notify_state_changed()
            return False
        self.settings.data["events"][event] = bool(enabled)
        self.settings.save()
        logger.info("Set authentication trigger {}={}", event, enabled)
        if event != "startup":
            self._refresh_host_hooks()
        self._notify_state_changed()
        return True

    def _refresh_host_hooks(self) -> None:
        self.patches.restore()
        self._install_host_hooks()

    @Slot(result=bool)
    def configure_password(self) -> bool:
        # 如果已经存在任何认证方式，必须先通过现有认证才能更改/添加密码
        if self.settings.data.get("auth_methods"):
            if not self.authenticate("change_password"):
                logger.warning("Password configuration cancelled during identity verification")
                return False

        current = self.dialogs.password("设置验证密码", "请输入新密码：")
        if not current:
            return False
        confirm = self.dialogs.confirm_password("好东西就要来了！", "请再次输入新密码以确认安全无虞。：", first_value=current)
        if confirm is None:
            logger.warning("Password setup confirmation cancelled")
            return False
        self.credentials.set_password(current)
        self._enable_method("password")
        self.settings.save()
        logger.info("Password credential configured")
        self._notify_state_changed()
        return True

    @Slot(result=bool)
    def get_password_configured(self) -> bool:
        return self.credentials.password_configured

    @Slot(result=bool)
    def hello_available(self) -> bool:
        return self.credentials.hello_available(waiter=self._pump_until_finished)