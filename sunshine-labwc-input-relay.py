#!/usr/bin/env python3
"""
sunshine-labwc-input-relay.py

Exclusively grabs Sunshine's uinput devices (Mouse passthrough, Keyboard passthrough,
and any virtual gamepads) and forwards their events into labwc:
  - Mouse/keyboard → zwlr_virtual_pointer_v1 / zwp_virtual_keyboard_v1 (Wayland)
  - Gamepads       → new uinput device (passthrough; readable by apps in labwc)

Requires: python-evdev, python-pywayland, libxkbcommon
User must be in the 'input' group: sudo usermod -aG input $USER
"""

import os
import sys
import signal
import time
import select
import ctypes
import ctypes.util
import subprocess
import struct
from pathlib import Path

try:
    import evdev
    from evdev import ecodes
except ImportError:
    sys.exit("python-evdev not installed")

try:
    from pywayland.client import Display
    from pywayland.protocol.wayland import WlSeat
except ImportError:
    sys.exit("python-pywayland not installed")

# ---------------------------------------------------------------------------
# Embedded protocol XMLs (wlroots unstable protocols not bundled in pywayland)
# ---------------------------------------------------------------------------

_VP_XML = """\
<?xml version="1.0" encoding="UTF-8"?>
<protocol name="wlr_virtual_pointer_unstable_v1">
  <interface name="zwlr_virtual_pointer_v1" version="2">
    <request name="motion">
      <arg name="time" type="uint" summary="timestamp with millisecond granularity"/>
      <arg name="dx" type="fixed" summary="delta x by which pointer has moved"/>
      <arg name="dy" type="fixed" summary="delta y by which pointer has moved"/>
    </request>
    <request name="motion_absolute">
      <arg name="time" type="uint" summary="timestamp with millisecond granularity"/>
      <arg name="x" type="uint" summary="position on x axis"/>
      <arg name="y" type="uint" summary="position on y axis"/>
      <arg name="x_extent" type="uint" summary="extent of x axis"/>
      <arg name="y_extent" type="uint" summary="extent of y axis"/>
    </request>
    <request name="button">
      <arg name="time" type="uint" summary="timestamp with millisecond granularity"/>
      <arg name="button" type="uint" summary="button that produced the event"/>
      <arg name="state" type="uint" summary="physical state of the button"/>
    </request>
    <request name="axis">
      <arg name="time" type="uint" summary="timestamp with millisecond granularity"/>
      <arg name="axis" type="uint" summary="axis type"/>
      <arg name="value" type="fixed" summary="length of vector in touchpad coordinates"/>
    </request>
    <request name="frame" summary="end of a pointer event sequence"/>
    <request name="axis_source">
      <arg name="axis_source" type="uint" summary="source of the axis event"/>
    </request>
    <request name="axis_stop">
      <arg name="time" type="uint" summary="timestamp with millisecond granularity"/>
      <arg name="axis" type="uint" summary="the axis stopped with this event"/>
    </request>
    <request name="axis_discrete">
      <arg name="time" type="uint" summary="timestamp with millisecond granularity"/>
      <arg name="axis" type="uint" summary="axis type"/>
      <arg name="value" type="fixed" summary="length of vector in touchpad coordinates"/>
      <arg name="discrete" type="int" summary="number of steps"/>
    </request>
    <request name="destroy" type="destructor" since="2"/>
  </interface>
  <interface name="zwlr_virtual_pointer_manager_v1" version="2">
    <request name="create_virtual_pointer">
      <arg name="seat" type="object" interface="wl_seat" allow-null="true"
           summary="seat to associate the pointer with"/>
      <arg name="id" type="new_id" interface="zwlr_virtual_pointer_v1"/>
    </request>
    <request name="create_virtual_pointer_with_output" since="2">
      <arg name="seat" type="object" interface="wl_seat" allow-null="true"/>
      <arg name="output" type="object" interface="wl_output" allow-null="true"/>
      <arg name="id" type="new_id" interface="zwlr_virtual_pointer_v1"/>
    </request>
    <request name="destroy" type="destructor" since="2"/>
  </interface>
</protocol>
"""

