"""Password and Windows Hello authentication backends."""

from __future__ import annotations

import hashlib
import hmac
import secrets
import sys
import threading
from typing import Any

try:
    from loguru import logger
except ImportError:
    import logging
    logger = logging.getLogger("authentication")

_WIN32 = sys.platform == "win32"


def _run_fresh_thread(fn, waiter=None) -> tuple[str, Any]:
    """Run a blocking WinRT call in a fresh thread.

    A dedicated thread guarantees WinRT initializes a clean COM apartment
    regardless of the caller's threading context (e.g. the Qt GUI thread).
    ``waiter`` lets the caller keep the GUI responsive while the WinRT
    consent dialog is on screen; without it we simply join the thread.
    """
    outcome: list = []

    def run() -> None:
        try:
            outcome.append(("ok", fn()))
        except Exception as exc:
            logger.debug("Windows Hello call failed: {}", exc)
            outcome.append(("error", exc))

    worker = threading.Thread(target=run, daemon=True)
    worker.start()
    if waiter is not None:
        try:
            waiter(worker)
        except Exception:
            worker.join()
    else:
        worker.join()
    return outcome[0] if outcome else ("error", None)


def _user_consent_verifier():
    if not _WIN32:
        return None
    try:
        from winrt.windows.security.credentials.ui import UserConsentVerifier, UserConsentVerifierAvailability

        return UserConsentVerifier, UserConsentVerifierAvailability
    except Exception as exc:
        logger.debug("Windows Hello runtime unavailable: {}", exc)
        return None


class Credentials:
    def __init__(self, settings: Any):
        self.settings = settings

    @property
    def password_configured(self) -> bool:
        return bool(self.settings.data.get("password_hash") and self.settings.data.get("password_salt"))

    def set_password(self, password: str) -> None:
        salt = secrets.token_bytes(16)
        iterations = int(self.settings.data.get("iterations", 310_000))
        digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations)
        self.settings.data.update(password_salt=salt.hex(), password_hash=digest.hex(), iterations=iterations)
        self.settings.save()

    def verify_password(self, password: str) -> bool:
        try:
            digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), bytes.fromhex(self.settings.data["password_salt"]), int(self.settings.data["iterations"])).hex()
            return hmac.compare_digest(digest, self.settings.data["password_hash"])
        except (KeyError, TypeError, ValueError):
            return False

    @classmethod
    def hello_available(cls, waiter=None) -> bool:
        verifier = _user_consent_verifier()
        if verifier is None:
            return False
        user_consent, availability = verifier

        def check() -> bool:
            result = user_consent.check_availability_async().get()
            return result == availability.AVAILABLE

        state, value = _run_fresh_thread(check, waiter)
        return state == "ok" and bool(value)

    @classmethod
    def verify_hello(cls, waiter=None) -> bool:
        verifier = _user_consent_verifier()
        if verifier is None:
            return False
        user_consent, availability = verifier

        def verify() -> bool:
            result = user_consent.check_availability_async().get()
            if result != availability.AVAILABLE:
                logger.info("Windows Hello not available: {}", getattr(result, "name", result))
                return False
            outcome = user_consent.request_verification_async("Class Widgets 身份验证").get()
            status = getattr(outcome, "name", str(outcome)).split(".")[-1].lower()
            return status == "verified"

        state, value = _run_fresh_thread(verify, waiter)
        return state == "ok" and bool(value)
