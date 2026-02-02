#!/usr/bin/env node
const QUESTION_API_PORT = process.env.QUESTION_API_PORT || '9227';
const QUESTION_API_URL = `http://localhost:${QUESTION_API_PORT}/question`;

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
      serverInfo: { name: 'motive-ask-user-question', version: '1.0.0' }
    });
    return;
  }
  if (method === 'tools/list') {
    send(id, {
      tools: [{
        name: 'AskUserQuestion',
        description: 'Ask the user a question and wait for their response.',
        inputSchema: {
          type: 'object',
          properties: {
            questions: {
              type: 'array',
              items: {
                type: 'object',
                properties: {
                  question: { type: 'string' },
                  header: { type: 'string' },
                  options: { type: 'array', items: { type: 'object' } },
                  multiSelect: { type: 'boolean' }
                },
                required: ['question']
              },
              minItems: 1,
              maxItems: 4
            }
          },
          required: ['questions']
        }
      }]
    });
    return;
  }
  if (method === 'tools/call') {
    const toolName = params?.name;
    if (toolName !== 'AskUserQuestion') {
      send(id, { content: [{ type: 'text', text: `Error: Unknown tool: ${toolName}` }], isError: true });
      return;
    }
    try {
      const args = params?.arguments || {};
      const questions = Array.isArray(args.questions) ? args.questions : [];
      const question = questions[0] || {};
      const response = await fetch(QUESTION_API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          question: question.question,
          header: question.header,
          options: question.options,
          multiSelect: question.multiSelect
        })
      });
      if (!response.ok) {
        const text = await response.text();
        send(id, { content: [{ type: 'text', text: `Error: Question API returned ${response.status}: ${text}` }], isError: true });
        return;
      }
      const result = await response.json();
      if (result.denied) {
        send(id, { content: [{ type: 'text', text: 'User declined to answer the question.' }] });
        return;
      }
      if (Array.isArray(result.selectedOptions) && result.selectedOptions.length > 0) {
        send(id, { content: [{ type: 'text', text: `User selected: ${result.selectedOptions.join(', ')}` }] });
        return;
      }
      if (result.customText) {
        send(id, { content: [{ type: 'text', text: `User responded: ${result.customText}` }] });
        return;
      }
      send(id, { content: [{ type: 'text', text: 'User provided no response.' }] });
    } catch (err) {
      const message = err && err.message ? err.message : String(err);
      send(id, { content: [{ type: 'text', text: `Error: Failed to ask question: ${message}` }], isError: true });
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
