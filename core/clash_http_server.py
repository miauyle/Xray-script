#!/usr/bin/env python3
import argparse
import pathlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from clash_shadowrocket import aggregate


def read_token(path: pathlib.Path) -> str:
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError:
        return ""


class Handler(BaseHTTPRequestHandler):
    server_version = "XrayClashSubscription/1.0"

    def do_GET(self):
        request_path = self.path.split("?", 1)[0]
        routes = [
            (self.server.token_file, self.server.yaml_file, "clash.yaml"),
            (self.server.multi_token_file, self.server.multi_yaml_file, "multi_clash.yaml"),
            (self.server.provider_token_file, self.server.provider_yaml_file, "proxies.yaml"),
            (self.server.provider_next_token_file, self.server.provider_yaml_file, "proxies.yaml"),
        ]
        # Both multi endpoints use the same scoped MULTI_TOKEN.
        if (getattr(self.server, "shadowrocket_config_file", None) is not None and
                getattr(self.server, "shadowrocket_cache_dir", None) is not None):
            routes.append((self.server.multi_token_file, self.server.provider_yaml_file, "multi_nodes.txt"))
        selected_file = None
        dynamic = False
        for token_file, yaml_file, filename in routes:
            if token_file is None or yaml_file is None:
                continue
            token = read_token(token_file)
            if token and request_path == f"/sub/{token}/{filename}":
                selected_file = yaml_file
                dynamic = filename == "multi_nodes.txt"
                break
        if selected_file is None:
            self.send_error(404)
            return

        if dynamic:
            try:
                data = aggregate(
                    self.server.shadowrocket_config_file, selected_file,
                    self.server.shadowrocket_cache_dir,
                )
            except (OSError, ValueError):
                self.send_error(503)
                return
        else:
            try:
                data = selected_file.read_bytes()
            except OSError:
                self.send_error(404)
                return

        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8" if dynamic else "text/yaml; charset=utf-8")
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
    parser.add_argument("--multi-token-file", type=pathlib.Path)
    parser.add_argument("--multi-yaml-file", type=pathlib.Path)
    parser.add_argument("--provider-token-file", type=pathlib.Path)
    parser.add_argument("--provider-yaml-file", type=pathlib.Path)
    parser.add_argument("--provider-next-token-file", type=pathlib.Path)
    parser.add_argument("--shadowrocket-config-file", type=pathlib.Path)
    parser.add_argument("--shadowrocket-cache-dir", type=pathlib.Path)
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.bind, args.port), Handler)
    server.token_file = args.token_file
    server.yaml_file = args.yaml_file
    server.multi_token_file = args.multi_token_file
    server.multi_yaml_file = args.multi_yaml_file
    server.provider_token_file = args.provider_token_file
    server.provider_next_token_file = args.provider_next_token_file
    server.provider_yaml_file = args.provider_yaml_file
    server.shadowrocket_config_file = args.shadowrocket_config_file
    server.shadowrocket_cache_dir = args.shadowrocket_cache_dir
    server.serve_forever()


if __name__ == "__main__":
    main()
