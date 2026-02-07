#!/usr/bin/env python3
"""
Simple Webhook Server for Testing Redmine Webhooks

This is a lightweight HTTP server that:
1. Receives webhook POST requests from Redmine
2. Logs all incoming requests to console
3. Returns 200 OK response
4. Saves request logs to webhook_events.json file

Usage:
    python3 webhook_test_server.py [port]

Default port: 8080
"""

from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import datetime
import os
import sys

# Log file path
LOG_FILE = "webhook_events.json"

# Global server port for display
SERVER_PORT = 8080


class WebhookHandler(BaseHTTPRequestHandler):
    """Handle incoming webhook requests"""

    def log_webhook(self, method, path, body, headers):
        """Log incoming request to console and file"""

        # Build log entry
        timestamp = datetime.datetime.now().isoformat()
        body_text = body.decode('utf-8', errors='replace') if isinstance(body, bytes) else body

        log_entry = {
            "timestamp": timestamp,
            "method": method,
            "path": path,
            "headers": dict(headers),
            "body": body_text,
            "content_type": headers.get("Content-Type", ""),
            "content_length": headers.get("Content-Length", 0)
        }

        # Print to console (colorized output)
        print(f"\n{'='*60}")
        print(f"📨 WEBHOOK RECEIVED - {timestamp}")
        print(f"{'='*60}")
        print(f"Method:   {method}")
        print(f"Path:     {path}")
        print(f"Headers:")
        for key, value in headers.items():
            print(f"  {key}: {value}")
        print(f"\nBody ({len(body)} bytes):")
        try:
            json_data = json.loads(body_text)
            print(json.dumps(json_data, indent=2))
        except json.JSONDecodeError:
            print(body_text)

        # Save to file
        try:
            # Load existing logs
            if os.path.exists(LOG_FILE):
                with open(LOG_FILE, "r") as f:
                    logs = json.load(f)
            else:
                logs = []

            # Add new log
            logs.append(log_entry)

            # Save logs
            with open(LOG_FILE, "w") as f:
                json.dump(logs, f, indent=2)

            print(f"\n💾 Saved to: {LOG_FILE}")

        except Exception as e:
            print(f"\n⚠️  Failed to save log: {e}")

        print(f"{'='*60}\n")

    def do_POST(self):
        """Handle POST requests (webhooks)"""

        # Read request body
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)

        # Log the request
        self.log_webhook(self.command, self.path, body, self.headers)

        # Send 200 OK response
        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()

        response = {
            "status": "received",
            "message": "Webhook received successfully",
            "timestamp": datetime.datetime.now().isoformat()
        }
        self.wfile.write(json.dumps(response).encode("utf-8"))

    def do_GET(self):
        """Handle GET requests (health check and log view)"""

        if self.path == "/":
            # Serve simple UI
            self.send_response(200)
            self.send_header("Content-type", "text/html")
            self.end_headers()

            try:
                with open(LOG_FILE, "r") as f:
                    logs = json.load(f)
                recent_logs = logs[-10:]  # Last 10 entries
            except Exception as e:
                recent_logs = []

            html = f"""
            <!DOCTYPE html>
            <html>
            <head>
                <title>Webhook Test Server</title>
                <style>
                    body {{
                        font-family: 'Courier New', monospace;
                        padding: 20px;
                        background-color: #1e1e1e;
                        color: #00ff00;
                    }}
                    h1 {{
                        border-bottom: 2px solid #00ff00;
                        padding-bottom: 10px;
                    }}
                    .log-entry {{
                        border: 1px solid #00ff00;
                        padding: 15px;
                        margin: 10px 0;
                        border-radius: 5px;
                        background-color: #2d2d2d;
                    }}
                    .timestamp {{
                        color: #ffff00;
                        font-weight: bold;
                    }}
                    pre {{
                        background-color: #000;
                        padding: 10px;
                        border-radius: 3px;
                        overflow-x: auto;
                    }}
                </style>
            </head>
            <body>
                <h1>🎣 Webhook Test Server</h1>
                <p>Listening for webhook requests on <strong>{SERVER_PORT}</strong></p>

                <h2>Recent Webhook Events</h2>
            """

            if recent_logs:
                for log in recent_logs:
                    html += f"""
                    <div class="log-entry">
                        <div class="timestamp">{log['timestamp']}</div>
                        <div><strong>Method:</strong> {log['method']}</div>
                        <div><strong>Path:</strong> {log['path']}</div>
                        <div><strong>Content-Type:</strong> {log['content_type']}</div>
                        <div><strong>Body:</strong></div>
                        <pre>{json.dumps(log.get('body', ''), indent=2)}</pre>
                    </div>
                    """
            else:
                html += "<p style='color: #ffff00;'>No webhook events received yet.</p>"

            html += """
                <h2>Instructions</h2>
                <ul>
                    <li>Create a webhook endpoint in Redmine at <strong>http://localhost:{SERVER_PORT}</strong></li>
                    <li>Trigger an event (create/update issue, etc.)</li>
                    <li>Watch this page for incoming webhook requests</li>
                    <li>Check console output for detailed logs</li>
                </ul>
            </body>
            </html>
            """
            self.wfile.write(html.encode("utf-8"))

        elif self.path == "/health":
            # Health check endpoint
            self.send_response(200)
            self.send_header("Content-type", "application/json")
            self.end_headers()
            response = {
                "status": "ok",
                "server": "webhook-test-server",
                "timestamp": datetime.datetime.now().isoformat()
            }
            self.wfile.write(json.dumps(response).encode("utf-8"))

        else:
            # 404 for unknown paths
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not Found")


def run_server(port=8080):
    """Start the webhook server"""

    global SERVER_PORT
    SERVER_PORT = port

    print(f"""
{'='*60}
🎣 WEBHOOK TEST SERVER
{'='*60}

Starting webhook test server...
  Port: {port}
  Health check: http://localhost:{port}/health
  Web UI: http://localhost:{port}/
  Log file: {os.path.abspath(LOG_FILE)}

{'='*60}
Waiting for webhook requests...
Press Ctrl+C to stop.
{'='*60}
    """)

    server_address = ('', port)
    httpd = HTTPServer(server_address, WebhookHandler)

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n\n🛑 Server stopped by user")
        httpd.server_close()
    except Exception as e:
        print(f"\n❌ Server error: {e}")
        httpd.server_close()


if __name__ == "__main__":
    # Parse command line arguments
    port = 8080
    if len(sys.argv) > 1:
        try:
            port = int(sys.argv[1])
        except ValueError:
            print(f"Error: Port must be a number. Using default: {port}")

    # Run server
    run_server(port)
