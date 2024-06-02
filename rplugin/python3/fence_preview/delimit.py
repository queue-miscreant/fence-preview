from binascii import hexlify
from dataclasses import dataclass
from enum import auto, Enum
from hashlib import sha256
import itertools
import logging
import re

from typing import List, Optional, Tuple

log = logging.getLogger(__name__)
log.setLevel(logging.DEBUG)


@dataclass
class ContentRegexes:
    fences_regex: re.Pattern
    file_regex: re.Pattern
    header_regex: re.Pattern
    newlines: re.Pattern


DEFAULT_REGEXES = ContentRegexes(
    fences_regex=re.compile(
        r"\n```(?P<name>([a-z]{3,}))(,height=(?P<height>([\d]+)))?[\w]*\n(?P<inner>[\s\S]+?)?```",
        re.MULTILINE,
    ),
    file_regex=re.compile(
        r"\n(?P<alt>!\[[^\]]*\])\((?P<file_name>.*?)\)\n(?P<new_lines>\n*)",
        re.MULTILINE,
    ),
    header_regex=re.compile(r"\n(#{1,6}.*)", re.MULTILINE),  # TODO
    newlines=re.compile(r"\n", re.MULTILINE),
)


def hash_content(content: str) -> str:
    return hexlify(sha256(content.encode()).digest()).decode()


class ContentType(Enum):
    MATH = "math"  # TODO: needs syntax
    GNUPLOT = "gnuplot"
    TEX = "tex"
    LATEX = TEX
    FILE = ""  # Unique from None
    OTHER = None


@dataclass
class Node:
    content_id: str
    range: Tuple[int, int]
    content: str
    content_type: ContentType
    filetype: Optional[str]


def make_fenced_content(
    line_number: int, name: str, height: Optional[str], content: str
) -> Optional[Node]:
    line_count = int(height) if height is not None else content.count("\n") + 2

    try:
        content_type = ContentType[name.upper()]
        filetype = content_type.value
    except KeyError:
        content_type = ContentType.OTHER
        filetype = name

    return Node(
        content_id=hash_content(content),
        range=(line_number, line_number + line_count - 1),
        content=content,
        content_type=content_type,
        filetype=filetype,
    )


def make_file_content(
    line_number: int, filepath: str, line_count: int
) -> Optional[Node]:
    try:
        return Node(
            content_id=hash_content(filepath),
            range=(line_number + 1, line_number + line_count),
            content=filepath,
            content_type=ContentType.FILE,
            filetype=None,
        )
    except (AssertionError, ValueError):
        return None


def process_content(
    buffer_lines: List[str],
    matcher: ContentRegexes,
) -> List[Node]:

    content = "\n" + "\n".join(buffer_lines)

    # put new lines into a btree map for later
    new_lines = {
        line.start(): line_number + 1
        for line_number, line in enumerate(matcher.newlines.finditer(content))
    }
    new_lines[1] = 1

    for line_number, line in enumerate(matcher.newlines.finditer(content)):
        start = line.start()
        new_lines[start] = line_number + 1

    fences = [
        make_fenced_content(
            new_lines.get(fence.start(0), 0),
            name=fence.group("name"),
            height=fence.group("height"),
            content=fence.group("inner") or "",
        )
        for fence in matcher.fences_regex.finditer(content)
    ]

    files = [
        make_file_content(
            new_lines.get(file.start(0), 0),
            filepath=file.group("file_name"),
            # alttext=file.group("alt"),
            line_count=len(file.group("new_lines")),
        )
        for file in matcher.file_regex.finditer(content)
    ]

    return [item for item in itertools.chain(fences, files) if item is not None]
