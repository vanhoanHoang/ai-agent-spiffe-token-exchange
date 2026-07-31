import { ChangeDetectionStrategy, Component, input } from '@angular/core';

import { CallCheck } from '../../core/narrative';

@Component({
  selector: 'dc-call-checks-panel',
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './call-checks-panel.html',
  styleUrl: './call-checks-panel.css',
})
export class CallChecksPanel {
  readonly checks = input.required<readonly CallCheck[]>();
  readonly logLines = input.required<readonly string[]>();
}
