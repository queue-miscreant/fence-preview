from dataclasses import dataclass
import logging
from pathlib import Path

from typing import List, Literal, Optional, Tuple

from wand.image import Image

from fence_preview.latex import (
    ART_PATH,
    hash_content,
    parse_equation,
    parse_latex,
    parse_latex_from_file,
    generate_svg_from_latex,
    generate_latex_from_gnuplot,
    generate_latex_from_gnuplot_file,
    generate_latex_from_python,
)

log = logging.getLogger(__name__)
log.setLevel(logging.DEBUG)


@dataclass
class ParsingNode:
    type: Literal["fence", "file"]
    range: Tuple[int, int]
    id: int
    hash: str
    params: Optional[dict] = None
    filename: Optional[str] = None
    content: Optional[List[str]] = None


@dataclass
class NodeParams:
    filetype: str
    others: List[str]
    height: Optional[int] = None


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

    return NodeParams(filetype=filetype, height=height, others=others)


def run_fence(node: ParsingNode) -> Optional[Path]:
    assert node.params is not None
    if node.content is None:
        return None

    content = "\n".join(node.content)
    content_hash = node.hash
    path = (ART_PATH / content_hash).with_suffix(".svg")

    if not path.exists():
        params = NodeParams(**node.params)
        if params is None:
            return None

        if params.filetype == "math":
            path = parse_equation(content, path, 1.0)
        elif params.filetype == "tex":
            path = parse_latex(content)
        elif params.filetype == "gnuplot":
            new_path = generate_latex_from_gnuplot(content)
            generate_svg_from_latex(new_path, 1.0)
        elif params.filetype == "python" and "latex" in params.others:
            generate_latex_from_python(content, path, 1.0)
        else:
            return None

    return path


def gen_file(node: ParsingNode) -> Path:
    assert node.filename is not None
    path = Path(node.filename).expanduser()

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
