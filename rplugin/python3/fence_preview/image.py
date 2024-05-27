from dataclasses import dataclass
import logging
from pathlib import Path

from typing import Optional, Dict, Tuple

from wand.image import Image

from fence_preview.delimit import Node, ContentType
from fence_preview.latex import (
    path_from_content,
    parse_equation,
    parse_latex,
    parse_latex_from_file,
    generate_svg_from_latex,
    generate_latex_from_gnuplot,
    generate_latex_from_gnuplot_file,
)

log = logging.getLogger(__name__)
log.setLevel(logging.DEBUG)


@dataclass
class SixelCache:
    content_id: str
    extmark_id: int
    path: Path


def prepare_blob(node: Node) -> Optional[Tuple[Node, Path]]:
    # if (cache := sixel_cache.get(node.content_id)):
    #     return node, cache.path
    image_path = generate_content(node)

    return node, image_path


def generate_content(node: Node) -> Path:
    path = path_from_content(node)
    missing = not path.exists()

    if missing:
        if node.content_type == ContentType.FILE:
            raise FileNotFoundError(f"Could not find file {path}!")
        if node.content_type == ContentType.MATH:
            path = parse_equation(node, 1.0)
        elif node.content_type == ContentType.TEX:
            path = parse_latex(node.content)
        elif node.content_type == ContentType.GNUPLOT:
            new_path = generate_latex_from_gnuplot(node.content)
            generate_svg_from_latex(path, 1.0)

    # // rewrite path if ending as tex or gnuplot file
    if node.content_type == ContentType.FILE:
        if path.suffix == ".tex":
            path = parse_latex_from_file(path)
        elif path.suffix == ".plt":
            new_path = generate_latex_from_gnuplot_file(path)
            path = new_path.with_suffix(".svg")

    # Rasterize svg
    if path.suffix == ".svg":
        with Image(resolution=(600.0, 600.0), filename=path) as outfile:
            outfile.save(filename=path.with_suffix(".png"))
            path = path.with_suffix(".png")

    return path
