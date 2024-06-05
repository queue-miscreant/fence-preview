from dataclasses import dataclass
import logging
from pathlib import Path

from typing import List, Literal, Optional, Tuple

from wand.image import Image

from fence_preview.delimit import Node, ContentType, hash_content
from fence_preview.latex import (
    ART_PATH,
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
class ParsingNode:
    type: Literal["fence", "file"]
    parameters: str
    start: int
    end_: int
    content: Optional[List[str]] = None


@dataclass
class NodeParams:
    filetype: str
    height: Optional[int]
    others: List[str]


def prepare_blob(node: Node) -> Optional[Tuple[Node, Path]]:
    # if (cache := sixel_cache.get(node.content_id)):
    #     return node, cache.path
    image_path = generate_content(node)
    if image_path is None:
        return None

    return node, image_path


def generate_content(node: Node) -> Optional[Path]:
    path = path_from_content(node)
    missing = not path.exists()

    if missing:
        if node.content_type == ContentType.FILE:
            raise FileNotFoundError(f"Could not find file {path}!")
        if node.content_type == ContentType.MATH:
            path = parse_equation(node.content, path, 1.0)
        elif node.content_type == ContentType.TEX:
            path = parse_latex(node.content)
        elif node.content_type == ContentType.GNUPLOT:
            new_path = generate_latex_from_gnuplot(node.content)
            generate_svg_from_latex(path, 1.0)
        else:
            return None

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

def parse_node_parameters(params: str) -> Optional[NodeParams]:
    filetype = None
    height = None

    others = []

    for i, param in enumerate(params.split(",")):
        param = param.strip()
        if i == 0:
            # TODO: remap filetypes like "tex" to "latex"?
            filetype = param
        elif param.startswith("height"):
            equal = param.split("=")
            if len(equal) <= 1:
                raise ValueError("Got height, but no height provided")
            else:
                try:
                    height = int(equal[1])
                except ValueError:
                    raise ValueError("Invalid height given")
        else:
            others.append(param)

    if filetype is None:
        return None

    return NodeParams(
        filetype=filetype,
        height=height,
        others=others
    )


def run_fence(node: ParsingNode) -> Optional[Path]:
    if node.content is None:
        return None

    stripped_content = "\n".join(node.content).strip()
    content_hash = hash_content(stripped_content)
    path = (ART_PATH / content_hash).with_suffix(".svg")

    if not path.exists():
        params = parse_node_parameters(node.parameters)
        if params is None:
            return None

        if params.filetype == "math":
            path = parse_equation(stripped_content, path, 1.0)
        elif params.filetype == "tex":
            path = parse_latex(stripped_content)
        elif params.filetype == "gnuplot":
            generate_latex_from_gnuplot(stripped_content)
            generate_svg_from_latex(path, 1.0)
        else:
            return None

    return path

def gen_file(node: ParsingNode) -> Path:
    path = Path(node.parameters).expanduser()

    log.error(node)

    if path.suffix == ".tex":
        path = parse_latex_from_file(path)
    elif path.suffix == ".plt":
        new_path = generate_latex_from_gnuplot_file(path)
        path = new_path.with_suffix(".svg")

    return path

def generate_image(node: ParsingNode) -> Optional[Path]:
    # TODO: exceptions
    if node.type == "fence":
        path = run_fence(node)
    else:
        path = gen_file(node)

    if path is None or not path.exists():
        return None
    elif path.suffix == ".svg":
        # Rasterize
        with Image(resolution=(600.0, 600.0), filename=path) as outfile:
            outfile.save(filename=path.with_suffix(".png"))
            path = path.with_suffix(".png")

    return path
