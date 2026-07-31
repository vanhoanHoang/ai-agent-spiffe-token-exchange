import { ChangeDetectionStrategy, Component, input } from '@angular/core';

import { RejectionCard } from '../../core/narrative';

@Component({
  selector: 'dc-rejection-grid',
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './rejection-grid.html',
  styleUrl: './rejection-grid.css',
})
export class RejectionGrid {
  readonly cards = input.required<readonly RejectionCard[]>();
}
