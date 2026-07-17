"""
IT Ops Agent - Main entry point for Amazon Bedrock AgentCore Runtime.
Exposes HTTP server on port 8080 that AgentCore routes requests to.
"""
import json
import logging
import traceback
from http.server import HTTPServer, BaseHTTPRequestHandler
from agent import create_it_ops_agent

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("it-ops-agent")

# Initialize agent once at module level for session reuse
agent = create_it_ops_agent()


class AgentHandler(BaseHTTPRequestHandler):
    """HTTP handler for AgentCore Runtime requests."""

    def do_POST(self):
        """Handle incoming agent invocation requests from AgentCore."""
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)

        try:
            request = json.loads(body)
            prompt = request.get("prompt", "")
            session_id = request.get("session_id", "default")

            logger.info(f"[session={session_id}] Received: {prompt[:100]}...")

            # Invoke the Strands agent
            response = agent(prompt)

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()

            result = {
                "response": str(response),
                "session_id": session_id,
                "status": "success"
            }
            self.wfile.write(json.dumps(result).encode())
            logger.info(f"[session={session_id}] Completed successfully")

        except Exception as e:
            logger.error(f"Agent error: {e}\n{traceback.format_exc()}")
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            error_result = {"error": str(e), "status": "error"}
            self.wfile.write(json.dumps(error_result).encode())

    def do_GET(self):
        """Health check endpoint for AgentCore readiness probes."""
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        health = {"status": "healthy", "agent": "it-ops-agent", "version": "1.0"}
        self.wfile.write(json.dumps(health).encode())

    def log_message(self, format, *args):
        """Override to use Python logging instead of stderr."""
        logger.debug(f"HTTP: {format % args}")


def main():
    """Start the HTTP server on port 8080 (AgentCore default)."""
    port = 8080
    server = HTTPServer(("0.0.0.0", port), AgentHandler)
    logger.info(f"IT Ops Agent starting on port {port}")
    logger.info("Ready to receive requests from AgentCore Runtime")
    server.serve_forever()


if __name__ == "__main__":
    main()
