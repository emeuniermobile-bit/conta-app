import { describe, expect, it } from '@jest/globals';

import { ARRONDISSEMENTS } from '../arrondissements';

describe('arrondissements', () => {
  it('contient les 20 arrondissements dans l’ordre', () => {
    expect(ARRONDISSEMENTS.map((a) => a.code)).toEqual(Array.from({ length: 20 }, (_, i) => i + 1));
  });
  it('place chaque centre dans Paris', () => {
    for (const a of ARRONDISSEMENTS) {
      expect(a.center.latitude).toBeGreaterThan(48.81);
      expect(a.center.latitude).toBeLessThan(48.91);
      expect(a.center.longitude).toBeGreaterThan(2.22);
      expect(a.center.longitude).toBeLessThan(2.47);
      expect(a.rings[0].length).toBeGreaterThan(3);
    }
  });
});
