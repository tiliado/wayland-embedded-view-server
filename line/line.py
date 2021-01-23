#!/usr/bin/env python3
import os
import mmap
import signal
from abc import ABC, abstractmethod
from typing import Union

from pywayland.client import Display
from pywayland.protocol.wayland import WlCompositor, WlShell, WlShm
from pywayland.utils import AnonymousFile

from lib.paint import LinePainter

# weston --debug -S wayland-weston
WAYLAND_DISPLAY = os.environ.get("DEMO_DISPLAY", os.environ.get("WAYLAND_DISPLAY", "wayland-weston"))
WIDTH = 200
HEIGHT = 100
MARGIN = 10

SHM_FORMAT = {
    WlShm.format.argb8888.value: "ARGB8888",
    WlShm.format.xrgb8888.value: "XRGB8888",
    WlShm.format.rgb565.value: "RGB565",
}


class Context:
    def __init__(self, display: Union[str, int]):
        self.display = Display(display)
        self.compositor = None
        self.shell = None
        self.shm = None

    def __del__(self):
        print("Disconnecting from", WAYLAND_DISPLAY)
        self.display.disconnect()

    def connect(self):
        print("Connecting to", WAYLAND_DISPLAY)
        self.display.connect()

        registry = self.display.get_registry()
        print(type(registry), registry)
        registry.dispatcher["global"] = self.on_global_object_added
        registry.dispatcher["global_remove"] = self.on_global_object_removed

        self.display.dispatch(block=True)
        self.display.roundtrip()

        assert all((self.compositor, self.shm)), (self.compositor, self.shell, self.shm)

    def run(self):
        while self.display.dispatch(block=True) != -1:
            pass

    def on_global_object_added(self, registry, object_id, interface, version):
        print("Global object added:", registry, object_id, interface, version)

        if interface == "wl_compositor":
            print("got compositor")
            self.compositor = registry.bind(object_id, WlCompositor, version)
        elif interface == "wl_shell":
            print("got shell")
            self.shell = registry.bind(object_id, WlShell, version)
        elif interface == "wl_shm":
            print("got shm")
            self.shm = registry.bind(object_id, WlShm, version)
            self.shm.dispatcher["format"] = self.on_shm_format

    def on_global_object_removed(self, registry, object_id):
        print("Global object removed:", registry, object_id)

    def on_shm_format(self, shm, shm_format):
        print("Possible shmem format: {}".format(SHM_FORMAT.get(shm_format, shm_format)))


class Window(ABC):
    def __init__(self, ctx: Context, width: int, height: int, scale: int, title: str = None):
        self.ctx = ctx
        self.width = width
        self.height = height
        self.scale = scale
        self.title = id(self) if title is None else title
        self.surface = None
        self.shell_surface = None
        self.shm_data = None
        self.buffer = None
        self._frame = None  # Holds reference

    @abstractmethod
    def paint(self, time: int):
        pass

    def redraw(self, time: int = 0) -> None:

        def frame_callback(callback, time):
            callback._destroy()
            self.redraw(time)

        self.paint(time)
        self.surface.damage(0, 0, self.width * self.scale, self.height * self.scale)
        self._frame = frame = self.surface.frame()
        frame.dispatcher["done"] = frame_callback
        self.surface.attach(self.buffer, 0, 0)
        self.surface.commit()

    def create(self) -> None:
        self.surface = self.ctx.compositor.create_surface()
        if self.ctx.shell is not None:
            self.shell_surface = self.ctx.shell.get_shell_surface(self.surface)
            self.shell_surface.set_toplevel()
            self.shell_surface.set_title(self.title)
            self.shell_surface.dispatcher["ping"] = lambda s, i: s.pong(i)
        self.buffer = self.create_buffer()
        self.redraw()

    def create_buffer(self):
        width = self.width * self.scale
        height = self.height * self.scale
        stride = width * 4
        size = stride * height

        with AnonymousFile(size) as fd:
            self.shm_data = mmap.mmap(
                fd, size, prot=mmap.PROT_READ | mmap.PROT_WRITE, flags=mmap.MAP_SHARED
            )
            pool = self.ctx.shm.create_pool(fd, size)
            buff = pool.create_buffer(0, width, height, stride, WlShm.format.argb8888.value)
            pool.destroy()
        return buff


class LineWindow(Window):
    def __init__(self, ctx: Context, width: int, height: int, title: str = None, margin: int = MARGIN, scale: int = 3):
        super().__init__(ctx, width, height, scale, title)
        self.painter = LinePainter(width, height, scale, margin)

    def paint(self, time: int):
        self.painter.paint(self.shm_data, time)


def main():
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    ctx = Context(WAYLAND_DISPLAY)
    ctx.connect()

    windows = [
        LineWindow(ctx, WIDTH, HEIGHT, "Widow 1"),
        LineWindow(ctx, WIDTH // 2, HEIGHT // 2, "Widow 2"),
    ]

    for window in windows:
        window.create()

    ctx.run()


if __name__ == "__main__":
    main()