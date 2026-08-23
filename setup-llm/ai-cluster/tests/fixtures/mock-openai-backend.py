#!/usr/bin/env python3
import argparse
import hashlib
import json
from http.server import BaseHTTPRequestHandler, HTTPServer


def _json_bytes(payload):
    return json.dumps(payload).encode("utf-8")


def _deterministic_embedding(text, dimensions=8):
    digest = hashlib.sha256(text.encode("utf-8")).digest()
    values = []
    for index in range(dimensions):
        byte_value = digest[index % len(digest)]
        # Keep vectors intentionally non-normalized so contract checks can assert this.
        values.append(round(float(byte_value) / 25.5, 6))
    return values


class Handler(BaseHTTPRequestHandler):
    mode = "chat"
    model_name = "local-coding"

    def _write_json(self, status, payload):
        content = _json_bytes(payload)
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def do_GET(self):
        if self.path == "/health":
            self._write_json(200, {"status": "ok", "mode": self.mode, "model": self.model_name})
            return

        if self.path == "/v1/models":
            self._write_json(200, {
                "object": "list",
                "data": [{"id": self.model_name, "object": "model", "owned_by": "local"}],
            })
            return

        self._write_json(404, {"error": {"message": "not found", "type": "invalid_request_error"}})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length > 0 else b"{}"

        try:
            body = json.loads(raw.decode("utf-8"))
        except Exception:
            self._write_json(400, {"error": {"message": "invalid json", "type": "invalid_request_error"}})
            return

        if self.path == "/v1/chat/completions":
            if self.mode != "chat":
                if self.mode == "rate-limit":
                    self._write_json(429, {"error": {"message": "rate limit", "type": "rate_limit_error"}})
                    return
                if self.mode == "malformed":
                    bad_payload = b"this is not json"
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(bad_payload)))
                    self.end_headers()
                    self.wfile.write(bad_payload)
                    return
                self._write_json(400, {"error": {"message": "chat disabled", "type": "invalid_request_error"}})
                return

            prompt_text = ""
            for msg in body.get("messages", []):
                prompt_text += str(msg.get("content", "")) + " "
            prompt_text = prompt_text.strip() or "empty"

            if body.get("stream"):
                chunks = [
                    f'data: {{"id":"chatcmpl-mock","object":"chat.completion.chunk","choices":[{{"index":0,"delta":{{"content":"mock:"}}}}]}}\\n\\n',
                    f'data: {{"id":"chatcmpl-mock","object":"chat.completion.chunk","choices":[{{"index":0,"delta":{{"content":" {prompt_text}"}}}}]}}\\n\\n',
                    "data: [DONE]\\n\\n",
                ]
                payload = "".join(chunks).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Cache-Control", "no-cache")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
                return

            self._write_json(200, {
                "id": "chatcmpl-mock",
                "object": "chat.completion",
                "model": self.model_name,
                "choices": [
                    {
                        "index": 0,
                        "finish_reason": "stop",
                        "message": {"role": "assistant", "content": f"mock[{self.model_name}] response: {prompt_text}"},
                    }
                ],
                "usage": {"prompt_tokens": 5, "completion_tokens": 5, "total_tokens": 10},
            })
            return

        if self.path == "/v1/embeddings":
            if self.mode != "embeddings":
                self._write_json(400, {"error": {"message": "embeddings disabled", "type": "invalid_request_error"}})
                return

            inputs = body.get("input", [])
            if not isinstance(inputs, list):
                inputs = [inputs]

            data = []
            for idx, item in enumerate(inputs):
                data.append({
                    "object": "embedding",
                    "index": idx,
                    "embedding": _deterministic_embedding(str(item), dimensions=8),
                })

            self._write_json(200, {
                "object": "list",
                "model": self.model_name,
                "data": data,
                "usage": {"prompt_tokens": 4, "total_tokens": 4},
            })
            return

        self._write_json(404, {"error": {"message": "not found", "type": "invalid_request_error"}})

    def log_message(self, format, *args):
        return


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["chat", "embeddings", "rate-limit", "malformed"], required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--port", type=int, required=True)
    args = parser.parse_args()

    Handler.mode = args.mode
    Handler.model_name = args.name

    server = HTTPServer(("0.0.0.0", args.port), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
