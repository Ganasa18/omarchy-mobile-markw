#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Host tests for cleanup after watchdog inspection fails; never opens hardware."""
import importlib.machinery
import importlib.util
from pathlib import Path
import struct
import unittest
from contextlib import contextmanager
import tempfile
from types import SimpleNamespace
from unittest.mock import patch

path = Path(__file__).resolve().parents[4] / "tools/markw-watchdog-feed"
loader = importlib.machinery.SourceFileLoader("watchdog_feed", str(path))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


class CleanupTests(unittest.TestCase):
    def test_inspection_failure_still_disables_magic_closes_and_closes_fd(self):
        events = []

        def ioctl(fd, command, data, *args):
            events.append(("ioctl", command))
            if command == 0x80285700:
                raise OSError("inspection failed")
            return 0

        # create=True allows the initial stub to demonstrate missing cleanup.
        with patch.object(module, "os", create=True) as os_mock, \
                patch.object(module, "fcntl", create=True) as fcntl_mock:
            os_mock.open.return_value = 7
            os_mock.write.side_effect = lambda fd, data: events.append(("write", data))
            os_mock.close.side_effect = lambda fd: events.append(("close", fd))
            fcntl_mock.ioctl.side_effect = ioctl
            with self.assertRaisesRegex(OSError, "inspection failed"):
                with module.Watchdog():
                    pass
        self.assertIn(("ioctl", 0x80045704), events)
        self.assertIn(("write", b"V"), events)
        self.assertIn(("close", 7), events)

    def test_success_checks_identity_timeout_pings_and_disarms(self):
        events = []

        def ioctl(fd, command, data, *args):
            events.append(("ioctl", command))
            if command == 0x80285700:
                data[:] = struct.pack("II32s", 0x100, 0, b"qcom_wdt")
            if command == 0x80045707:
                data[0] = 30
            return 0

        with patch.object(module, "os", create=True) as os_mock, \
                patch.object(module, "fcntl", create=True) as fcntl_mock:
            os_mock.open.return_value = 7
            os_mock.write.side_effect = lambda fd, data: events.append(("write", data))
            os_mock.close.side_effect = lambda fd: events.append(("close", fd))
            fcntl_mock.ioctl.side_effect = ioctl
            with module.Watchdog() as watchdog:
                self.assertEqual(watchdog.identity, "qcom_wdt")
                self.assertEqual(watchdog.timeout, 30)
                watchdog.ping()
        self.assertIn(("ioctl", 0x80045705), events)
        self.assertEqual(events[-2:], [("write", b"V"), ("close", 7)])


class MainTests(unittest.TestCase):
    @contextmanager
    def session(self):
        handlers = {}
        fake_signal = SimpleNamespace(SIGTERM=15, SIGINT=2, SIGHUP=1,
                                      signal=lambda sig, handler: handlers.update({sig: handler}))
        fake_time = SimpleNamespace(CLOCK_BOOTTIME=7, clock_gettime=lambda clock: 1,
                                   sleep=lambda seconds: handlers[15](15, None))
        with tempfile.TemporaryDirectory() as tmp, \
                patch.object(module, "PIDFILE", Path(tmp) / "pid"), \
                patch.object(module, "preflight"), \
                patch.object(module, "fcntl", object()), \
                patch.object(module, "signal", fake_signal), \
                patch.object(module, "time", fake_time), \
                patch.object(module.sys, "argv", ["watchdog-feed", "--seconds", "5"]), \
                patch.object(module, "Watchdog") as watchdog, \
                patch("builtins.print"):
            watchdog.return_value.__enter__.return_value.identity = "qcom_wdt"
            watchdog.return_value.__enter__.return_value.timeout = 30
            yield module.PIDFILE, watchdog

    def test_failed_open_removes_own_pid(self):
        with self.session() as (pid, watchdog):
            watchdog.return_value.__enter__.side_effect = OSError("open failed")
            with self.assertRaisesRegex(OSError, "open failed"):
                module.main()
            self.assertFalse(pid.exists())

    def test_failed_ping_exits_context_and_removes_own_pid(self):
        with self.session() as (pid, watchdog):
            watchdog.return_value.__enter__.return_value.ping.side_effect = OSError("ping failed")
            with self.assertRaisesRegex(OSError, "ping failed"):
                module.main()
            watchdog.return_value.__exit__.assert_called_once()
            self.assertFalse(pid.exists())

    def test_term_exits_context_and_removes_own_pid(self):
        with self.session() as (pid, watchdog):
            module.main()
            watchdog.return_value.__exit__.assert_called_once()
            self.assertFalse(pid.exists())

    def test_read_only_check_never_opens_watchdog(self):
        with self.session() as (pid, watchdog), \
                patch.object(module.sys, "argv", ["watchdog-feed", "--check"]):
            module.main()
            watchdog.assert_not_called()
            self.assertFalse(pid.exists())


if __name__ == "__main__":
    unittest.main()
