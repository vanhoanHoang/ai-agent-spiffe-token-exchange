import { ChangeDetectionStrategy, Component, input } from '@angular/core';

import { DemoRun } from '../../core/demo-run';
import { CustodyHop } from '../../core/narrative';

@Component({
  selector: 'dc-custody-panel',
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './custody-panel.html',
  styleUrl: './custody-panel.css',
})
export class CustodyPanel {
  readonly hops = input.required<readonly CustodyHop[]>();
  readonly custody = input.required<DemoRun['chain_of_custody']>();
}
