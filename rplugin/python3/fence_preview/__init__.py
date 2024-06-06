import asyncio
from collections import defaultdict
from dataclasses import asdict
import logging
import sys
from pathlib import Path
import traceback

from typing import (
    Any,
    DefaultDict,
    List,
    Iterable,
    Optional,
    Tuple,
)

import pynvim
from fence_preview.image import generate_image, ParsingNode
from fence_preview.latex import ART_PATH, hash_content

log = logging.getLogger(__name__)
log.setLevel(logging.DEBUG)

LOGGING_TO_NVIM_LEVELS: DefaultDict[int, int] = defaultdict(
    lambda: 1,
    {
        logging.DEBUG: 1,
        logging.INFO: 1,
        logging.ERROR: 3,
        logging.CRITICAL: 4,
    },
)


class NvimHandler(logging.Handler):
    def __init__(self, nvim: pynvim.Nvim, level=0):
        super().__init__(level)
        self._nvim = nvim

    def emit(self, record: logging.LogRecord):
        self._nvim.async_call(
            self._nvim.api.notify,
            str(record.getMessage()),
            LOGGING_TO_NVIM_LEVELS[record.levelno],
            {},
        )


@pynvim.plugin
class NvimImage:
    def __init__(self, nvim: pynvim.Nvim):
        self.nvim = nvim
        self._handler = NvimHandler(nvim, level=logging.INFO)

        if not ART_PATH.exists():
            ART_PATH.mkdir()

        self._last_nodes: Optional[List[ParsingNode]] = None
        self._last_files: Optional[List[Optional[Path]]] = None

        nvim.loop.set_exception_handler(self.handle_exception)
        logging.getLogger().addHandler(self._handler)

    @pynvim.function("FenceAsyncGen", sync=True)
    def async_gen(self, args: List[Any]):
        buffer = args[0]
        nodes = [ParsingNode(**arg) for arg in args[1]]
        draw_number: int = args[2]

        if self._last_nodes and self._last_files:
            if nodes == self._last_nodes:
                self.deliver_paths(buffer, zip(self._last_nodes, self._last_files), draw_number)
                return
        self._last_nodes = nodes

        asyncio.create_task(self.generate_images(buffer, nodes, draw_number))

    async def generate_images(self, buffer: int, nodes: List[ParsingNode], draw_number: int):
        loop: asyncio.AbstractEventLoop = self.nvim.loop

        updated_path_nodes = await asyncio.gather(
            *(
                # TODO
                loop.run_in_executor(None, generate_image, node)
                for node in nodes
            )
        )
        self._last_files = updated_path_nodes

        self.nvim.async_call(self.deliver_paths, buffer, zip(nodes, updated_path_nodes), draw_number)

    def deliver_paths(self, buffer: int, node_paths: Iterable[Tuple[ParsingNode, Optional[Path]]], draw_number: int):
        for node, path in node_paths:
            if path is None:
                continue
            self.nvim.lua.fence_preview.try_draw_extmark(
                buffer, str(path), asdict(node), draw_number
            )

    def handle_exception(self, _: asyncio.AbstractEventLoop, context: Any) -> None:
        if (exception := context.get("exception")) is None or not isinstance(
            exception, Exception
        ):
            message = context.get("message")
            log.error("Handler got non-exception: %s", message)
            return
        if sys.version_info >= (3, 10):
            formatted = traceback.format_exception(exception)
        elif hasattr(exception, "__traceback__"):
            formatted = traceback.format_exception(
                type(exception), exception, exception.__traceback__
            )
        else:
            formatted = "(Could not get stack trace)"

        log.error(f"Error occurred:\n{''.join(formatted)}")
        log.debug("", exc_info=True)
