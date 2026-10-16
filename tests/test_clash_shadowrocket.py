"""Shadowrocket one-URL subscription: transport mapping, cache failures and HTTP scopes."""
import base64
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import threading
import unittest
import urllib.error
import urllib.parse
import urllib.request
from http.server import ThreadingHTTPServer


ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# clash_shadowrocket imports clash_multi from its source directory in runtime.
import sys
sys.path.insert(0, str(ROOT / "core"))
import clash_shadowrocket as sr
import clash_http_server as http
import clash_multi as multi


LOCAL = """proxies:
  - name: 'Fallback-Vision-Reality'
    type: vless
    server: '198.51.100.10'
    port: 443
    uuid: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    udp: true
    tls: true
    servername: 'www.example.com'
    client-fingerprint: chrome
    encryption: ''
    flow: 'xtls-rprx-vision'
    reality-opts:
      public-key: 'PUBKEY-AAA'
      short-id: 'abcdef01'
    network: tcp
  - name: 'Fallback-XHTTP-Reality'
    type: vless
    server: '198.51.100.10'
    port: 443
    uuid: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
    udp: true
    tls: true
    servername: 'www.example.com'
    client-fingerprint: chrome
    encryption: ''
    reality-opts:
      public-key: 'PUBKEY-BBB'
      short-id: ''
    network: xhttp
    xhttp-opts:
      path: '/secret/with space'
      host: 'www.example.com'
      mode: 'auto'
"""

REMOTE = """proxies:
  - name: 'Vision-Reality'
    type: vless
    server: '203.0.113.20'
    port: 8443
    uuid: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
    udp: true
    tls: true
    servername: 'peer.example.com'
    client-fingerprint: chrome
    encryption: ''
    flow: 'xtls-rprx-vision'
    reality-opts:
      public-key: 'PUBKEY-CCC'
      short-id: '0123abcd'
    network: tcp
"""

TLS_XHTTP = """proxies:
  - name: 'SNI-XHTTP-TLS-CDN'
    type: vless
    server: 'cdn.example.com'
    port: 443
    uuid: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
    udp: true
    tls: true
    servername: 'cdn.example.com'
    client-fingerprint: chrome
    encryption: ''
    network: xhttp
    alpn:
      - h2
    xhttp-opts:
      path: '/hello'
      host: 'cdn.example.com'
      mode: 'auto'
"""


def decode(data):
    text = base64.b64decode(data, validate=True).decode()
    return [urllib.parse.urlsplit(line) for line in text.splitlines() if line]


class ShadowrocketTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.local = self.root / "proxies.yaml"
        self.local.write_text(LOCAL)
        self.config = self.root / "multi-server.json"
        multi.edit_config(self.config, "enable")
        self.cache = self.root / "cache"

    def tearDown(self):
        self.temp.cleanup()

    def peer(self, name="KR", token="K" * 43):
        url = "http://203.0.113.30/sub/" + token + "/proxies.yaml"
        multi.edit_config(self.config, "add", name, url)
        return {"name": name, "url": url}

    def test_local_nodes_and_transport_parameters(self):
        uris = decode(sr.aggregate(self.config, self.local, self.cache))
        self.assertEqual(len(uris), 2)
        vision, xhttp = uris
        self.assertEqual(vision.scheme, "vless")
        self.assertEqual(vision.hostname, "198.51.100.10")
        self.assertEqual(vision.fragment, "Local-Fallback-Vision-Reality")
        self.assertEqual(urllib.parse.parse_qs(vision.query)["pbk"], ["PUBKEY-AAA"])
        self.assertEqual(urllib.parse.parse_qs(vision.query)["flow"], ["xtls-rprx-vision"])
        args = urllib.parse.parse_qs(xhttp.query, keep_blank_values=True)
        self.assertEqual(args["type"], ["xhttp"])
        self.assertEqual(args["path"], ["/secret/with space"])
        self.assertEqual(args["mode"], ["auto"])
        self.assertEqual(args["sid"], [""])
        self.assertNotIn("flow", args)

    def test_remote_combined_one_subscription_and_cache_stale(self):
        peer = self.peer()
        calls = []
        def fetch(url):
            calls.append(url)
            return REMOTE.encode()
        output = sr.aggregate(self.config, self.local, self.cache, fetcher=fetch, now=10000000)
        uris = decode(output)
        self.assertEqual(len(uris), 3)
        self.assertEqual(uris[-1].fragment, "KR-Vision-Reality")
        self.assertEqual(len(calls), 1)
        self.assertEqual(sr.aggregate(self.config, self.local, self.cache, fetcher=lambda u: (_ for _ in ()).throw(RuntimeError("should not fetch")), now=10000000), output)
        cache = sr.cache_path(self.cache, peer)
        self.assertEqual(cache.stat().st_mode & 0o777, 0o600)
        os.utime(cache, (10000000 - 301, 10000000 - 301))
        # Unreachable peer: leave cached node in subscription.
        after_failure = sr.aggregate(self.config, self.local, self.cache,
                                     fetcher=lambda u: (_ for _ in ()).throw(OSError("peer down")), now=10000000)
        self.assertEqual(after_failure, output)
        # Invalid/partial response must not poison good cache.
        bad = sr.aggregate(self.config, self.local, self.cache,
                           fetcher=lambda u: b"proxies:\n  - name: 'Bad'\n    type: vless\n", now=10000000)
        self.assertEqual(bad, output)
        # Never silently re-serve revoked credentials from days-old cache.
        os.utime(cache, (10000000 - sr.MAX_STALE_SECONDS - 1,
                         10000000 - sr.MAX_STALE_SECONDS - 1))
        expired = decode(sr.aggregate(
            self.config, self.local, self.cache,
            fetcher=lambda u: (_ for _ in ()).throw(OSError("peer offline")),
            now=10000000,
        ))
        self.assertEqual(len(expired), 2)
        # Rotating URL token invalidates the association to old cache.
        self.peer(token="N" * 43)
        after_rotation = decode(sr.aggregate(self.config, self.local, self.cache,
                                fetcher=lambda u: (_ for _ in ()).throw(OSError("down")), now=10000000))
        self.assertEqual(len(after_rotation), 2)
        multi.edit_config(self.config, "remove", "KR")
        self.assertEqual(len(decode(sr.aggregate(self.config, self.local, self.cache))), 2)

    def test_empty_remote_cold_start_keeps_local_nodes(self):
        self.peer()
        output = decode(sr.aggregate(self.config, self.local, self.cache,
                         fetcher=lambda u: (_ for _ in ()).throw(OSError("offline"))))
        self.assertEqual(len(output), 2)

    def test_multi_doctor_detects_stale_live_xray_and_missing_peer(self):
        import contextlib
        import io
        self.peer()
        # The standalone and Provider YAML match, but live Xray has a new
        # UUID. This is a real source of "standalone works, aggregated fails".
        xray = self.root / "xray.json"
        script = self.root / "script.json"
        xray.write_text(json.dumps({
            "inbounds": [{"settings": {"clients": [
                {"id": "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"}]}}]
        }))
        script.write_text(json.dumps({"xray": {"publicKey": "PUBKEY-NEW"}}))
        single = self.root / "clash.yaml"
        # The existing marker layout is required by render_files.
        base = multi.PROXY_MARKER + LOCAL.partition("proxies:\\n")[2] + multi.GROUP_MARKER + "\\n" + multi.RULE_MARKER + "\\n"
        single.write_text(base)
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            healthy = sr.inspect_publications(
                self.config, self.local, self.cache,
                single=single, xray=xray, script=script,
                fetcher=lambda u: (_ for _ in ()).throw(OSError("no remote")),
            )
        self.assertFalse(healthy)
        text = output.getvalue()
        self.assertIn("UUID/public key differs", text)
        self.assertIn("remote Provider unavailable", text)
        self.assertNotIn("PUBKEY-NEW", text)
        self.assertNotIn("KKKKKKK", text)

    def test_multi_doctor_good_local_and_remote(self):
        import contextlib
        import io
        self.peer()
        xray = self.root / "xray.json"
        script = self.root / "script.json"
        xray.write_text(json.dumps({"inbounds": [
            {"settings": {"clients": [{"id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}]}},
            {"settings": {"clients": [{"id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"}]}}
        ]}))
        # In real configs both Reality transports use the same Xray public key.
        # Normalize fixture's second key for this test.
        self.local.write_text(LOCAL.replace("PUBKEY-BBB", "PUBKEY-AAA"))
        script.write_text(json.dumps({"xray": {"publicKey": "PUBKEY-AAA"}}))
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            healthy = sr.inspect_publications(
                self.config, self.local, self.cache,
                xray=xray, script=script,
                fetcher=lambda u: REMOTE.encode(),
            )
        self.assertTrue(healthy, output.getvalue())
        self.assertIn("PASS: KR remote Provider fetched", output.getvalue())
        self.assertNotIn("203.0.113.30/sub/", output.getvalue())

    def test_sni_tls_xhttp_with_alpn(self):
        nodes = sr.parse_provider(TLS_XHTTP)
        uri = sr.make_uri(nodes[0], "CDN")
        args = urllib.parse.parse_qs(urllib.parse.urlsplit(uri).query)
        self.assertEqual(args["security"], ["tls"])
        self.assertEqual(args["alpn"], ["h2"])
        self.assertEqual(args["type"], ["xhttp"])

    def test_unsupported_payload_fails_closed(self):
        for content in (
            "proxies:\n  - name: 'bad'\n    type: trojan\n",
            "proxies:\n  - name: 'bad'\n    type: vless\n    server: 'localhost'\n    port: 443\n",
            "proxies:\n  - name: 'bad'\n    type: vless\n    server: '198.51.100.1'\n    port: 443\n    uuid: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'\n    tls: true\n    servername: 'www.example.com'\n    network: xhttp\n",
            "proxies:\n  - name: 'bad'\n    type: vless\n    server: '198.51.100.1'\n    port: 443\n    uuid: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'\n    tls: true\n    servername: 'www.example.com'\n    reality-opts:\n      public-key: ''\n",
        ):
            with self.assertRaises(sr.ProviderError):
                sr.parse_provider(content)


class ShadowrocketHttpTests(unittest.TestCase):
    def test_one_scoped_http_url_and_auth(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "config.json").write_text(json.dumps({"enabled": True, "peers": []}))
            (root / "proxies.yaml").write_text(LOCAL)
            (root / "multi.token").write_text("multi-secret")
            (root / "single.token").write_text("single-secret")
            (root / "provider.token").write_text("provider-secret")
            (root / "multi_clash.yaml").write_text("multi configuration")
            (root / "clash.yaml").write_text("single configuration")
            server = ThreadingHTTPServer(("127.0.0.1", 0), http.Handler)
            server.token_file = root / "single.token"
            server.yaml_file = root / "clash.yaml"
            server.multi_token_file = root / "multi.token"
            server.multi_yaml_file = root / "multi_clash.yaml"
            server.provider_token_file = root / "provider.token"
            server.provider_next_token_file = root / "missing.token"
            server.provider_yaml_file = root / "proxies.yaml"
            server.shadowrocket_config_file = root / "config.json"
            server.shadowrocket_cache_dir = root / "cache"
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            try:
                prefix = "http://127.0.0.1:" + str(server.server_port)
                def get(path):
                    try:
                        with urllib.request.urlopen(prefix + path, timeout=5) as resp:
                            return resp.status, resp.read(), resp.headers
                    except urllib.error.HTTPError as exc:
                        return exc.code, b"", exc.headers
                status, data, headers = get("/sub/multi-secret/multi_nodes.txt")
                self.assertEqual(status, 200)
                self.assertEqual(len(decode(data)), 2)
                self.assertIn("text/plain", headers["Content-Type"])
                self.assertEqual(headers["Cache-Control"], "no-store")
                for bad in ("/sub/single-secret/multi_nodes.txt",
                            "/sub/provider-secret/multi_nodes.txt",
                            "/sub/wrong/multi_nodes.txt"):
                    self.assertEqual(get(bad)[0], 404)
                self.assertEqual(get("/sub/single-secret/clash.yaml")[1], b"single configuration")
                self.assertEqual(get("/sub/multi-secret/multi_clash.yaml")[1], b"multi configuration")
                (root / "config.json").write_text(json.dumps({"enabled": False, "peers": []}))
                self.assertEqual(get("/sub/multi-secret/multi_nodes.txt")[0], 503)
            finally:
                server.shutdown()
                worker.join(timeout=5)
                server.server_close()


if __name__ == "__main__":
    unittest.main()
