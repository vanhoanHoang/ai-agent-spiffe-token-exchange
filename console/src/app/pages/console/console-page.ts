import {
  ChangeDetectionStrategy,
  Component,
  computed,
  ElementRef,
  inject,
  signal,
  viewChild,
} from '@angular/core';
import { RouterLink } from '@angular/router';

import { DemoRun, DemoStep, parseDemoRun } from '../../core/demo-run';
import { IssuedCert, LiveClient, LiveSvid } from '../../core/live';
import {
  callChecks,
  custodyHops,
  rejectionCards,
  STAGES,
  stepById,
  tokenByRef,
} from '../../core/narrative';
import { SessionService } from '../../core/session';
import { CallChecksPanel } from '../../features/call/call-checks-panel';
import { CertPanel } from '../../features/certs/cert-panel';
import { IssuedCertPanel } from '../../features/certs/issued-cert';
import { ChatPanel } from '../../features/chat/chat-panel';
import { CustodyPanel } from '../../features/custody/custody-panel';
import { FlowDiagram } from '../../features/diagram/flow-diagram';
import { RunHeader } from '../../features/header/run-header';
import { LiveChat } from '../../features/live/live-chat';
import { LogPanel } from '../../features/log/log-panel';
import { RejectionGrid } from '../../features/rejections/rejection-grid';
import { StepRail } from '../../features/steps/step-rail';
import { TokenCard } from '../../shared/ui/token-card';

/** Stages that only exist once the chain delegated a second time. */
const SECOND_HOP_STAGES: readonly string[] = ['svid2', 'exchange2', 'issue'];

@Component({
  selector: 'dc-console-page',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    RouterLink,
    RunHeader,
    StepRail,
    TokenCard,
    CertPanel,
    IssuedCertPanel,
    CustodyPanel,
    CallChecksPanel,
    ChatPanel,
    RejectionGrid,
    LogPanel,
    LiveChat,
    FlowDiagram,
  ],
  templateUrl: './console-page.html',
  styleUrl: './console-page.css',
})
export class ConsolePage {
  private readonly liveClient = inject(LiveClient);
  protected readonly session = inject(SessionService);

  protected readonly run = signal<DemoRun | null>(null);
  protected readonly error = signal<string | null>(null);
  protected readonly stageId = signal<string>('login');
  protected readonly tab = signal<'rejections' | 'log'>('rejections');
  protected readonly liveSvid = signal<LiveSvid | null>(null);
  protected readonly liveUser = this.session.user;
  /** How deep the live chain went, so the diagram widens to the second hop
   *  only when the run actually delegated (M12/D-032). */
  protected readonly liveHops = signal(1);
  /** The certificate this session's chain issued, once one exists (D-036). */
  protected readonly issuedCert = signal<IssuedCert | null>(null);

  /** P6.8: live session vs the captured history. Nothing recorded renders in
   *  the live view — captured artifacts live behind the explicit tab, under a
   *  provenance banner, so they can never read as the user's own session. */
  private readonly viewChoice = signal<'live' | 'recorded' | null>(null);
  protected readonly view = computed<'live' | 'recorded'>(
    () => this.viewChoice() ?? (this.liveUser() !== null ? 'live' : 'recorded'),
  );

  protected setView(v: 'live' | 'recorded'): void {
    this.viewChoice.set(v);
  }

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
    void this.session.load();
  }

  protected readonly playing = signal(false);
  private playTimer: ReturnType<typeof setInterval> | null = null;

  protected select(id: string): void {
    this.stopPlay();
    this.stageId.set(id);
    if (id === 'svid' && this.liveUser() !== null) {
      void this.loadSvid();
    }
  }

  /** Live only: the agent's current X.509-SVID chain, refetched on demand. */
  protected async loadSvid(): Promise<void> {
    this.liveSvid.set(await this.liveClient.svid());
  }

  private readonly stagePanel = viewChild<ElementRef<HTMLElement>>('stagePanel');

  /** A live hop chip was clicked: open its stage detail and bring it into view. */
  protected inspect(id: string): void {
    this.select(id);
    this.stagePanel()?.nativeElement.scrollIntoView?.({ behavior: 'smooth', block: 'start' });
  }

  /**
   * A real event landed in the live chain: follow it on the diagram. Hop 1's
   * `svid` opens a fresh chain, so it resets the depth — otherwise a two-hop
   * run would leave the next single-hop run drawing scenery it never used.
   */
  protected follow(stageId: string): void {
    this.stageId.set(stageId);
    if (stageId === 'svid') {
      this.liveHops.set(1);
    } else if (SECOND_HOP_STAGES.includes(stageId)) {
      this.liveHops.set(2);
    }
    if (stageId === 'issue') {
      void this.loadIssued();
    }
  }

  /** The chain reached issuance: fetch the certificate it produced. */
  private async loadIssued(): Promise<void> {
    this.issuedCert.set(await this.liveClient.issued());
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
