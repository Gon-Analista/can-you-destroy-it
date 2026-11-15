#!/usr/bin/env python3
"""Cliente mínimo del MCP HTTP de Sprite AI (https://www.sprite-ai.art/api/mcp).

La clave NO va en el repo. Se lee de la variable SPRITE_AI_API_KEY; en las sesiones en la nube la
inyecta el proxy (secreto de red del entorno) y basta con no definirla.

Uso:
    python3 tools/sprite_ai/sai.py list                       # herramientas y esquemas
    python3 tools/sprite_ai/sai.py call sprite_get_balance '{}'
    python3 tools/sprite_ai/sai.py call sprite_generate '{"prompt": "..."}'
"""
import json
import os
import sys
import urllib.request

URL = "https://www.sprite-ai.art/api/mcp"


def rpc(method: str, params: dict) -> dict:
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
    key = os.environ.get("SPRITE_AI_API_KEY")
    if key:
        headers["Authorization"] = f"Bearer {key}"
    req = urllib.request.Request(URL, data=body, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=600) as resp:
        text = resp.read().decode()
    for line in text.splitlines():
        if line.startswith("data:"):
            return json.loads(line[5:].strip())
    return json.loads(text)


def main() -> None:
    if sys.argv[1] == "list":
        print(json.dumps(rpc("tools/list", {}), indent=1, ensure_ascii=False))
    elif sys.argv[1] == "call":
        args = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
        res = rpc("tools/call", {"name": sys.argv[2], "arguments": args})
        print(json.dumps(res, indent=1, ensure_ascii=False))


if __name__ == "__main__":
    main()
