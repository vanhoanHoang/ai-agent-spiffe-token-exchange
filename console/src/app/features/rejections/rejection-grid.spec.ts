import { TestBed } from '@angular/core/testing';

import { rejectionCards } from '../../core/narrative';
import { demoRunFixture } from '../../core/testing/fixture';
import { RejectionGrid } from './rejection-grid';

describe('RejectionGrid', () => {
  it('renders six cards: five acceptance rejections + the scope refusal', async () => {
    await TestBed.configureTestingModule({ imports: [RejectionGrid] }).compileComponents();
    const fixture = TestBed.createComponent(RejectionGrid);
    fixture.componentRef.setInput('cards', rejectionCards(demoRunFixture()));
    await fixture.whenStable();
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelectorAll('.card').length).toBe(6);
    expect(el.textContent).toContain('token scopes (user ∩ agent)');
    expect(el.querySelectorAll('.card.failed').length).toBe(0);
  });

  it('renders a rejection that did NOT hold as an alarm (negative fixture)', async () => {
    const run = demoRunFixture();
    const broken = {
      ...run,
      rejections: run.rejections.map((r, i) =>
        i === 0 ? { ...r, verdict: 'FAILED-TO-DENY' as const } : r,
      ),
    };
    await TestBed.configureTestingModule({ imports: [RejectionGrid] }).compileComponents();
    const fixture = TestBed.createComponent(RejectionGrid);
    fixture.componentRef.setInput('cards', rejectionCards(broken));
    await fixture.whenStable();
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelectorAll('.card.failed').length).toBe(1);
    expect(el.textContent).toContain('NOT REFUSED');
  });
});
