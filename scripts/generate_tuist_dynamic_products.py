#!/usr/bin/env python3

"""
Generate Tuist package product type overrides from the resolved dependency graph.

The goal is to keep a chosen package product dynamic, and then promote only the
dependencies that are shared outside that dynamic product's dependency tree.

For example, if "NIOTransportServices" is chosen as a seed:
  - keep "NIOTransportServices" dynamic
  - walk its transitive dependencies
  - if a dependency is also consumed by something outside the
    "NIOTransportServices" subtree, promote it to dynamic too
  - repeat until the set reaches a fixed point

The generated JSON file is read by Tuist/Package.swift to populate
PackageSettings(productTypes:).
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Set, Tuple


@dataclass(frozen=True)
class Node:
    kind: str
    path: str
    name: str

    @property
    def key(self) -> Tuple[str, str, str]:
        return (self.kind, self.path, self.name)


def _pairs_to_dict(items: List[object]) -> Dict[object, object]:
    if len(items) % 2 != 0:
        raise ValueError("Expected alternating key/value list")
    return {items[i]: items[i + 1] for i in range(0, len(items), 2)}


def _parse_node(raw: object) -> Optional[Node]:
    if not isinstance(raw, dict):
        return None

    if "target" in raw:
        target = raw["target"]
        return Node("target", target["path"], target["name"])

    if "project" in raw:
        project = raw["project"]
        return Node("project", project["path"], project["target"])

    return None


def _load_graph(graph_path: Path) -> dict:
    with graph_path.open() as handle:
        return json.load(handle)


def _run_tuist_graph(repo_root: Path) -> Path:
    tempdir = Path(tempfile.mkdtemp(prefix="tuist-graph-"))
    subprocess.run(
        [
            "tuist",
            "graph",
            "--format",
            "json",
            "--no-open",
            "--output-path",
            str(tempdir),
            "--path",
            str(repo_root),
        ],
        check=True,
        cwd=repo_root,
    )
    return tempdir / "graph.json"


def _collect_project_products(graph: dict) -> Dict[Tuple[str, str, str], str]:
    products: Dict[Tuple[str, str, str], str] = {}
    projects = _pairs_to_dict(graph["projects"])

    for project_path, project in projects.items():
        targets = project.get("targets", {})
        for target_name, target in targets.items():
            node = Node("target", str(project_path), target_name)
            products[node.key] = target.get("product", "")

    return products


def _collect_edges(graph: dict) -> Dict[Tuple[str, str, str], Set[Tuple[str, str, str]]]:
    adjacency: Dict[Tuple[str, str, str], Set[Tuple[str, str, str]]] = {}

    dependencies = graph["dependencies"]
    if len(dependencies) % 2 != 0:
        raise ValueError("Unexpected dependencies payload shape")

    for i in range(0, len(dependencies), 2):
        src = _parse_node(dependencies[i])
        raw_children = dependencies[i + 1]
        if src is None or not isinstance(raw_children, list):
            continue

        children: Set[Tuple[str, str, str]] = set()
        for child_raw in raw_children:
            child = _parse_node(child_raw)
            if child is None:
                continue
            children.add(child.key)
        adjacency[src.key] = children

    return adjacency


def _reverse_edges(
    adjacency: Dict[Tuple[str, str, str], Set[Tuple[str, str, str]]]
) -> Dict[Tuple[str, str, str], Set[Tuple[str, str, str]]]:
    reverse: Dict[Tuple[str, str, str], Set[Tuple[str, str, str]]] = {}
    for src, children in adjacency.items():
        reverse.setdefault(src, set())
        for child in children:
            reverse.setdefault(child, set()).add(src)
    return reverse


def _transitive_closure(
    start: Tuple[str, str, str],
    adjacency: Dict[Tuple[str, str, str], Set[Tuple[str, str, str]]],
    cache: Dict[Tuple[str, str, str], Set[Tuple[str, str, str]]],
) -> Set[Tuple[str, str, str]]:
    if start in cache:
        return cache[start]

    seen: Set[Tuple[str, str, str]] = set()
    stack = [start]
    while stack:
        node = stack.pop()
        for child in adjacency.get(node, set()):
            if child in seen:
                continue
            seen.add(child)
            stack.append(child)

    cache[start] = seen
    return seen


def _is_external_target(node_key: Tuple[str, str, str], repo_root: Path) -> bool:
    kind, path, _ = node_key
    return kind == "target" and Path(path).resolve() != repo_root.resolve()


def compute_dynamic_products(
    repo_root: Path,
    seed_names: Iterable[str],
    graph_path: Optional[Path] = None,
) -> List[str]:
    graph = _load_graph(graph_path or _run_tuist_graph(repo_root))
    products = _collect_project_products(graph)
    adjacency = _collect_edges(graph)
    reverse = _reverse_edges(adjacency)

    closure_cache: Dict[Tuple[str, str, str], Set[Tuple[str, str, str]]] = {}

    seed_set = set(seed_names)
    all_targets = set(products)
    dynamic: Set[Tuple[str, str, str]] = {
        node for node in all_targets if node[0] == "target" and node[2] in seed_set
    }

    if not dynamic:
        raise SystemExit(f"No seed products found: {', '.join(seed_names)}")

    changed = True
    while changed:
        changed = False
        for root in list(dynamic):
            root_closure = _transitive_closure(root, adjacency, closure_cache)
            for candidate in root_closure:
                if candidate in dynamic:
                    continue
                if candidate[0] != "target":
                    continue

                external_parents = {
                    parent
                    for parent in reverse.get(candidate, set())
                    if parent not in root_closure
                }
                if external_parents:
                    dynamic.add(candidate)
                    changed = True

    names = sorted({
        node[2]
        for node in dynamic
        if _is_external_target(node, repo_root)
    })
    return names


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="Path to the Tuist repo root",
    )
    parser.add_argument(
        "--seed",
        dest="seeds",
        action="append",
        required=True,
        help="Package product name to force as a dynamic framework. Repeat as needed.",
    )
    parser.add_argument(
        "--graph-json",
        type=Path,
        help="Optional existing tuist graph JSON to reuse",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "Tuist" / "DynamicProducts.json",
        help="Where to write the generated JSON file",
    )
    args = parser.parse_args()

    repo_root = args.repo_root.resolve()
    output_path = args.output.resolve()
    dynamic_names = compute_dynamic_products(
        repo_root=repo_root,
        seed_names=args.seeds,
        graph_path=args.graph_json.resolve() if args.graph_json else None,
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(dynamic_names, indent=2) + "\n")

    print(f"Wrote {len(dynamic_names)} dynamic products to {output_path}")
    for name in dynamic_names:
        print(name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