_VK_XML = """\
<?xml version="1.0" encoding="UTF-8"?>
<protocol name="virtual_keyboard_unstable_v1">
  <interface name="zwp_virtual_keyboard_v1" version="1">
    <request name="keymap">
      <arg name="format" type="uint" summary="keymap format"/>
      <arg name="fd" type="fd" summary="keymap file descriptor"/>
      <arg name="size" type="uint" summary="keymap size, in bytes"/>
    </request>
    <request name="key">
      <arg name="time" type="uint" summary="timestamp with millisecond granularity"/>
      <arg name="key" type="uint" summary="key that produced the event"/>
      <arg name="state" type="uint" summary="physical state of the key"/>
    </request>
    <request name="modifiers">
      <arg name="mods_depressed" type="uint" summary="depressed modifiers"/>
      <arg name="mods_latched" type="uint" summary="latched modifiers"/>
      <arg name="mods_locked" type="uint" summary="locked modifiers"/>
      <arg name="group" type="uint" summary="keyboard layout"/>
    </request>
    <request name="destroy" type="destructor"/>
  </interface>
  <interface name="zwp_virtual_keyboard_manager_v1" version="1">
    <request name="create_virtual_keyboard">
      <arg name="seat" type="object" interface="wl_seat"
           summary="seat to associate the keyboard with"/>
      <arg name="id" type="new_id" interface="zwp_virtual_keyboard_v1"/>
    </request>
  </interface>
</protocol>
"""

# ---------------------------------------------------------------------------
# Generate and import protocol bindings at runtime
# ---------------------------------------------------------------------------

def _scan_protocols(cache_dir: Path) -> tuple:
    """Run pywayland scanner on the embedded XMLs if needed; import results.

    The scanner generates packages with relative imports like ``from ..wayland``.
    Python forbids relative imports that cross the top-level package boundary,
    so we nest everything inside a dummy parent package ``_p`` and add
    cache_dir to sys.path — the ``..wayland`` then resolves to ``_p.wayland``.
    """
    parent = cache_dir / "_p"
    vp_dir = parent / "wlr_virtual_pointer_unstable_v1"
    vk_dir = parent / "virtual_keyboard_unstable_v1"

    if not vp_dir.exists() or not vk_dir.exists():
        parent.mkdir(parents=True, exist_ok=True)
        (parent / "__init__.py").write_text("")  # make it a package

        vp_xml = cache_dir / "vp.xml"
        vk_xml = cache_dir / "vk.xml"
        vp_xml.write_text(_VP_XML)
        vk_xml.write_text(_VK_XML)

        wl_xml = "/usr/share/wayland/wayland.xml"
        # Scan each XML separately — the scanner silently drops protocols when
        # multiple custom XMLs share the same output directory in one call.
        for xml in [str(vp_xml), str(vk_xml)]:
            subprocess.check_call(
                [sys.executable, "-m", "pywayland.scanner",
                 "-i", xml, wl_xml, "-o", str(parent)],
                stderr=subprocess.DEVNULL
            )

    # Add cache_dir so ``_p`` is a top-level importable package.
    cache_str = str(cache_dir)
    if cache_str not in sys.path:
        sys.path.insert(0, cache_str)

    import _p.wlr_virtual_pointer_unstable_v1.zwlr_virtual_pointer_manager_v1 as _vpm
    import _p.wlr_virtual_pointer_unstable_v1.zwlr_virtual_pointer_v1 as _vp
    import _p.virtual_keyboard_unstable_v1.zwp_virtual_keyboard_manager_v1 as _vkm
    import _p.virtual_keyboard_unstable_v1.zwp_virtual_keyboard_v1 as _vk

    return (
        _vpm.ZwlrVirtualPointerManagerV1,
        _vp.ZwlrVirtualPointerV1,
        _vkm.ZwpVirtualKeyboardManagerV1,
        _vk.ZwpVirtualKeyboardV1,
    )

# ---------------------------------------------------------------------------
# XKB keymap via libxkbcommon
# ---------------------------------------------------------------------------

