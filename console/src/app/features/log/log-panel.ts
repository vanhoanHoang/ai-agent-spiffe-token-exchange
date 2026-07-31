import { ChangeDetectionStrategy, Component, computed, input, signal } from '@angular/core';

interface LogPart {
  readonly t: string;
  readonly cls: string;
}

function classify(tok: string): string {
  if (/^sub=/.test(tok)) {
    return 'sub';
  }
  if (/^act=/.test(tok)) {
    return 'act';
  }
  if (/^peer=|spiffe:/.test(tok)) {
    return 'peer';
  }
  if (/DENIED|reject|403|401/.test(tok)) {
    return 'reject';
  }
  return 'base';
}

@Component({
  selector: 'dc-log-panel',
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './log-panel.html',
  styleUrl: './log-panel.css',
})
export class LogPanel {
  readonly lines = input.required<readonly string[]>();

  protected readonly shown = signal(2);
  protected readonly replaying = computed(() => this.shown() < this.lines().length);

  protected readonly visible = computed<readonly LogPart[][]>(() =>
    this.lines()
      .slice(0, this.shown())
      .map((line) => line.split(/(\s+)/).map((t) => ({ t, cls: classify(t) }))),
  );

  protected next(): void {
    this.shown.update((n) => Math.min(n + 1, this.lines().length));
  }

  protected all(): void {
    this.shown.set(this.lines().length);
  }
}
