#!/usr/bin/env node
const PERMISSION_API_PORT = process.env.PERMISSION_API_PORT || '9226';
const PERMISSION_API_URL = `http://localhost:${PERMISSION_API_PORT}/permission`;

process.stdin.setEncoding('utf8');
let buffer = '';

function send(id, result, error) {
  const response = { jsonrpc: '2.0', id };
  if (error) {
    response.error = error;
  } else {
    response.result = result;
  }
  process.stdout.write(JSON.stringify(response) + '\n');
}

async function handleMessage(message) {
  if (!message || typeof message !== 'object') return;
  const { id, method, params } = message;
  if (!method) return;
  if (method === 'initialize') {
    send(id, {
      protocolVersion: '2024-10-07',
      capabilities: { tools: {} },
      serverInfo: { name: 'motive-file-permission', version: '1.0.0' }
    });
    return;
  }
  if (method === 'tools/list') {
    send(id, {
      tools: [{
        name: 'request_file_permission',
        description: 'Request user permission before performing file operations.',
        inputSchema: {
          type: 'object',
          properties: {
            operation: { type: 'string', enum: ['create','delete','rename','move','modify','overwrite'] },
            filePath: { type: 'string' },
            filePaths: { type: 'array', items: { type: 'string' } },
            targetPath: { type: 'string' },
            contentPreview: { type: 'string' }
          },
          required: ['operation']
        }
      }]
    });
    return;
  }
  if (method === 'tools/call') {
    const toolName = params?.name;
    if (toolName !== 'request_file_permission') {
      send(id, { content: [{ type: 'text', text: `Error: Unknown tool: ${toolName}` }], isError: true });
      return;
    }
    try {
      const response = await fetch(PERMISSION_API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(params?.arguments || {})
      });
      if (!response.ok) {
        const text = await response.text();
        send(id, { content: [{ type: 'text', text: `Error: Permission API returned ${response.status}: ${text}` }], isError: true });
        return;
      }
      const result = await response.json();
      const allowed = !!result.allowed;
      send(id, { content: [{ type: 'text', text: allowed ? 'allowed' : 'denied' }] });
    } catch (err) {
      const message = err && err.message ? err.message : String(err);
      send(id, { content: [{ type: 'text', text: `Error: Failed to request permission: ${message}` }], isError: true });
    }
    return;
  }
}

function onLine(line) {
  const trimmed = line.trim();
  if (!trimmed) return;
  let message = null;
  try {
    message = JSON.parse(trimmed);
  } catch {
    return;
  }
  if (message && message.method === 'notifications/initialized') {
    return;
  }
  handleMessage(message);
}

process.stdin.on('data', chunk => {
  buffer += chunk;
  const lines = buffer.split('\n');
  buffer = lines.pop() || '';
  for (const line of lines) {
    onLine(line);
  }
});
