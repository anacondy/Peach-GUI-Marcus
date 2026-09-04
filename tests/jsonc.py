"""Minimal JSONC reader for waybar's config and dock.jsonc.

waybar accepts // line comments, /* */ block comments and trailing commas. The
standard json module accepts none of them, so `json.load` on dock.jsonc fails on
a perfectly valid file. This strips exactly those three things and nothing else
- in particular it is string-aware, so the '//' in a URL value survives.
"""
import json
import re


def strip_jsonc(text):
    out = []
    i = 0
    n = len(text)
    in_string = False
    quote = ""
    while i < n:
        c = text[i]
        if in_string:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if c == quote:
                in_string = False
            i += 1
            continue
        if c in "\"'":
            in_string = True
            quote = c
            out.append(c)
            i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
            continue
        out.append(c)
        i += 1

    stripped = "".join(out)
    # Trailing commas before } or ]
    stripped = re.sub(r",(\s*[}\]])", r"\1", stripped)
    return stripped


def load(path):
    with open(path, encoding="utf-8") as fh:
        return json.loads(strip_jsonc(fh.read()))
