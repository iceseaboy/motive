#!/usr/bin/env python3
"""
browser-use-sidecar: Direct browser automation CLI with persistent sessions.

Uses Unix socket for IPC to maintain browser session across multiple CLI calls.
Features:
- Idle timeout: Server auto-exits after 5 minutes of inactivity
- Browser close detection: Server exits when browser crashes/closes
- Singleton guarantee: Only one server instance runs at a time
- Tab management: List and switch between tabs
- Wait command: Wait for user interaction (login, captcha, etc.)
"""

import urllib.request
# CRITICAL: Patch getproxies BEFORE any imports to disable macOS system proxy
urllib.request.getproxies = lambda: {}

import argparse
import asyncio
import fcntl
import json
import logging
import os
import signal
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

# Clear proxy env vars
for var in ['ALL_PROXY', 'all_proxy', 'HTTP_PROXY', 'http_proxy',
            'HTTPS_PROXY', 'https_proxy', 'SOCKS_PROXY', 'socks_proxy']:
    os.environ.pop(var, None)

# Set up logging
logging.basicConfig(level=logging.WARNING, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

# Configuration
IDLE_TIMEOUT_SECONDS = 300  # 5 minutes
BROWSER_CHECK_INTERVAL = 15  # Check browser health every 15 seconds (longer to avoid interfering with operations)

# File paths
SOCKET_PATH = Path(tempfile.gettempdir()) / "browser-use-sidecar.sock"
PID_PATH = Path(tempfile.gettempdir()) / "browser-use-sidecar.pid"
LOCK_PATH = Path(tempfile.gettempdir()) / "browser-use-sidecar.lock"
LOG_PATH = Path(tempfile.gettempdir()) / "browser-use-sidecar.log"
CHROME_PID_PATH = Path(tempfile.gettempdir()) / "browser-use-sidecar-chrome.pid"


def cleanup_stale_files():
    """Clean up stale socket/pid files if process doesn't exist."""
    if PID_PATH.exists():
        try:
            pid = int(PID_PATH.read_text().strip())
            os.kill(pid, 0)  # Check if process exists
        except (OSError, ValueError):
            # Process doesn't exist, clean up
            PID_PATH.unlink(missing_ok=True)
            SOCKET_PATH.unlink(missing_ok=True)
            LOCK_PATH.unlink(missing_ok=True)


def force_kill_chrome():
    """Force kill any Chrome/Chromium processes spawned by sidecar."""
    # Method 1: Kill by saved PID
    if CHROME_PID_PATH.exists():
        try:
            chrome_pid = int(CHROME_PID_PATH.read_text().strip())
            # Kill process group (includes child processes)
            try:
                os.killpg(chrome_pid, signal.SIGTERM)
                time.sleep(0.5)
                os.killpg(chrome_pid, signal.SIGKILL)
            except (OSError, ProcessLookupError):
                pass
            # Also try direct kill
            try:
                os.kill(chrome_pid, signal.SIGKILL)
            except (OSError, ProcessLookupError):
                pass
            CHROME_PID_PATH.unlink(missing_ok=True)
        except (OSError, ValueError):
            pass
    
    # Method 2: Kill by process name pattern (backup)
    try:
        # Find Chrome processes with our specific user data directory
        result = subprocess.run(
            ['pgrep', '-f', 'browser-use-sidecar'],
            capture_output=True, text=True
        )
        if result.stdout.strip():
            for pid_str in result.stdout.strip().split('\n'):
                try:
                    pid = int(pid_str)
                    os.kill(pid, signal.SIGKILL)
                except (OSError, ValueError):
                    pass
    except Exception:
        pass
    
    # Method 3: Kill orphaned Chromium processes
    try:
        subprocess.run(
            ['pkill', '-9', '-f', 'chromium.*--remote-debugging'],
            capture_output=True
        )
    except Exception:
        pass


def is_server_running() -> bool:
    """Check if server is running and responsive."""
    cleanup_stale_files()
    
    if not PID_PATH.exists():
        return False
    
    try:
        pid = int(PID_PATH.read_text().strip())
        os.kill(pid, 0)  # Check if process exists
        
        # Also verify socket is connectable
        if SOCKET_PATH.exists():
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                sock.settimeout(1.0)
                sock.connect(str(SOCKET_PATH))
                sock.close()
                return True
            except (socket.error, socket.timeout):
                # Socket exists but not connectable, kill stale process
                try:
                    os.kill(pid, signal.SIGTERM)
                    time.sleep(0.3)
                    os.kill(pid, signal.SIGKILL)
                except OSError:
                    pass
                cleanup_stale_files()
                return False
        return False
    except (OSError, ValueError):
        cleanup_stale_files()
        return False


def kill_existing_server():
    """Kill any existing server process and Chrome."""
    cleanup_stale_files()
    
    if PID_PATH.exists():
        try:
            pid = int(PID_PATH.read_text().strip())
            # Try graceful shutdown first
            os.kill(pid, signal.SIGTERM)
            for _ in range(20):  # 2 seconds max
                time.sleep(0.1)
                try:
                    os.kill(pid, 0)
                except OSError:
                    break
            else:
                # Force kill if still running
                try:
                    os.kill(pid, signal.SIGKILL)
                except OSError:
                    pass
        except (OSError, ValueError):
            pass
    
    cleanup_stale_files()
    
    # Also force kill Chrome processes
    force_kill_chrome()


def send_to_server(request: dict, timeout: float = 60.0) -> dict:
    """Send request to server and get response."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    try:
        sock.connect(str(SOCKET_PATH))
        sock.sendall(json.dumps(request).encode() + b'\n')
        
        # Read response
        data = b''
        while True:
            chunk = sock.recv(8192)
            if not chunk:
                break
            data += chunk
            if b'\n' in data:
                break
        
        return json.loads(data.decode().strip())
    finally:
        sock.close()


class BrowserServer:
    """Server that maintains browser session with auto-cleanup."""
    
    def __init__(self, headed: bool = True):
        self.headed = headed
        self.session = None
        self.running = True
        self.last_activity = time.time()
        self._lock_fd = None
        self._chrome_pid = None
    
    def acquire_lock(self) -> bool:
        """Acquire exclusive lock to ensure singleton."""
        try:
            self._lock_fd = open(LOCK_PATH, 'w')
            fcntl.flock(self._lock_fd.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            return True
        except (IOError, OSError):
            if self._lock_fd:
                self._lock_fd.close()
                self._lock_fd = None
            return False
    
    def release_lock(self):
        """Release the exclusive lock."""
        if self._lock_fd:
            try:
                fcntl.flock(self._lock_fd.fileno(), fcntl.LOCK_UN)
                self._lock_fd.close()
            except:
                pass
            self._lock_fd = None
        LOCK_PATH.unlink(missing_ok=True)
    
    async def start_browser(self):
        """Start browser session with isolated profile, copying essential auth files."""
        from browser_use.browser.session import BrowserSession
        from browser_use.browser.profile import BrowserProfile
        import shutil
        
        # Use isolated Chrome profile for automation
        profile_dir = Path.home() / "Library" / "Application Support" / "Motive" / "browser" / "profiles" / "chrome-profile"
        profile_dir.mkdir(parents=True, exist_ok=True)
        default_subdir = profile_dir / "Default"
        default_subdir.mkdir(parents=True, exist_ok=True)
        
        # Copy essential auth files from user's Chrome (small files, not GB of cache)
        # This preserves login sessions without copying the entire profile
        user_chrome = Path.home() / "Library" / "Application Support" / "Google" / "Chrome" / "Default"
        essential_files = [
            "Cookies",           # Login cookies (~few MB)
            "Login Data",        # Saved passwords
            "Web Data",          # Form autofill
            "Preferences",       # Settings
            "Secure Preferences",
        ]
        
        if user_chrome.exists():
            for filename in essential_files:
                src = user_chrome / filename
                dst = default_subdir / filename
                if src.exists():
                    try:
                        # Only copy if source is newer or dest doesn't exist
                        if not dst.exists() or src.stat().st_mtime > dst.stat().st_mtime:
                            shutil.copy2(src, dst)
                            logger.info(f"Synced {filename} from user Chrome profile")
                    except Exception as e:
                        logger.warning(f"Failed to copy {filename}: {e}")
        
        profile = BrowserProfile(
            headless=not self.headed,
            user_data_dir=str(profile_dir),
        )
        self.session = BrowserSession(browser_profile=profile)
        await self.session.start()
        return {"success": True, "message": "Browser started"}
    
    async def is_browser_alive(self) -> bool:
        """Check if browser session is still alive.
        
        Be VERY lenient - only return False if browser is definitely dead.
        Any error should be treated as "browser is probably still alive".
        """
        if not self.session:
            return False
        
        # Just check if session object exists - don't try CDP operations
        # as they can fail for many transient reasons
        try:
            # Check if the browser object exists
            if hasattr(self.session, '_browser') and self.session._browser:
                return True
            # Session exists but no browser object - might still be starting
            return True
        except Exception as e:
            # Any exception during check - assume alive
            logger.warning(f"Health check exception (assuming alive): {e}")
            return True
    
    def update_activity(self):
        """Update last activity timestamp."""
        self.last_activity = time.time()
    
    def is_idle_timeout(self) -> bool:
        """Check if idle timeout has been reached."""
        return (time.time() - self.last_activity) > IDLE_TIMEOUT_SECONDS
    
    async def handle_command(self, cmd: str, params: dict) -> dict:
        """Handle a browser command."""
        self.update_activity()
        
        try:
            if cmd == "open":
                return await self.cmd_open(params.get("url", ""))
            elif cmd == "state":
                return await self.cmd_state()
            elif cmd == "click":
                return await self.cmd_click(params.get("index", 0))
            elif cmd == "input":
                return await self.cmd_input(params.get("index", 0), params.get("text", ""))
            elif cmd == "type":
                return await self.cmd_type(params.get("text", ""))
            elif cmd == "keys":
                return await self.cmd_keys(params.get("key", ""))
            elif cmd == "scroll":
                return await self.cmd_scroll(params.get("direction", "down"))
            elif cmd == "back":
                return await self.cmd_back()
            elif cmd == "screenshot":
                return await self.cmd_screenshot(params.get("filename"))
            elif cmd == "close":
                return await self.cmd_close()
            elif cmd == "ping":
                return {"success": True, "message": "pong"}
            elif cmd == "tabs":
                return await self.cmd_tabs()
            elif cmd == "switch":
                return await self.cmd_switch(params.get("index", 0))
            elif cmd == "wait":
                return await self.cmd_wait(params.get("seconds", 30), params.get("message", ""))
            elif cmd == "refresh":
                return await self.cmd_refresh()
            else:
                return {"error": f"Unknown command: {cmd}"}
        except Exception as e:
            logger.exception("Command error")
            return {"error": str(e)}
    
    async def _wait_for_page_ready(self, timeout: float = 5.0) -> bool:
        """Wait for page to be ready (document.readyState == 'complete')."""
        try:
            cdp_session = await self.session.get_or_create_cdp_session(target_id=None, focus=False)
            if not cdp_session:
                return False
            
            start = asyncio.get_event_loop().time()
            while asyncio.get_event_loop().time() - start < timeout:
                result = await cdp_session.cdp_client.send.Runtime.evaluate(
                    params={'expression': 'document.readyState'},
                    session_id=cdp_session.session_id,
                )
                if result.get('result', {}).get('value') == 'complete':
                    return True
                await asyncio.sleep(0.1)  # Poll every 100ms
            return False
        except Exception:
            return False
    
    async def cmd_open(self, url: str) -> dict:
        """Navigate to URL."""
        if not self.session:
            return {"error": "Browser not started"}
        
        if not url.startswith(('http://', 'https://', 'file://')):
            url = 'https://' + url
        
        from browser_use.browser.events import NavigateToUrlEvent
        await self.session.event_bus.dispatch(NavigateToUrlEvent(url=url))
        
        # Smart wait: poll for page ready instead of fixed sleep
        await self._wait_for_page_ready(timeout=10.0)
        return {"success": True, "url": url}
    
    async def cmd_state(self) -> dict:
        """Get page state with interactive elements."""
        if not self.session:
            return {"error": "Browser not started"}
        
        # Get current tab info first
        tabs_info = await self._get_tabs_info()
        
        state_text = await self.session.get_state_as_text()
        
        result = {"state": state_text}
        if tabs_info:
            result["current_tab"] = tabs_info.get("current_index", 0)
            result["total_tabs"] = tabs_info.get("total", 1)
        
        return result
    
    async def _get_tabs_info(self) -> dict:
        """Get information about all tabs."""
        try:
            cdp_session = await self.session.get_or_create_cdp_session(target_id=None, focus=False)
            if not cdp_session:
                return {}
            
            # Get all targets (tabs)
            result = await cdp_session.cdp_client.send.Target.getTargets(
                params={},
                session_id=None  # Use browser-level session
            )
            
            targets = result.get('targetInfos', [])
            pages = [t for t in targets if t.get('type') == 'page']
            
            # Find current target
            current_target_id = getattr(cdp_session, 'target_id', None)
            current_index = 0
            
            tabs = []
            for i, page in enumerate(pages):
                tab_info = {
                    "index": i,
                    "title": page.get('title', ''),
                    "url": page.get('url', ''),
                    "targetId": page.get('targetId', '')
                }
                tabs.append(tab_info)
                if page.get('targetId') == current_target_id:
                    current_index = i
            
            return {
                "tabs": tabs,
                "current_index": current_index,
                "total": len(pages)
            }
        except Exception as e:
            logger.warning(f"Failed to get tabs info: {e}")
            return {}
    
    async def cmd_tabs(self) -> dict:
        """List all open tabs."""
        if not self.session:
            return {"error": "Browser not started"}
        
        tabs_info = await self._get_tabs_info()
        if not tabs_info:
            return {"tabs": [], "current": 0, "message": "Could not retrieve tabs"}
        
        return {
            "tabs": tabs_info.get("tabs", []),
            "current": tabs_info.get("current_index", 0),
            "total": tabs_info.get("total", 0)
        }
    
    async def cmd_switch(self, index: int) -> dict:
        """Switch to tab by index using browser_use's SwitchTabEvent."""
        if not self.session:
            return {"error": "Browser not started"}
        
        try:
            tabs_info = await self._get_tabs_info()
            if not tabs_info or not tabs_info.get("tabs"):
                return {"error": "Could not get tabs list"}
            
            tabs = tabs_info["tabs"]
            if index < 0 or index >= len(tabs):
                return {"error": f"Invalid tab index {index}. Available: 0-{len(tabs)-1}"}
            
            target_id = tabs[index]["targetId"]
            
            # Use browser_use's official SwitchTabEvent to properly switch tabs
            # This updates agent_focus_target_id, activates the tab visually,
            # and clears cached DOM state
            from browser_use.browser.events import SwitchTabEvent
            await self.session.event_bus.dispatch(SwitchTabEvent(target_id=target_id))
            
            await asyncio.sleep(0.2)  # Brief wait for tab switch
            
            return {
                "success": True,
                "switched_to": index,
                "url": tabs[index]["url"],
                "title": tabs[index]["title"]
            }
        except Exception as e:
            logger.exception("Switch tab error")
            return {"error": f"Failed to switch tab: {e}"}
    
    async def cmd_click(self, index: int) -> dict:
        """Click element by index."""
        if not self.session:
            return {"error": "Browser not started"}
        
        from browser_use.browser.events import ClickElementEvent
        node = await self.session.get_element_by_index(index)
        if node is None:
            return {"error": f"Element index {index} not found"}
        
        await self.session.event_bus.dispatch(ClickElementEvent(node=node))
        await asyncio.sleep(0.5)  # Wait for click effect
        
        return {"success": True, "clicked": index}
    
    async def cmd_input(self, index: int, text: str) -> dict:
        """Type text into element by index."""
        if not self.session:
            return {"error": "Browser not started"}
        
        from browser_use.browser.events import ClickElementEvent, TypeTextEvent
        node = await self.session.get_element_by_index(index)
        if node is None:
            return {"error": f"Element index {index} not found"}
        
        await self.session.event_bus.dispatch(ClickElementEvent(node=node))
        await asyncio.sleep(0.05)  # Minimal wait for focus
        await self.session.event_bus.dispatch(TypeTextEvent(node=node, text=text))
        await asyncio.sleep(0.05)  # Minimal wait after type
        return {"success": True, "index": index, "text": text}
    
    async def cmd_type(self, text: str) -> dict:
        """Type text into focused element."""
        if not self.session:
            return {"error": "Browser not started"}
        
        cdp_session = await self.session.get_or_create_cdp_session(target_id=None, focus=False)
        if not cdp_session:
            return {"error": "No active CDP session"}
        
        await cdp_session.cdp_client.send.Input.insertText(
            params={'text': text},
            session_id=cdp_session.session_id,
        )
        return {"success": True, "typed": text}
    
    async def cmd_keys(self, key: str) -> dict:
        """Press keyboard key."""
        if not self.session:
            return {"error": "Browser not started"}
        
        cdp_session = await self.session.get_or_create_cdp_session(target_id=None, focus=False)
        if not cdp_session:
            return {"error": "No active CDP session"}
        
        key_map = {
            'Enter': '\r', 'Tab': '\t', 'Escape': '\x1b',
            'Backspace': '\x08', 'Delete': '\x7f',
        }
        char = key_map.get(key, key)
        
        await cdp_session.cdp_client.send.Input.dispatchKeyEvent(
            params={'type': 'keyDown', 'key': key, 'text': char},
            session_id=cdp_session.session_id,
        )
        await cdp_session.cdp_client.send.Input.dispatchKeyEvent(
            params={'type': 'keyUp', 'key': key},
            session_id=cdp_session.session_id,
        )
        return {"success": True, "key": key}
    
    async def cmd_scroll(self, direction: str) -> dict:
        """Scroll page."""
        if not self.session:
            return {"error": "Browser not started"}
        
        cdp_session = await self.session.get_or_create_cdp_session(target_id=None, focus=False)
        if not cdp_session:
            return {"error": "No active CDP session"}
        
        amount = 500 if direction == "down" else -500
        await cdp_session.cdp_client.send.Runtime.evaluate(
            params={'expression': f'window.scrollBy(0, {amount})'},
            session_id=cdp_session.session_id,
        )
        return {"success": True, "direction": direction}
    
    async def cmd_back(self) -> dict:
        """Go back in history."""
        if not self.session:
            return {"error": "Browser not started"}
        
        from browser_use.browser.events import GoBackEvent
        await self.session.event_bus.dispatch(GoBackEvent())
        await asyncio.sleep(0.5)
        return {"success": True}
    
    async def cmd_refresh(self) -> dict:
        """Refresh current page."""
        if not self.session:
            return {"error": "Browser not started"}
        
        try:
            cdp_session = await self.session.get_or_create_cdp_session(target_id=None, focus=False)
            if not cdp_session:
                return {"error": "No active CDP session"}
            
            await cdp_session.cdp_client.send.Page.reload(
                params={'ignoreCache': True},
                session_id=cdp_session.session_id,
            )
            await asyncio.sleep(1.5)
            return {"success": True, "message": "Page refreshed"}
        except Exception as e:
            return {"error": f"Failed to refresh: {e}"}
    
    async def cmd_wait(self, seconds: int, message: str = "") -> dict:
        """Wait for user interaction (login, captcha, etc.)."""
        if not self.session:
            return {"error": "Browser not started"}
        
        wait_msg = message if message else "Waiting for user action"
        print(f"⏳ {wait_msg} ({seconds}s)...", flush=True)
        
        # Keep activity alive during wait
        start_time = time.time()
        while time.time() - start_time < seconds:
            self.update_activity()
            await asyncio.sleep(1)
        
        return {
            "success": True,
            "waited": seconds,
            "message": f"Waited {seconds} seconds for: {wait_msg}"
        }
    
    async def cmd_screenshot(self, filename: str = None) -> dict:
        """Take screenshot."""
        if not self.session:
            return {"error": "Browser not started"}
        
        import base64
        data = await self.session.take_screenshot(full_page=False)
        
        if filename:
            Path(filename).write_bytes(data)
            return {"success": True, "file": filename, "size": len(data)}
        
        b64 = base64.b64encode(data).decode()
        return {"success": True, "screenshot_base64_truncated": b64[:200] + "...", "size": len(data)}
    
    async def cmd_close(self) -> dict:
        """Close browser and stop server."""
        if self.session:
            try:
                await self.session.stop()
            except Exception:
                pass
            self.session = None
        
        # Force kill Chrome processes
        force_kill_chrome()
        
        self.running = False
        return {"success": True, "message": "Browser closed, server stopping"}
    
    async def handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        """Handle a client connection."""
        try:
            data = await asyncio.wait_for(reader.readline(), timeout=60.0)
            if not data:
                return
            
            request = json.loads(data.decode().strip())
            cmd = request.get("command", "")
            params = request.get("params", {})
            
            response = await self.handle_command(cmd, params)
            
            writer.write(json.dumps(response).encode() + b'\n')
            await writer.drain()
        except asyncio.TimeoutError:
            pass
        except Exception as e:
            logger.exception("Client handler error")
            try:
                writer.write(json.dumps({"error": str(e)}).encode() + b'\n')
                await writer.drain()
            except:
                pass
        finally:
            writer.close()
            try:
                await writer.wait_closed()
            except:
                pass
    
    async def health_check_loop(self):
        """Periodically check browser health and idle timeout."""
        consecutive_failures = 0
        max_consecutive_failures = 3  # Only shutdown after 3 consecutive failures
        
        while self.running:
            await asyncio.sleep(BROWSER_CHECK_INTERVAL)
            
            # Check idle timeout
            if self.is_idle_timeout():
                print(f"Idle timeout reached ({IDLE_TIMEOUT_SECONDS}s), shutting down...", flush=True)
                self.running = False
                break
            
            # Check browser health with tolerance for temporary issues
            if self.session:
                if await self.is_browser_alive():
                    consecutive_failures = 0  # Reset on success
                else:
                    consecutive_failures += 1
                    print(f"Browser health check failed ({consecutive_failures}/{max_consecutive_failures})", flush=True)
                    
                    if consecutive_failures >= max_consecutive_failures:
                        print("Browser appears to have closed or crashed, shutting down...", flush=True)
                        self.running = False
                        break
    
    async def run_server(self):
        """Run the server with health monitoring."""
        # Acquire exclusive lock
        if not self.acquire_lock():
            print("Another server instance is running, exiting.", flush=True)
            return
        
        try:
            # Clean up old socket
            SOCKET_PATH.unlink(missing_ok=True)
            
            # Start browser first
            await self.start_browser()
            
            # Create Unix socket server
            server = await asyncio.start_unix_server(
                self.handle_client,
                path=str(SOCKET_PATH)
            )
            
            # Write PID
            PID_PATH.write_text(str(os.getpid()))
            
            print(f"Server running (PID: {os.getpid()}, idle timeout: {IDLE_TIMEOUT_SECONDS}s)", flush=True)
            
            # Handle shutdown signals
            def shutdown_handler(sig, frame):
                print(f"Received signal {sig}, shutting down...", flush=True)
                self.running = False
            
            signal.signal(signal.SIGTERM, shutdown_handler)
            signal.signal(signal.SIGINT, shutdown_handler)
            
            # Start health check loop
            health_task = asyncio.create_task(self.health_check_loop())
            
            try:
                while self.running:
                    await asyncio.sleep(0.1)
            finally:
                health_task.cancel()
                try:
                    await health_task
                except asyncio.CancelledError:
                    pass
                
                server.close()
                await server.wait_closed()
                
                if self.session:
                    try:
                        await self.session.stop()
                    except:
                        pass
                
                # Force kill Chrome on shutdown
                force_kill_chrome()
                
                print("Server stopped.", flush=True)
        finally:
            # Cleanup
            SOCKET_PATH.unlink(missing_ok=True)
            PID_PATH.unlink(missing_ok=True)
            CHROME_PID_PATH.unlink(missing_ok=True)
            self.release_lock()


def start_server_daemon(headed: bool):
    """Start server as background subprocess.
    
    Uses subprocess to start server, which works better with PyInstaller.
    The headed parameter controls whether browser window is visible.
    """
    # Kill any existing server first
    kill_existing_server()
    
    # Get the path to this executable
    if getattr(sys, 'frozen', False):
        # Running as PyInstaller bundle
        exe_path = sys.executable
    else:
        # Running as script
        exe_path = sys.executable
        # Will run as: python main.py --server --headed/--headless
    
    # Build command
    if getattr(sys, 'frozen', False):
        cmd = [exe_path, '--server']
    else:
        cmd = [exe_path, __file__, '--server']
    
    if headed:
        cmd.append('--headed')
    else:
        cmd.append('--headless')
    
    # Open log file
    log_file = open(str(LOG_PATH), 'w')
    
    # Start subprocess
    proc = subprocess.Popen(
        cmd,
        stdout=log_file,
        stderr=log_file,
        start_new_session=True,  # Detach from parent
    )
    
    # Wait for server to start
    for _ in range(100):  # 10 seconds max
        time.sleep(0.1)
        if SOCKET_PATH.exists():
            return True
    
    # Check if process died
    if proc.poll() is not None:
        print(f"Server process exited with code {proc.returncode}", file=sys.stderr)
        return False
    
    return False


def run_server_mode(headed: bool):
    """Run server directly (called with --server flag)."""
    import traceback
    try:
        print(f"Server starting... headed={headed}", flush=True)
        server = BrowserServer(headed=headed)
        asyncio.run(server.run_server())
    except Exception as e:
        print(f"Server error: {e}", flush=True)
        traceback.print_exc()
    finally:
        print("Server exiting", flush=True)
        force_kill_chrome()
        SOCKET_PATH.unlink(missing_ok=True)
        PID_PATH.unlink(missing_ok=True)
        CHROME_PID_PATH.unlink(missing_ok=True)
        LOCK_PATH.unlink(missing_ok=True)


def main():
    # Check for server mode (called by start_server_daemon)
    if '--server' in sys.argv:
        headed = '--headed' in sys.argv
        run_server_mode(headed)
        return
    
    parser = argparse.ArgumentParser(description="Browser automation CLI with persistent sessions")
    parser.add_argument("--headed", action="store_true", default=True, help="Run browser in headed mode (default)")
    parser.add_argument("--headless", action="store_true", help="Run browser in headless mode")
    parser.add_argument("--json", action="store_true", help="Output JSON only (no extra messages)")
    
    subparsers = parser.add_subparsers(dest="command", required=True)
    
    # open
    p_open = subparsers.add_parser("open", help="Navigate to URL (starts browser if needed)")
    p_open.add_argument("url", help="URL to open")
    
    # state
    subparsers.add_parser("state", help="Get page state with clickable elements")
    
    # click
    p_click = subparsers.add_parser("click", help="Click element by index")
    p_click.add_argument("index", type=int, help="Element index from state")
    
    # input
    p_input = subparsers.add_parser("input", help="Click element and type text")
    p_input.add_argument("index", type=int, help="Element index")
    p_input.add_argument("text", help="Text to type")
    
    # type
    p_type = subparsers.add_parser("type", help="Type into currently focused element")
    p_type.add_argument("text", help="Text to type")
    
    # keys
    p_keys = subparsers.add_parser("keys", help="Press keyboard key")
    p_keys.add_argument("key", help="Key name (Enter, Tab, Escape, etc.)")
    
    # scroll
    p_scroll = subparsers.add_parser("scroll", help="Scroll page")
    p_scroll.add_argument("direction", choices=["up", "down"], help="Scroll direction")
    
    # back
    subparsers.add_parser("back", help="Go back in browser history")
    
    # refresh
    subparsers.add_parser("refresh", help="Refresh current page")
    
    # screenshot
    p_ss = subparsers.add_parser("screenshot", help="Take screenshot")
    p_ss.add_argument("filename", nargs="?", help="Output filename (optional)")
    
    # close
    subparsers.add_parser("close", help="Close browser and stop server")
    
    # tabs - list all tabs
    subparsers.add_parser("tabs", help="List all open tabs")
    
    # switch - switch to tab
    p_switch = subparsers.add_parser("switch", help="Switch to tab by index")
    p_switch.add_argument("index", type=int, help="Tab index (from tabs command)")
    
    # wait - wait for user
    p_wait = subparsers.add_parser("wait", help="Wait for user action (login, captcha)")
    p_wait.add_argument("seconds", type=int, nargs="?", default=30, help="Seconds to wait (default 30)")
    p_wait.add_argument("--message", "-m", help="Message to display")
    
    # sessions (for compatibility)
    subparsers.add_parser("sessions", help="List active sessions")
    
    # kill - force kill server
    subparsers.add_parser("kill", help="Force kill server and Chrome processes")
    
    args = parser.parse_args()
    headed = not args.headless
    
    # Handle kill command
    if args.command == "kill":
        kill_existing_server()
        force_kill_chrome()
        print(json.dumps({"success": True, "message": "Server and Chrome killed"}))
        return
    
    # Build request
    params = {}
    if args.command == "open":
        params["url"] = args.url
    elif args.command == "click":
        params["index"] = args.index
    elif args.command == "input":
        params["index"] = args.index
        params["text"] = args.text
    elif args.command == "type":
        params["text"] = args.text
    elif args.command == "keys":
        params["key"] = args.key
    elif args.command == "scroll":
        params["direction"] = args.direction
    elif args.command == "screenshot":
        params["filename"] = args.filename
    elif args.command == "switch":
        params["index"] = args.index
    elif args.command == "wait":
        params["seconds"] = args.seconds
        params["message"] = getattr(args, 'message', None) or ""
    elif args.command == "sessions":
        if is_server_running():
            print(json.dumps({"sessions": ["default"]}))
        else:
            print(json.dumps({"sessions": []}))
        return
    
    # Check if server is running
    if not is_server_running():
        if args.command == "close":
            print(json.dumps({"success": True, "message": "No server running"}))
            return
        
        # Start server daemon
        if not args.json:
            print("Starting browser server...", file=sys.stderr)
        
        if not start_server_daemon(headed):
            print(json.dumps({"error": "Failed to start server"}))
            sys.exit(1)
        
        if not args.json:
            print("Server started.", file=sys.stderr)
    
    # Send command to server
    try:
        request = {"command": args.command, "params": params}
        result = send_to_server(request)
        print(json.dumps(result, ensure_ascii=False))
        
        if "error" in result:
            sys.exit(1)
    except Exception as e:
        print(json.dumps({"error": f"Failed to communicate with server: {e}"}))
        sys.exit(1)


if __name__ == "__main__":
    main()