def _get_xkb_keymap_fd() -> tuple[int, int]:
    """Return (fd, size) for a memfd containing the default XKB keymap."""
    libxkb_name = ctypes.util.find_library("xkbcommon")
    if not libxkb_name:
        raise RuntimeError("libxkbcommon not found")
    libxkb = ctypes.CDLL(libxkb_name)

    libxkb.xkb_context_new.restype = ctypes.c_void_p
    libxkb.xkb_context_new.argtypes = [ctypes.c_uint]
    libxkb.xkb_keymap_new_from_names.restype = ctypes.c_void_p
    libxkb.xkb_keymap_new_from_names.argtypes = [
        ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint]
    libxkb.xkb_keymap_get_as_string.restype = ctypes.c_char_p
    libxkb.xkb_keymap_get_as_string.argtypes = [ctypes.c_void_p, ctypes.c_uint]
    libxkb.xkb_keymap_unref.argtypes = [ctypes.c_void_p]
    libxkb.xkb_context_unref.argtypes = [ctypes.c_void_p]

    ctx = libxkb.xkb_context_new(0)  # XKB_CONTEXT_NO_FLAGS
    if not ctx:
        raise RuntimeError("xkb_context_new failed")

    keymap_ptr = libxkb.xkb_keymap_new_from_names(ctx, None, 0)
    if not keymap_ptr:
        raise RuntimeError("xkb_keymap_new_from_names failed")

    # XKB_KEYMAP_FORMAT_TEXT_V1 = 1
    keymap_str = libxkb.xkb_keymap_get_as_string(keymap_ptr, 1)
    keymap_bytes = keymap_str + b'\x00'  # include NUL terminator

    libxkb.xkb_keymap_unref(keymap_ptr)
    libxkb.xkb_context_unref(ctx)

    libc = ctypes.CDLL(None)
    libc.memfd_create.restype = ctypes.c_int
    libc.memfd_create.argtypes = [ctypes.c_char_p, ctypes.c_uint]
    fd = libc.memfd_create(b"xkb-keymap", 0)
    if fd < 0:
        raise RuntimeError("memfd_create failed")

    os.write(fd, keymap_bytes)
    os.lseek(fd, 0, os.SEEK_SET)
    return fd, len(keymap_bytes)

# ---------------------------------------------------------------------------
# Find Sunshine input devices via /proc/bus/input/devices
# ---------------------------------------------------------------------------

# Polaris uses "Polaris Mouse passthrough" / "Polaris Keyboard passthrough".
# Upstream Sunshine uses "Mouse passthrough" / "Keyboard passthrough".
# Keep both so the relay works with either server.
_SUNSHINE_DEVICE_NAMES = {
    "Mouse passthrough",
    "Mouse passthrough (absolute)",
    "Keyboard passthrough",
    "Polaris Mouse passthrough",
    "Polaris Keyboard passthrough",
    "Touch passthrough",
    "Pen passthrough",
}

# Buttons that indicate a gamepad (any of these being present is enough).
_GAMEPAD_BTN_INDICATORS = {
    ecodes.BTN_SOUTH,       # A on Xbox, Cross on DS
    ecodes.BTN_GAMEPAD,     # alias for BTN_SOUTH on some kernels
    ecodes.BTN_JOYSTICK,    # older joystick style
}

def _is_virtual_gamepad(path: str) -> bool:
    """Return True if the device at path looks like a virtual (uinput) gamepad."""
    try:
        dev = evdev.InputDevice(path)
        caps = dev.capabilities()
        dev.close()
    except Exception:
        return False

    btn_keys = set(caps.get(ecodes.EV_KEY, []))
    abs_axes = {a[0] if isinstance(a, tuple) else a
                for a in caps.get(ecodes.EV_ABS, [])}

    has_gamepad_btn = bool(btn_keys & _GAMEPAD_BTN_INDICATORS)
    has_sticks = bool(abs_axes & {ecodes.ABS_X, ecodes.ABS_Y,
                                   ecodes.ABS_RX, ecodes.ABS_RY})
    return has_gamepad_btn and has_sticks


