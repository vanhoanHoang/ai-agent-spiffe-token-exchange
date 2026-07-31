import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';

import { Stage } from '../../core/narrative';

@Component({
  selector: 'dc-step-rail',
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './step-rail.html',
  styleUrl: './step-rail.css',
})
export class StepRail {
  readonly stages = input.required<readonly Stage[]>();
  readonly selected = input.required<string>();
  readonly picked = output<string>();
}
