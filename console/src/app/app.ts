import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';

import { DemoRun, DemoStep, parseDemoRun } from './core/demo-run';
import { LiveClient, LiveState, LiveUser } from './core/live';
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
import { FlowDiagram } from './features/diagram/flow-diagram';
import { RunHeader } from './features/header/run-header';
import { LiveChat } from './features/live/live-chat';
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
    LiveChat,
    FlowDiagram,
  ],
  templateUrl: './app.html',
  styleUrl: './app.css',
})
export class App {
  private readonly liveClient = inject(LiveClient);

  protected readonly run = signal<DemoRun | null>(null);
  protected readonly error = signal<string | null>(null);
  protected readonly stageId = signal<string>('login');
  protected readonly liveState = signal<LiveState>('offline');
  protected readonly liveUser = computed<LiveUser | null>(() => {
    const s = this.liveState();
    return typeof s === 'object' ? s : null;
  });

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
    void this.liveClient.me().then((s) => this.liveState.set(s));
  }

  protected readonly playing = signal(false);
  private playTimer: ReturnType<typeof setInterval> | null = null;

  protected select(id: string): void {
    this.stopPlay();
    this.stageId.set(id);
  }

  /** The mockup's play behavior: walk the five stages, packets and all. */
  protected togglePlay(): void {
    if (this.playing()) {
      this.stopPlay();
      return;
    }
    this.playing.set(true);
    this.stageId.set(STAGES[0].id);
    this.playTimer = setInterval(() => this.advance(), 4000);
  }

  private advance(): void {
    const i = STAGES.findIndex((s) => s.id === this.stageId());
    if (i >= STAGES.length - 1) {
      this.stopPlay();
      return;
    }
    this.stageId.set(STAGES[i + 1].id);
  }

  private stopPlay(): void {
    if (this.playTimer !== null) {
      clearInterval(this.playTimer);
      this.playTimer = null;
    }
    this.playing.set(false);
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
