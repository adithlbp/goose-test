#!/usr/bin/env python3
"""
Spike: provisionar un secreto en Goose vía `goose acp` (JSON-RPC sobre stdio).
El helper NUNCA toca el Keychain: solo habla JSON-RPC; Goose persiste el secreto.

Flujo: spawn `goose acp` -> initialize -> _goose/unstable/config/upsert (isSecret)
       -> (opcional) _goose/unstable/config/read para verificar -> cerrar.

Reutiliza el patrón del cliente ACP existente (test_acp_client.py).
NO es producción: sin retries, sin UI, sin abstracciones.
"""
import argparse
import json
import subprocess
import sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--goose", required=True, help="ruta al binario goose")
    ap.add_argument("--token", default="", help="valor del secreto (API key)")
    ap.add_argument("--token-stdin", action="store_true",
                    help="leer el token desde stdin (evita exponerlo en argv/ps)")
    ap.add_argument("--key", default="OPENAI_API_KEY", help="nombre del secreto")
    ap.add_argument("--verify", action="store_true", help="leer (masked) tras escribir")
    ap.add_argument("--read-only", action="store_true", help="solo leer, no escribir")
    ap.add_argument("--remove", action="store_true", help="borrar el secreto")
    args = ap.parse_args()

    if args.token_stdin:
        args.token = sys.stdin.readline().strip()
        if not args.token:
            print("!!! --token-stdin: no llegó ningún token por stdin", file=sys.stderr)
            return 1

    proc = subprocess.Popen(
        [args.goose, "acp"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )

    state = {"rid": 0}

    def call(method, params):
        state["rid"] += 1
        rid = state["rid"]
        req = {"jsonrpc": "2.0", "id": rid, "method": method, "params": params}
        print(">>>", json.dumps(req))
        proc.stdin.write(json.dumps(req) + "\n")
        proc.stdin.flush()
        while True:
            line = proc.stdout.readline()
            if not line:
                print("!!! EOF (stdout cerrado). stderr:")
                print(proc.stderr.read())
                return None
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                # cualquier línea no-JSON en stdout se ignora
                continue
            if "id" not in msg:  # notificación
                continue
            if msg.get("id") == rid:
                print("<<<", json.dumps(msg))
                return msg

    # 1. handshake
    call("initialize", {
        "protocolVersion": "v1",
        "clientCapabilities": {},
        "clientInfo": {"name": "corp-helper", "version": "1.0.0"},
    })

    # 2. operación
    if args.remove:
        call("_goose/unstable/config/remove", {"key": args.key, "isSecret": True})
    elif not args.read_only:
        call("_goose/unstable/config/upsert", {
            "key": args.key, "value": args.token, "isSecret": True,
        })

    # 3. verificación opcional (valor enmascarado)
    if args.verify or args.read_only:
        call("_goose/unstable/config/read", {"key": args.key, "isSecret": True})

    # 4. cerrar
    proc.stdin.close()
    proc.terminate()
    proc.wait()


if __name__ == "__main__":
    sys.exit(main())
