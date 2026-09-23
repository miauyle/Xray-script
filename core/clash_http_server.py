#!/usr/bin/env python3
import argparse
import pathlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def read_token(path: pathlib.Path) -> str:
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError:
        return ""


class Handler(BaseHTTPRequestHandler):
    server_version = "XrayClashSubscription/1.0"

    def do_GET(self):
        token = read_token(self.server.token_file)
        expected = f"/sub/{token}/clash.yaml" if token else ""
        if not expected or self.path.split("?", 1)[0] != expected:
            self.send_error(404)
            return

        try:
            data = self.server.yaml_file.read_bytes()
        except OSError:
            self.send_error(404)
            return

        self.send_response(200)
        self.send_header("Content-Type", "text/yaml; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        return


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--token-file", type=pathlib.Path, required=True)
    parser.add_argument("--yaml-file", type=pathlib.Path, required=True)
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.bind, args.port), Handler)
    server.token_file = args.token_file
    server.yaml_file = args.yaml_file
    server.serve_forever()


if __name__ == "__main__":
    main()
