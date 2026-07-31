import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';

import { DemoRun } from '../../core/demo-run';

@Component({
  selector: 'dc-run-header',
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './run-header.html',
  styleUrl: './run-header.css',
})
export class RunHeader {
  readonly run = input.required<DemoRun>();

  protected readonly issuer = computed(() => {
    const iss = this.run().tokens[0]?.claims['iss'];
    return typeof iss === 'string' ? iss : 'unknown issuer';
  });
}
