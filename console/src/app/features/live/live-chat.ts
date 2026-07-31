import { ChangeDetectionStrategy, Component, computed, inject, input, signal } from '@angular/core';

import { LiveClient, LiveUser } from '../../core/live';

interface Turn {
  readonly q: string;
  readonly a: string;
  readonly error: boolean;
}

type Phase = 'idle' | 'flight' | 'done' | 'error';

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

  protected readonly hasAudit = computed(() => this.user().scopes.includes('mcp:audit'));

  protected send(box: HTMLInputElement): void {
    const message = box.value.trim();
    if (message === '' || this.pending()) {
      return;
    }
    box.value = '';
    void this.run(message);
  }

  private async run(message: string): Promise<void> {
    this.pending.set(true);
    this.phase.set('flight');
    const res = await this.live.chat(message);
    const error = res.answer === undefined;
    this.turns.update((t) => [...t, { q: message, a: res.answer ?? res.error ?? 'no response', error }]);
    this.phase.set(error ? 'error' : 'done');
    this.pending.set(false);
  }
}
