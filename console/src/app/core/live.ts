import { Injectable } from '@angular/core';

/**
 * P6 live mode (D-017): when the console is served BY agent-web (same
 * origin), these endpoints exist and the console gains a live chat panel.
 * Served anywhere else — file://, ng serve, a static host — they don't, and
 * the console falls back to the recorded capture (the M11 exit, unchanged).
 * The API returns answers and identity labels only; never a token.
 */
export interface LiveUser {
  readonly username: string;
  readonly scopes: readonly string[];
}

export type LiveState = 'offline' | 'anonymous' | LiveUser;

export interface ChatResult {
  readonly answer?: string;
  readonly error?: string;
}

/** Public metadata of one certificate in the live X.509-SVID chain. */
export interface LiveCert {
  readonly role: string;
  readonly subject: string;
  readonly issuer: string;
  readonly serial: string;
  readonly notBefore: string;
  readonly notAfter: string;
  readonly uriSans: readonly string[];
  readonly sha256: string;
}

export interface LiveSvid {
  readonly spiffeId: string;
  readonly chain: readonly LiveCert[];
}

@Injectable({ providedIn: 'root' })
export class LiveClient {
  private csrf = '';

  async me(): Promise<LiveState> {
    try {
      const r = await fetch('/api/me');
      if (r.status === 401) {
        return 'anonymous';
      }
      if (!r.ok) {
        return 'offline';
      }
      const d = (await r.json()) as { username?: unknown; scopes?: unknown; csrf?: unknown };
      if (typeof d.username !== 'string' || typeof d.csrf !== 'string') {
        return 'offline';
      }
      this.csrf = d.csrf;
      const scopes = Array.isArray(d.scopes) ? d.scopes.filter((s): s is string => typeof s === 'string') : [];
      return { username: d.username, scopes };
    } catch {
      return 'offline';
    }
  }

  async chat(message: string): Promise<ChatResult> {
    try {
      const r = await fetch('/api/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': this.csrf },
        body: JSON.stringify({ message }),
      });
      return (await r.json()) as ChatResult;
    } catch (e) {
      return { error: e instanceof Error ? e.message : String(e) };
    }
  }

  /** The agent's CURRENT X.509-SVID chain — certificate metadata only,
   *  fetched fresh each call so rotation is visible. Null when not live. */
  async svid(): Promise<LiveSvid | null> {
    try {
      const r = await fetch('/api/svid');
      if (!r.ok) {
        return null;
      }
      const d = (await r.json()) as { spiffeId?: unknown; chain?: unknown };
      if (typeof d.spiffeId !== 'string' || !Array.isArray(d.chain)) {
        return null;
      }
      return { spiffeId: d.spiffeId, chain: d.chain as LiveCert[] };
    } catch {
      return null;
    }
  }

  /** Ends the session (CSRF-protected POST) so a re-login can change the
   *  consented scopes without leaving the console. */
  async logout(): Promise<void> {
    try {
      await fetch('/logout', { method: 'POST', headers: { 'X-CSRF-TOKEN': this.csrf } });
    } catch {
      // session is gone either way; the reload lands on the login banner
    }
  }

  /** Streamed chat (D-018): REAL chain events (svid, exchange, tool) arrive
   *  through onEvent the moment each completes; resolves with the answer. */
  async chatStream(message: string, onEvent: (step: string, detail: string) => void): Promise<ChatResult> {
    try {
      const r = await fetch('/api/chat/stream', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': this.csrf },
        body: JSON.stringify({ message }),
      });
      if (!r.ok || r.body === null) {
        return { error: `HTTP ${r.status}` };
      }
      return await readSseStream(r.body, onEvent);
    } catch (e) {
      return { error: e instanceof Error ? e.message : String(e) };
    }
  }
}

interface SseBlock {
  readonly event: string;
  readonly data: string;
}

function parseSseBlock(block: string): SseBlock | null {
  let event = '';
  const data: string[] = [];
  for (const line of block.split('\n')) {
    if (line.startsWith('event:')) {
      event = line.slice(6).trim();
    } else if (line.startsWith('data:')) {
      data.push(line.slice(5).replace(/^ /, ''));
    }
  }
  return event === '' ? null : { event, data: data.join('\n') };
}

async function readSseStream(
  body: ReadableStream<Uint8Array>,
  onEvent: (step: string, detail: string) => void,
): Promise<ChatResult> {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buf = '';
  let result: ChatResult = { error: 'stream ended without an answer' };
  for (;;) {
    const { done, value } = await reader.read();
    if (done) {
      return result;
    }
    buf += decoder.decode(value, { stream: true });
    let i = buf.indexOf('\n\n');
    while (i >= 0) {
      const block = parseSseBlock(buf.slice(0, i));
      buf = buf.slice(i + 2);
      i = buf.indexOf('\n\n');
      if (block === null) {
        continue;
      }
      if (block.event === 'answer') {
        result = { answer: block.data };
      } else if (block.event === 'error') {
        result = { error: block.data };
      } else {
        onEvent(block.event, block.data);
      }
    }
  }
}
