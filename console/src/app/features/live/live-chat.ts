import { ChangeDetectionStrategy, Component, computed, inject, input, signal } from '@angular/core';

import { LiveClient, LiveUser } from '../../core/live';

interface Turn {
  readonly q: string;
  readonly a: string;
  readonly error: boolean;
}

interface FeedLine {
  readonly step: string;
  readonly detail: string;
}

type HopId = 'svid' | 'exchange' | 'call' | 'answer';
type HopStatus = 'pre' | 'active' | 'done' | 'failed';
type Phase = 'idle' | 'flight' | 'done' | 'error';

const IDLE_HOPS: Record<HopId, HopStatus> = { svid: 'pre', exchange: 'pre', call: 'pre', answer: 'pre' };

@Component({
  selector: 'dc-live-chat',
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './live-chat.html',
  styleUrl: './live-chat.css',
})
export class LiveChat {
  readonly user = input.required<LiveUser>();

  private readonly live = inject(LiveClient);

  protected readonly turns = signal<readonly Turn[]>([]);
  protected readonly pending = signal(false);
  protected readonly phase = signal<Phase>('idle');
  protected readonly hops = signal<Record<HopId, HopStatus>>(IDLE_HOPS);
  protected readonly feed = signal<readonly FeedLine[]>([]);
  protected readonly toolNames = signal<readonly string[]>([]);

  protected readonly hasAudit = computed(() => this.user().scopes.includes('mcp:audit'));

  protected async logout(): Promise<void> {
    await this.live.logout();
    window.location.assign('/console/');
  }

  protected send(box: HTMLInputElement): void {
    const message = box.value.trim();
    if (message === '' || this.pending()) {
      return;
    }
    box.value = '';
    void this.run(message);
  }

  /** Each REAL completion from the server stream advances the hop rail. */
  private onEvent(step: string, detail: string): void {
    this.feed.update((f) => [...f, { step, detail }]);
    if (step === 'svid') {
      this.hops.update((h) => ({ ...h, svid: 'done', exchange: 'active' }));
    } else if (step === 'exchange') {
      this.hops.update((h) => ({ ...h, exchange: 'done', call: 'active' }));
    } else if (step === 'tool') {
      this.toolNames.update((t) => [...t, detail]);
      this.hops.update((h) => ({ ...h, call: 'done', answer: 'active' }));
    }
  }

  private async run(message: string): Promise<void> {
    this.pending.set(true);
    this.phase.set('flight');
    this.hops.set({ ...IDLE_HOPS, svid: 'active' });
    this.feed.set([]);
    this.toolNames.set([]);

    const res = await this.live.chatStream(message, (s, d) => this.onEvent(s, d));
    const error = res.answer === undefined;
    this.turns.update((t) => [...t, { q: message, a: res.answer ?? res.error ?? 'no response', error }]);
    this.hops.update((h) => finishHops(h, error));
    this.phase.set(error ? 'error' : 'done');
    this.pending.set(false);
  }
}

function finishHops(h: Record<HopId, HopStatus>, error: boolean): Record<HopId, HopStatus> {
  const out = { ...h };
  for (const id of Object.keys(out) as HopId[]) {
    if (out[id] === 'active') {
      out[id] = error ? 'failed' : 'done';
    } else if (out[id] === 'pre' && !error) {
      out[id] = 'done';
    }
  }
  return out;
}
