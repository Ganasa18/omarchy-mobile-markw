# SPDX-License-Identifier: MIT
# Tests for bin/omamobile-hotspot's pure helpers; no D-Bus or NetworkManager
# needed. Run by test/all.
import importlib.machinery
import importlib.util
import os
import sys

here = os.path.dirname(os.path.abspath(__file__))
loader = importlib.machinery.SourceFileLoader("hotspot", os.path.join(here, "..", "bin", "omamobile-hotspot"))
spec = importlib.util.spec_from_loader("hotspot", loader)
hotspot = importlib.util.module_from_spec(spec)
loader.exec_module(hotspot)

failed = 0


def check(name, fn):
    global failed
    try:
        fn()
        print("ok - hotspot: " + name)
    except AssertionError as error:
        failed += 1
        print("not ok - hotspot: %s\n  %s" % (name, error), file=sys.stderr)


def names():
    assert hotspot.check_name("Redmi") == ""
    assert hotspot.check_name("") != ""
    assert hotspot.check_name("   ") != ""
    assert hotspot.check_name("x" * 32) == ""
    assert hotspot.check_name("x" * 33) != ""
    assert hotspot.check_name("é" * 17) != "", "the limit is 32 bytes, not characters"


def passwords():
    assert hotspot.check_password("12345678") == ""
    assert hotspot.check_password("1234567") == "At least 8 characters"
    assert hotspot.check_password("x" * 63) == ""
    assert hotspot.check_password("x" * 64) != ""
    assert hotspot.check_password("kata sandi!") == "", "spaces and symbols are fine"
    assert hotspot.check_password("sandiééé") != "", "WPA2 passphrases are printable ASCII"
    assert hotspot.check_password(None) != ""


def qr():
    assert hotspot.qr_text("Redmi", "kopi-pagi-2026") == "WIFI:T:WPA;S:Redmi;P:kopi-pagi-2026;;"
    assert hotspot.qr_text('a;b,c"d:e\\f', "p;w") == 'WIFI:T:WPA;S:a\\;b\\,c\\"d\\:e\\\\f;P:p\\;w;;'


def pmf():
    with_bip = "\tSupported Ciphers:\n\t\t* CCMP-128 (00-0f-ac:4)\n\t\t* CMAC (00-0f-ac:6)\n"
    without = "\tSupported Ciphers:\n\t\t* WEP40 (00-0f-ac:1)\n\t\t* TKIP (00-0f-ac:2)\n\t\t* CCMP-128 (00-0f-ac:4)\n"
    assert hotspot.pmf_for(with_bip) == hotspot.PMF_DEFAULT
    assert hotspot.pmf_for(without) == hotspot.PMF_DISABLE, "wcn36xx has no BIP: PMF off"


def defaults():
    assert hotspot.default_name("phone") == "Hotspot-phone"
    assert len(hotspot.default_name("x" * 40)) == 32
    password = hotspot.new_password()
    assert hotspot.check_password(password) == "" and len(password) == 12
    assert hotspot.new_password() != password


def stations():
    dump = "Station aa (on wlan0)\n\tinactive time: 10 ms\nStation bb (on wlan0)\n\trx bytes: 1\n"
    assert hotspot.count_stations(dump) == 2
    assert hotspot.count_stations("") == 0


def set_requests():
    assert hotspot.parse_set('{"name": "Redmi", "password": "12345678"}') == {"name": "Redmi", "password": "12345678"}
    assert hotspot.parse_set('{"password": "12345678"}') == {"password": "12345678"}
    for bad, reason in (('{"password": "short"}', "At least 8 characters"), ("{}", "Nothing to change"),
                        ("nope", "Not JSON"), ("[1]", "Not an object"), ('{"name": ""}', "Enter a name")):
        try:
            hotspot.parse_set(bad)
        except ValueError as error:
            assert str(error) == reason, "%s: %s" % (bad, error)
        else:
            raise AssertionError("accepted " + bad)


def no_secret_in_argv():
    source = open(os.path.join(here, "..", "bin", "omamobile-hotspot")).read()
    for line in source.splitlines():
        if "run([" in line and ("password" in line or "psk" in line or "text" in line.split("run([", 1)[1].split("]")[0]):
            raise AssertionError("a secret in a command line: " + line.strip())


for name, fn in (("names", names), ("passwords", passwords), ("QR text", qr), ("PMF from the radio's ciphers", pmf),
                 ("default name and password", defaults), ("station count", stations),
                 ("set requests", set_requests), ("no secret in argv", no_secret_in_argv)):
    check(name, fn)
sys.exit(1 if failed else 0)
