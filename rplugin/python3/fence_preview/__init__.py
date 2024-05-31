import asyncio
from collections import defaultdict
import logging
import sys
import time
import traceback

from typing import Any, DefaultDict, Dict, List, Tuple

import pynvim
from pynvim.api import Buffer
from fence_preview.image import prepare_blob
from fence_preview.delimit import process_content, DEFAULT_REGEXES, Node
from fence_preview.latex import ART_PATH

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

        # TODO: configurable
        self._regexes = DEFAULT_REGEXES

        if not ART_PATH.exists():
            ART_PATH.mkdir()

        nvim.loop.set_exception_handler(self.handle_exception)
        logging.getLogger().addHandler(self._handler)

    @pynvim.function("FenceUpdateContent", sync=True)
    def update_content(self, args: List[str]):
        log.error(time.time())
        buffer: Buffer = self.nvim.current.buffer
        # This can be async from nvim...
        nodes = process_content(
            buffer[:],
            self._regexes,
        )
        # TODO
        self.nvim.lua.sixel_extmarks.remove_all()

        # ...but this can't be
        asyncio.create_task(self.draw_visible(nodes, force=True))

    async def draw_visible(self, nodes: List[Node], force=False):
        loop: asyncio.AbstractEventLoop = self.nvim.loop
        # Start: we know each node and its content hash

        # First: If the content has already been generated, update the size of the extmarks
        # TODO

        # Second: Generate new content for each new content id

        # start processing new sixel content in another thread
        updated_path_nodes = await asyncio.gather(
            *(
                # TODO
                loop.run_in_executor(None, prepare_blob, node)
                for node in nodes
            )
        )

        # Second: clear old content from the cache
        # this must be sync
        self.nvim.async_call(self.update_extmarks, updated_path_nodes)

    def update_extmarks(self, updated_path_nodes: List[Tuple[Node, None]]):
        # self.nvim.lua.clear_cache()
        self.nvim.lua.fence_preview.push_new_content(
            [
                (node.range[0] - 1, node.range[1] - 1, str(path))
                for node, path in updated_path_nodes
            ]
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
