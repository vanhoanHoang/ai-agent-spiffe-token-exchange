import { ChangeDetectionStrategy, Component, computed, signal } from '@angular/core';

import { DemoRun, DemoStep, parseDemoRun } from './core/demo-run';
import {
  callChecks,
  custodyHops,
  rejectionCards,
  STAGES,
  stepById,
  tokenByRef,
} from './core/narrative';
import { CallChecksPanel } from './features/call/call-checks-panel';
import { ChatPanel } from './features/chat/chat-panel';
import { CustodyPanel } from './features/custody/custody-panel';
import { RunHeader } from './features/header/run-header';
import { LogPanel } from './features/log/log-panel';
import { RejectionGrid } from './features/rejections/rejection-grid';
import { StepRail } from './features/steps/step-rail';
import { TokenCard } from './shared/ui/token-card';

@Component({
  selector: 'dc-root',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    RunHeader,
    StepRail,
    TokenCard,
    CustodyPanel,
    CallChecksPanel,
    ChatPanel,
    RejectionGrid,
    LogPanel,
  ],
  templateUrl: './app.html',
  styleUrl: './app.css',
})
export class App {
  protected readonly run = signal<DemoRun | null>(null);
  protected readonly error = signal<string | null>(null);
  protected readonly stageId = signal<string>('login');

  protected readonly stages = STAGES;
  protected readonly stage = computed(
    () => STAGES.find((s) => s.id === this.stageId()) ?? STAGES[0],
  );
  protected readonly subjectToken = computed(() => {
    const r = this.run();
    return r ? tokenByRef(r, 'subject_token') : undefined;
  });
  protected readonly exchangedToken = computed(() => {
    const r = this.run();
    return r ? tokenByRef(r, 'exchanged_token') : undefined;
  });
  protected readonly hops = computed(() => {
    const r = this.run();
    return r ? custodyHops(r) : [];
  });
  protected readonly checks = computed(() => {
    const r = this.run();
    return r ? callChecks(r) : [];
  });
  protected readonly callLog = computed(() => this.step('chat-whoami')?.log_lines ?? []);
  protected readonly chatSteps = computed(() =>
    ['chat-whoami', 'chat-audit-refused']
      .map((id) => this.step(id))
      .filter((s): s is DemoStep => s !== undefined),
  );
  protected readonly rejections = computed(() => {
    const r = this.run();
    return r ? rejectionCards(r) : [];
  });

  constructor() {
    void this.load();
  }

  protected select(id: string): void {
    this.stageId.set(id);
  }

  private step(id: string): DemoStep | undefined {
    const r = this.run();
    return r ? stepById(r, id) : undefined;
  }

  private async load(): Promise<void> {
    try {
      const res = await fetch('demo-run.json');
      if (!res.ok) {
        throw new Error(`demo-run.json: HTTP ${res.status}`);
      }
      this.run.set(parseDemoRun(await res.json()));
    } catch (e) {
      this.error.set(e instanceof Error ? e.message : String(e));
    }
  }
}
