import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';

import { DemoStep } from '../../core/demo-run';

interface ChatMessage {
  readonly label: string;
  readonly text: string;
  readonly deny: boolean;
}

@Component({
  selector: 'dc-chat-panel',
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './chat-panel.html',
  styleUrl: './chat-panel.css',
})
export class ChatPanel {
  readonly steps = input.required<readonly DemoStep[]>();

  protected readonly messages = computed<readonly ChatMessage[]>(() =>
    this.steps().flatMap((s) => [
      { label: 'alice', text: s.prompt ?? '', deny: false },
      { label: s.verdict === 'deny' ? 'agent · refused by the server' : 'agent', text: s.answer ?? '', deny: s.verdict === 'deny' },
    ]),
  );
}