def _find_sunshine_devices() -> dict[str, str]:
    """Parse /proc/bus/input/devices; return {name: /dev/input/eventN}.

    Returns known Sunshine mouse/keyboard devices by exact name, plus any
    virtual (uinput-backed) gamepad devices keyed as 'gamepad:<name>'.
    Virtual devices are identified by their sysfs path containing
    '/virtual/input/' — real hardware never has that.
    """
    found: dict[str, str] = {}
    cur_name = cur_event = cur_sysfs = None

    def _commit():
        nonlocal cur_name, cur_event, cur_sysfs
        if not cur_name or not cur_event:
            cur_name = cur_event = cur_sysfs = None
            return
        path = f"/dev/input/{cur_event}"
        if cur_name in _SUNSHINE_DEVICE_NAMES:
            found[cur_name] = path
        elif cur_sysfs and "/virtual/input/" in cur_sysfs:
            if _is_virtual_gamepad(path):
                found[f"gamepad:{cur_name}"] = path
        cur_name = cur_event = cur_sysfs = None

    try:
        with open("/proc/bus/input/devices") as f:
            for line in f:
                line = line.rstrip()
                if line.startswith("N: Name="):
                    _commit()
                    cur_name = line[8:].strip('"')
                elif line.startswith("S: Sysfs="):
                    cur_sysfs = line[9:].strip()
                elif line.startswith("H: Handlers="):
                    for tok in line[12:].split():
                        if tok.startswith("event"):
                            cur_event = tok
                            break
                elif line == "":
                    _commit()
        _commit()
    except OSError:
        pass

    return found

# ---------------------------------------------------------------------------
# Wayland registry helper
# ---------------------------------------------------------------------------

def _collect_globals(display: Display) -> dict[str, tuple[int, int]]:
    """Return {interface_name: (id, version)} from the registry."""
    result = {}

    def _on_global(registry, id_, name, version):
        result[name] = (id_, version)

    registry = display.get_registry()
    registry.dispatcher["global"] = _on_global
    display.roundtrip()
    return result

# ---------------------------------------------------------------------------
# Input event relay
# ---------------------------------------------------------------------------

def _ms() -> int:
    return int(time.monotonic() * 1000) & 0xFFFFFFFF

_BTN_CODES = {ecodes.BTN_LEFT, ecodes.BTN_RIGHT, ecodes.BTN_MIDDLE,
              ecodes.BTN_SIDE, ecodes.BTN_EXTRA, ecodes.BTN_FORWARD,
              ecodes.BTN_BACK, ecodes.BTN_TASK}


