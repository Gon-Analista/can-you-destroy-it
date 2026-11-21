#!/usr/bin/env python3
"""Lista los avisos de GDScript (los del panel Depurador del editor) de todos los scripts.

Uso:
    python3 tools/gd_warnings.py [--godot RUTA] [--port 6011] [--summary] [ruta/filtro ...]

Arranca el editor de Godot sin ventana con su servidor de lenguaje (LSP), abre cada `.gd` de
`game/` y recoge los diagnósticos. Imprime `ruta:línea [CÓDIGO] mensaje`; con --summary, cuántos
hay de cada tipo. Los filtros (subcadenas de la ruta) limitan los archivos. Sale con 1 si hay
avisos. Requiere el binario de Godot (por defecto ~/bin/godot o $GODOT).
"""
import argparse
import json
import os
import pathlib
import re
import socket
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent / "game"


class Lsp:
    def __init__(self, port: int) -> None:
        self.sock = None
        for _ in range(180):
            try:
                self.sock = socket.create_connection(("127.0.0.1", port))
                break
            except OSError:
                time.sleep(1)
        if self.sock is None:
            sys.exit("No se pudo conectar con el LSP de Godot")
        self.sock.settimeout(0.3)
        self.buf = b""

    def send(self, obj: dict) -> None:
        data = json.dumps(obj).encode()
        self.sock.sendall(b"Content-Length: %d\r\n\r\n" % len(data) + data)

    def pump(self, seconds: float) -> list:
        out = []
        end = time.time() + seconds
        while time.time() < end:
            try:
                chunk = self.sock.recv(65536)
                if not chunk:
                    break
                self.buf += chunk
            except socket.timeout:
                pass
            while True:
                i = self.buf.find(b"\r\n\r\n")
                if i < 0:
                    break
                m = re.search(rb"Content-Length:\s*(\d+)", self.buf[:i], re.I)
                n = int(m.group(1))
                if len(self.buf) < i + 4 + n:
                    break
                out.append(json.loads(self.buf[i + 4 : i + 4 + n]))
                self.buf = self.buf[i + 4 + n :]
        return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", default=os.environ.get("GODOT", str(pathlib.Path.home() / "bin/godot")))
    ap.add_argument("--port", type=int, default=6011)
    ap.add_argument("--summary", action="store_true")
    ap.add_argument("filters", nargs="*")
    args = ap.parse_args()
    files = sorted(
        p
        for p in ROOT.rglob("*.gd")
        if not {".godot", "addons"} & set(p.parts)
        and (not args.filters or any(f in str(p) for f in args.filters))
    )
    editor = subprocess.Popen(
        [args.godot, "--editor", "--headless", "--path", str(ROOT), "--lsp-port", str(args.port)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    diags: dict = {}
    try:
        lsp = Lsp(args.port)
        lsp.send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                  "params": {"processId": None, "rootUri": ROOT.as_uri(), "capabilities": {}}})
        lsp.pump(3)
        lsp.send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
        lsp.pump(1)

        def take(msgs: list) -> None:
            for m in msgs:
                if m.get("method") == "textDocument/publishDiagnostics":
                    diags[m["params"]["uri"]] = m["params"]["diagnostics"]

        for p in files:
            lsp.send({"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {"textDocument": {
                "uri": p.as_uri(), "languageId": "gdscript", "version": 1, "text": p.read_text(encoding="utf-8")}}})
            take(lsp.pump(0.5))
        take(lsp.pump(3))
    finally:
        editor.terminate()
        editor.wait(10)
    counts: dict = {}
    total = 0
    for uri, ds in sorted(diags.items()):
        rel = uri.replace(ROOT.as_uri() + "/", "")
        for d in ds:
            total += 1
            msg = d["message"]
            code = re.search(r"\(([A-Z_]+)\)", msg)
            key = code.group(1) if code else "ERROR"
            counts[key] = counts.get(key, 0) + 1
            if not args.summary:
                print("%s:%d %s" % (rel, d["range"]["start"]["line"] + 1, msg))
    if args.summary:
        for k, n in sorted(counts.items(), key=lambda kv: -kv[1]):
            print("%5d %s" % (n, k))
    print("TOTAL %d avisos en %d de %d archivos" % (total, sum(1 for d in diags.values() if d), len(files)), file=sys.stderr)
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
