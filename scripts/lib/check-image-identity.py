#!/usr/bin/env python3
"""Verify passwd/group identity from a streamed Docker image archive."""

import json
import posixpath
import sys
import tarfile


TARGETS = {"etc/passwd", "etc/group"}


def normalized(name):
    value = posixpath.normpath(name.removeprefix("./"))
    return "" if value == ".." or value.startswith("../") else value


def read_layer(stream):
    result = {"opaque_etc": False, "deleted": set(), "files": {}}
    with tarfile.open(fileobj=stream, mode="r|*") as layer:
        for member in layer:
            name = normalized(member.name)
            if name == "etc/.wh..wh..opq":
                result["opaque_etc"] = True
            elif name in ("etc/.wh.passwd", "etc/.wh.group"):
                result["deleted"].add("etc/" + name.removeprefix("etc/.wh."))
            elif name in TARGETS:
                if not member.isfile():
                    result["deleted"].add(name)
                    continue
                source = layer.extractfile(member)
                if source is None or member.size > 2 * 1024 * 1024:
                    raise ValueError(f"invalid image identity file: {name}")
                result["files"][name] = source.read()
    return result


def image_identity_files(stream):
    manifest = None
    layers = {}
    with tarfile.open(fileobj=stream, mode="r|*") as archive:
        for member in archive:
            name = normalized(member.name)
            if name == "manifest.json" and member.isfile():
                source = archive.extractfile(member)
                manifest = json.load(source) if source is not None else None
            elif name.endswith("/layer.tar") and member.isfile():
                source = archive.extractfile(member)
                if source is not None:
                    layers[name] = read_layer(source)

    if not isinstance(manifest, list) or len(manifest) != 1:
        raise ValueError("expected one Docker image manifest")
    layer_order = manifest[0].get("Layers")
    if not isinstance(layer_order, list):
        raise ValueError("Docker image manifest has no layer list")

    files = {}
    for layer_name in layer_order:
        changes = layers.get(normalized(layer_name))
        if changes is None:
            raise ValueError(f"Docker image archive is missing layer: {layer_name}")
        if changes["opaque_etc"]:
            files.pop("etc/passwd", None)
            files.pop("etc/group", None)
        for name in changes["deleted"]:
            files.pop(name, None)
        files.update(changes["files"])
    return files


def identity_matches(files, username, uid, gid, docker_gid):
    try:
        passwd = files["etc/passwd"].decode("utf-8").splitlines()
        groups = files["etc/group"].decode("utf-8").splitlines()
    except (KeyError, UnicodeDecodeError):
        return False

    account = next((row.split(":") for row in passwd if row.split(":", 1)[0] == username), None)
    if account is None or len(account) < 4 or account[2] != uid or account[3] != gid:
        return False
    if not docker_gid or docker_gid == gid:
        return True
    for row in groups:
        fields = row.split(":")
        if len(fields) >= 4 and fields[2] == docker_gid and username in fields[3].split(","):
            return True
    return False


def main(argv):
    if len(argv) != 5:
        return 2
    try:
        files = image_identity_files(sys.stdin.buffer)
        return 0 if identity_matches(files, *argv[1:]) else 1
    except (OSError, ValueError, json.JSONDecodeError, tarfile.TarError):
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
