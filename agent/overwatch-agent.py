#!/usr/bin/env python3
"""
Overwatch Agent - Lightweight monitoring agent that phones home via HTTPS.
For servers where inbound SSH/WinRM is blocked.
"""

import argparse
import json
import logging
import os
import platform
import signal
import subprocess
import sys
import time

try:
    import psutil
    import requests
except ImportError:
    print("Missing dependencies. Install with: pip install psutil requests")
    sys.exit(1)

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("overwatch-agent")

VERSION = "1.0.0"
HEARTBEAT_INTERVAL = 30
METRICS_INTERVAL = 30
SCRIPT_POLL_INTERVAL = 10

running = True


def signal_handler(sig, frame):
    global running
    logger.info("Shutting down agent...")
    running = False


signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)


class OverwatchAgent:
    def __init__(self, server_url: str, token: str, verify_ssl: bool = True):
        self.server_url = server_url.rstrip("/")
        self.token = token
        self.verify_ssl = verify_ssl
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"Agent {token}",
            "Content-Type": "application/json",
        })
        self.session.verify = verify_ssl
        self.agent_id = None

    def register(self) -> bool:
        try:
            resp = self.session.post(f"{self.server_url}/api/v1/agent/register", json={
                "token": self.token,
                "hostname": platform.node(),
                "os_type": "linux" if sys.platform.startswith("linux") else "windows",
                "agent_version": VERSION,
            })
            if resp.status_code == 200:
                data = resp.json()
                self.agent_id = data.get("agent_id")
                logger.info(f"Registered as agent_id={self.agent_id}, server={data.get('server_name')}")
                return True
            else:
                logger.error(f"Registration failed: {resp.status_code} {resp.text}")
                return False
        except Exception as e:
            logger.error(f"Registration error: {e}")
            return False

    def heartbeat(self):
        try:
            self.session.post(f"{self.server_url}/api/v1/agent/heartbeat", json={
                "agent_version": VERSION,
                "uptime_seconds": int(time.time() - psutil.boot_time()),
            })
        except Exception as e:
            logger.debug(f"Heartbeat failed: {e}")

    def collect_and_push_metrics(self):
        try:
            cpu = psutil.cpu_percent(interval=1)
            mem = psutil.virtual_memory()
            disk = psutil.disk_usage("/")
            net = psutil.net_io_counters()
            load = os.getloadavg() if hasattr(os, "getloadavg") else (0, 0, 0)

            metrics = {
                "cpu_percent": cpu,
                "memory_percent": mem.percent,
                "memory_used_mb": mem.used / (1024 * 1024),
                "memory_total_mb": mem.total / (1024 * 1024),
                "disk_percent": disk.percent,
                "disk_used_gb": disk.used / (1024 ** 3),
                "disk_total_gb": disk.total / (1024 ** 3),
                "network_in_bytes": net.bytes_recv,
                "network_out_bytes": net.bytes_sent,
                "load_average_1m": load[0],
                "load_average_5m": load[1],
                "load_average_15m": load[2],
                "uptime_seconds": int(time.time() - psutil.boot_time()),
            }

            self.session.post(f"{self.server_url}/api/v1/agent/metrics", json=metrics)
            logger.debug("Metrics pushed")
        except Exception as e:
            logger.debug(f"Metrics push failed: {e}")

    def poll_and_execute_scripts(self):
        try:
            resp = self.session.get(f"{self.server_url}/api/v1/agent/scripts")
            if resp.status_code != 200:
                return

            scripts = resp.json()
            for script in scripts:
                self._execute_script(script)
        except Exception as e:
            logger.debug(f"Script poll failed: {e}")

    def _execute_script(self, script: dict):
        execution_id = script["execution_id"]
        content = script["content"]
        script_type = script.get("script_type", "bash")

        logger.info(f"Executing script {script['script_name']} (execution_id={execution_id})")

        try:
            if script_type in ("bash", "shell"):
                result = subprocess.run(
                    ["bash", "-c", content],
                    capture_output=True, text=True, timeout=300,
                )
            elif script_type == "powershell":
                result = subprocess.run(
                    ["powershell", "-Command", content],
                    capture_output=True, text=True, timeout=300,
                )
            elif script_type == "python":
                result = subprocess.run(
                    [sys.executable, "-c", content],
                    capture_output=True, text=True, timeout=300,
                )
            else:
                result = subprocess.run(
                    ["bash", "-c", content],
                    capture_output=True, text=True, timeout=300,
                )

            self.session.post(
                f"{self.server_url}/api/v1/agent/scripts/{execution_id}/result",
                json={
                    "exit_code": result.returncode,
                    "stdout": result.stdout[:50000],
                    "stderr": result.stderr[:10000] if result.stderr else None,
                },
            )
            logger.info(f"Script {execution_id} completed with exit_code={result.returncode}")

        except subprocess.TimeoutExpired:
            self.session.post(
                f"{self.server_url}/api/v1/agent/scripts/{execution_id}/result",
                json={"exit_code": -1, "stdout": "", "stderr": "Execution timed out"},
            )
        except Exception as e:
            self.session.post(
                f"{self.server_url}/api/v1/agent/scripts/{execution_id}/result",
                json={"exit_code": -1, "stdout": "", "stderr": str(e)},
            )

    def run(self):
        if not self.register():
            logger.error("Failed to register. Retrying in 30s...")
            time.sleep(30)
            if not self.register():
                logger.error("Registration failed again. Exiting.")
                sys.exit(1)

        last_heartbeat = 0
        last_metrics = 0
        last_script_poll = 0

        while running:
            now = time.time()

            if now - last_heartbeat >= HEARTBEAT_INTERVAL:
                self.heartbeat()
                last_heartbeat = now

            if now - last_metrics >= METRICS_INTERVAL:
                self.collect_and_push_metrics()
                last_metrics = now

            if now - last_script_poll >= SCRIPT_POLL_INTERVAL:
                self.poll_and_execute_scripts()
                last_script_poll = now

            time.sleep(1)


def main():
    parser = argparse.ArgumentParser(description="Overwatch Monitoring Agent")
    parser.add_argument("--url", required=True, help="Overwatch server URL (e.g. https://overwatch.example.com)")
    parser.add_argument("--token", required=True, help="Agent authentication token")
    parser.add_argument("--no-verify-ssl", action="store_true", help="Disable SSL verification")
    args = parser.parse_args()

    agent = OverwatchAgent(
        server_url=args.url,
        token=args.token,
        verify_ssl=not args.no_verify_ssl,
    )
    agent.run()


if __name__ == "__main__":
    main()
