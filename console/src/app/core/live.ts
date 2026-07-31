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
}