class InputRelay:
    def __init__(self, wayland_socket: str):
        self.wayland_socket = wayland_socket
        self._vpointer = None
        self._vkeyboard = None
        self._display = None
        # mouse + keyboard devices
        self._devices: list[evdev.InputDevice] = []
        # gamepad device → its uinput passthrough clone
        self._gamepad_relays: dict[evdev.InputDevice, evdev.UInput] = {}
        # paths already grabbed (avoid double-grab on rescan)
        self._grabbed_paths: set[str] = set()
        self._pending_abs: dict = {}

    def _open_devices(self, dev_map: dict[str, str]):
        for name, path in dev_map.items():
            if path in self._grabbed_paths:
                continue
            try:
                dev = evdev.InputDevice(path)
                dev.grab()
                self._grabbed_paths.add(path)

                if name.startswith("gamepad:"):
                    real_name = name[8:]
                    try:
                        # Clone all capabilities; new device is visible to
                        # apps inside labwc (e.g. Steam under gamescope).
                        ui = evdev.UInput.from_device(dev,
                                                      name=f"labwc:{real_name}")
                        self._gamepad_relays[dev] = ui
                        print(f"[relay] grabbed gamepad {path} ({real_name}), "
                              f"re-emitting via uinput as 'labwc:{real_name}'",
                              flush=True)
                    except Exception as e:
                        print(f"[relay] WARN: UInput clone failed for {path}: {e}",
                              flush=True)
                        # Grab without relay so KDE at least doesn't see it.
                        self._devices.append(dev)
                else:
                    self._devices.append(dev)
                    print(f"[relay] grabbed {path} ({name})", flush=True)

            except PermissionError:
                print(f"[relay] WARN: no permission for {path}; "
                      "add user to 'input' group", flush=True)
            except Exception as e:
                print(f"[relay] WARN: could not grab {path}: {e}", flush=True)

    def _rescan_gamepads(self):
        """Check for newly connected Sunshine gamepads and grab them."""
        dev_map = _find_sunshine_devices()
        new = {k: v for k, v in dev_map.items()
               if k.startswith("gamepad:") and v not in self._grabbed_paths}
        if new:
            self._open_devices(new)

    def _connect_wayland(self, protocols_cache: Path):
        (ZwlrVPManager, ZwlrVP,
         ZwpVKManager, ZwpVK) = _scan_protocols(protocols_cache)

        self._display = Display(self.wayland_socket)
        self._display.connect()

        globals_map = _collect_globals(self._display)
        reg = self._display.get_registry()

        seat = None
        if "wl_seat" in globals_map:
            id_, ver = globals_map["wl_seat"]
            seat = reg.bind(id_, WlSeat, min(ver, WlSeat.version))

        vp_mgr = None
        if "zwlr_virtual_pointer_manager_v1" in globals_map:
            id_, ver = globals_map["zwlr_virtual_pointer_manager_v1"]
            vp_mgr = reg.bind(id_, ZwlrVPManager,
                              min(ver, ZwlrVPManager.version))

        vk_mgr = None
        if "zwp_virtual_keyboard_manager_v1" in globals_map:
            id_, ver = globals_map["zwp_virtual_keyboard_manager_v1"]
            vk_mgr = reg.bind(id_, ZwpVKManager,
                              min(ver, ZwpVKManager.version))

        self._display.roundtrip()

        if vp_mgr:
            self._vpointer = vp_mgr.create_virtual_pointer(seat)
            print("[relay] virtual pointer created", flush=True)

        if vk_mgr and seat:
            self._vkeyboard = vk_mgr.create_virtual_keyboard(seat)
            try:
                fd, size = _get_xkb_keymap_fd()
                self._vkeyboard.keymap(1, fd, size)
                os.close(fd)
                print("[relay] virtual keyboard created + keymap sent", flush=True)
            except Exception as e:
                print(f"[relay] WARN: keymap failed: {e}", flush=True)
        elif vk_mgr and not seat:
            print("[relay] WARN: no wl_seat; keyboard relay disabled", flush=True)

        self._display.flush()

    def _dispatch_evdev_event(self, event: evdev.InputEvent,
                               source_dev: evdev.InputDevice):
        # Gamepad: verbatim passthrough to uinput clone.
        if source_dev in self._gamepad_relays:
            ui = self._gamepad_relays[source_dev]
            try:
                ui.write(event.type, event.code, event.value)
            except Exception:
                pass
            return

        # Mouse / keyboard forwarding via Wayland virtual devices.
        t = _ms()
        vp = self._vpointer
        vk = self._vkeyboard

        if event.type == ecodes.EV_REL and vp:
            if event.code == ecodes.REL_X:
                vp.motion(t, event.value, 0)
                vp.frame()
                self._display.flush()
            elif event.code == ecodes.REL_Y:
                vp.motion(t, 0, event.value)
                vp.frame()
                self._display.flush()
            elif event.code == ecodes.REL_WHEEL:
                vp.axis(t, 0, -event.value * 10)
                vp.frame()
                self._display.flush()
            elif event.code == ecodes.REL_HWHEEL:
                vp.axis(t, 1, event.value * 10)
                vp.frame()
                self._display.flush()

        elif event.type == ecodes.EV_ABS and vp:
            if event.code == ecodes.ABS_X:
                self._pending_abs["x"] = event.value
            elif event.code == ecodes.ABS_Y:
                self._pending_abs["y"] = event.value

        elif event.type == ecodes.EV_SYN and vp:
            if event.code == ecodes.SYN_REPORT and self._pending_abs:
                x = self._pending_abs.get("x", 0)
                y = self._pending_abs.get("y", 0)
                vp.motion_absolute(t, x, y, 65535, 65535)
                vp.frame()
                self._pending_abs.clear()
                self._display.flush()

        elif event.type == ecodes.EV_KEY:
            code = event.code
            state = event.value  # 0=up, 1=down, 2=repeat

            if code in _BTN_CODES and vp:
                if state != 2:
                    vp.button(t, code, state)
                    vp.frame()
                    self._display.flush()
            elif vk:
                wl_state = 1 if state >= 1 else 0
                vk.key(t, code, wl_state)
                self._display.flush()

    def run(self, protocols_cache: Path):
        # Wait indefinitely for the streaming server's core input devices.
        # They appear when the server starts (or when it first accepts a client
        # on some builds), so there is no useful upper bound on wait time.
        print("[relay] waiting for streaming server input devices…", flush=True)
        dev_map: dict[str, str] = {}
        while not any(not k.startswith("gamepad:") for k in dev_map):
            dev_map = _find_sunshine_devices()
            if not any(not k.startswith("gamepad:") for k in dev_map):
                time.sleep(5)

        self._open_devices(dev_map)
        if not self._devices:
            print("[relay] could not open any device; aborting", flush=True)
            sys.exit(1)

        self._connect_wayland(protocols_cache)
        if not self._vpointer and not self._vkeyboard:
            print("[relay] no virtual devices created; aborting", flush=True)
            sys.exit(1)

        wayland_fd = self._display.get_fd()

        def _build_fds() -> dict[int, evdev.InputDevice]:
            fds = {dev.fd: dev for dev in self._devices}
            fds.update({dev.fd: dev for dev in self._gamepad_relays})
            return fds

        dev_fds = _build_fds()
        all_fds = list(dev_fds) + [wayland_fd]

        print("[relay] running — forwarding input to labwc", flush=True)
        if self._gamepad_relays:
            print(f"[relay] {len(self._gamepad_relays)} gamepad(s) relayed via uinput",
                  flush=True)

        def _cleanup(signo=None, frame=None):
            for dev in self._devices:
                try:
                    dev.ungrab()
                    dev.close()
                except Exception:
                    pass
            for dev, ui in self._gamepad_relays.items():
                try:
                    dev.ungrab()
                    dev.close()
                except Exception:
                    pass
                try:
                    ui.close()
                except Exception:
                    pass
            if self._vpointer:
                try:
                    self._vpointer.destroy()
                except Exception:
                    pass
            if self._display:
                try:
                    self._display.disconnect()
                except Exception:
                    pass
            sys.exit(0)

        signal.signal(signal.SIGTERM, _cleanup)
        signal.signal(signal.SIGINT, _cleanup)

        last_rescan = time.monotonic()

        while True:
            try:
                rlist, _, _ = select.select(all_fds, [], [], 5.0)
            except (OSError, ValueError):
                break

            # Periodic rescan: pick up gamepads that appear after client connects.
            now = time.monotonic()
            if now - last_rescan >= 5.0:
                prev_count = len(self._gamepad_relays)
                self._rescan_gamepads()
                if len(self._gamepad_relays) != prev_count:
                    dev_fds = _build_fds()
                    all_fds = list(dev_fds) + [wayland_fd]
                    print(f"[relay] {len(self._gamepad_relays)} gamepad(s) now active",
                          flush=True)
                last_rescan = now

            for fd in rlist:
                if fd == wayland_fd:
                    self._display.dispatch(block=False)
                elif fd in dev_fds:
                    dev = dev_fds[fd]
                    try:
                        for event in dev.read():
                            self._dispatch_evdev_event(event, dev)
                    except OSError:
                        print(f"[relay] device {dev.path} lost", flush=True)
                        dev_fds.pop(fd, None)
                        all_fds = [f for f in all_fds if f != fd]
                        if not dev_fds:
                            print("[relay] all devices lost; exiting", flush=True)
                            _cleanup()

        _cleanup()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    wayland_socket = os.environ.get("WAYLAND_DISPLAY", "wayland-stream")
    cache_dir = Path(os.environ.get("XDG_RUNTIME_DIR",
                                    f"/run/user/{os.getuid()}")) / "sunshine-labwc" / "protocols"
    cache_dir.mkdir(parents=True, exist_ok=True)

    relay = InputRelay(wayland_socket)
    relay.run(cache_dir)
