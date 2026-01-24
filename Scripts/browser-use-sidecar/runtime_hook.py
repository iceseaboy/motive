"""PyInstaller runtime hook to disable system proxy detection.

This hook runs BEFORE any other code in the bundled application,
including when subprocess spawns a new Python instance.
"""
import urllib.request

# Monkey-patch getproxies to return empty dict, disabling all system proxy detection
# This is necessary because macOS reads proxy settings from System Configuration
# framework, which httpx/urllib uses, causing SOCKS proxy errors.
urllib.request.getproxies = lambda: {}

# Also clear proxy environment variables
import os
for var in ['ALL_PROXY', 'all_proxy', 'HTTP_PROXY', 'http_proxy',
            'HTTPS_PROXY', 'https_proxy', 'SOCKS_PROXY', 'socks_proxy']:
    os.environ.pop(var, None)
