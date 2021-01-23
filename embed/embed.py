#!/usr/bin/env python3
import mmap
import os
import signal
from typing import Union

from pywayland.client import Display
from pywayland.utils import AnonymousFile

from lib.paint import LinePainter
from wl_protocols.wayland import WlCompositor, WlShm

from wl_protocols.wevp_embed import WevpEmbedder

WAYLAND_DISPLAY = os.environ.get("DEMO_DISPLAY", os.environ.get("WAYLAND_DISPLAY", "wevf-demo"))

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
        self.shm = None
        self.embedder = None
        self.views = {}

    def __del__(self):
        print("Disconnecting from", WAYLAND_DISPLAY)
        self.display.disconnect()

    def connect(self):
        print("Connecting to", WAYLAND_DISPLAY)
        self.display.connect()

        registry = self.display.get_registry()
        registry.dispatcher["global"] = self.on_global_object_added
        registry.dispatcher["global_remove"] = self.on_global_object_removed

        self.display.dispatch(block=True)
        self.display.roundtrip()

    def run(self):
        while self.display.dispatch(block=True) != -1:
            pass

    def on_global_object_added(self, registry, object_id, interface, version):
        print("Global object added:", registry, object_id, interface, version)

        if interface == "wl_compositor":
            print("got compositor")
            self.compositor = registry.bind(object_id, WlCompositor, version)
        elif interface == "wl_shm":
            print("got shm")
            self.shm = registry.bind(object_id, WlShm, version)
            self.shm.dispatcher["format"] = self.on_shm_format
        elif interface == "wevp_embedder":
            print("got embeder")
            self.embedder = registry.bind(object_id, WevpEmbedder, version)
            self.embedder.dispatcher["ping"] = self.on_ping
            self.embedder.dispatcher["view_requested"] = self.on_view_requested

    def on_global_object_removed(self, registry, object_id):
        print("Global object removed:", registry, object_id)

    def on_shm_format(self, shm, shm_format):
        print("Possible shmem format: {}".format(SHM_FORMAT.get(shm_format, shm_format)))

    def on_ping(self, embeder, serial):
        embeder.pong(serial)

    def on_view_requested(self, embedder, serial, width, height, scale):
        print("Request new view", serial, width, height, scale)
        surface = self.compositor.create_surface()
        view = embedder.create_view(serial, surface, width, height, scale)
        self.views[view] = View(self.shm, view, surface, width, height, scale)


class View:
    def __init__(self, shm, view, surface, width, height, scale):
        self.shm = shm
        self.view = view
        self.surface = surface
        self.width = width
        self.height = height
        self.scale = scale
        self.shm_data = None
        self.buffer = None
        self.frame = None
        self.last_time = 0

        self.painter = LinePainter(width, height, scale, 5)

        view.dispatcher["resized"] = self.on_resized
        view.dispatcher["rescaled"] = self.on_rescaled

        self.create_buffer()
        self.redraw()

    def redraw(self, time: int = None):
        if time is None:
            time = self.last_time
        else:
            self.last_time = time
        self.render(time)
        self.commit()

    def render(self, time):
        self.painter.paint(self.shm_data, time)

    def create_buffer(self):
        if self.buffer is not None:
            self.buffer.destroy()
            self.buffer = None

        width = self.scale * self.width
        height = self.scale * self.height
        stride = width * 4
        size = stride * height

        with AnonymousFile(size) as fd:
            self.shm_data = mmap.mmap(
                fd, size, prot=mmap.PROT_READ | mmap.PROT_WRITE, flags=mmap.MAP_SHARED
            )
            pool = self.shm.create_pool(fd, size)
            buffer = pool.create_buffer(0, width, height, stride, WlShm.format.argb8888.value)
            pool.destroy()
        self.buffer = buffer

    def commit(self):
        def frame_callback(callback, time):
            callback._destroy()
            self.redraw(time)

        self.frame = frame = self.surface.frame()
        frame.dispatcher["done"] = frame_callback
        self.surface.damage(0, 0, self.scale * self.width, self.scale * self.height)
        self.surface.attach(self.buffer, 0, 0)
        self.surface.commit()

    def on_resized(self, view, width, height):
        print("resize", width, height)
        if self.width != width or self.height != height:
            self.painter.width = self.width = width
            self.painter.height = self.height = height
            self.create_buffer()
            self.redraw()

    def on_rescaled(self, view, scale):
        print("rescale", scale)
        if self.scale != scale:
            self.painter.scale = self.scale = scale
            self.create_buffer()
            self.redraw()


def main():
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    ctx = Context(WAYLAND_DISPLAY)
    ctx.connect()
    ctx.run()


if __name__ == "__main__":
    main()