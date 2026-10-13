import { describe, expect, it } from '@jest/globals';

import {
  canCraft,
  corruption,
  errorMessage,
  formatCountdown,
  isValidPhone,
  normalizePhone,
  parisTime,
  quantity,
  recipeLabel,
  type GameState,
  type Player,
} from '../game';

const player = (over: Partial<Player>): Player => ({
  id: 'p',
  display_name: 'Alice',
  avatar: { mask: 'classic', color: '#2EE6D6' },
  state: 'survivor',
  infected_at: null,
  infected_place: null,
  transform_at: null,
  mask_until: null,
  ration_available: true,
  contaminations: 0,
  cures: 0,
  lab_contribution: 0,
  arrondissement: null,
  ...over,
});

const game = (inventory: GameState['inventory']): GameState => ({
  player: player({}),
  inventory,
  season: null,
  server_time: '2026-10-13T08:00:00Z',
});

describe('numéro de téléphone', () => {
  it('met les numéros français au format international', () => {
    expect(normalizePhone('06 12 34 56 78')).toBe('+33612345678');
    expect(normalizePhone('0033 6 12 34 56 78')).toBe('+33612345678');
    expect(normalizePhone('+33 6 12-34-56-78')).toBe('+33612345678');
  });
  it('refuse un numéro trop court', () => {
    expect(isValidPhone(normalizePhone('06 12'))).toBe(false);
    expect(isValidPhone(normalizePhone('06 12 34 56 78'))).toBe(true);
  });
});

describe('fabrication', () => {
  it('vérifie les ingrédients de la recette', () => {
    expect(canCraft(game({ tissu: 2, filtre: 1 }), 'masque')).toBe(true);
    expect(canCraft(game({ tissu: 1, filtre: 1 }), 'masque')).toBe(false);
    expect(canCraft(game({ plante: 2, alcool: 1, reactif: 1 }), 'antidote')).toBe(true);
    expect(canCraft(game({}), 'tissu')).toBe(false);
  });
  it('décrit la recette', () => {
    expect(recipeLabel('masque')).toBe('2 tissu · 1 filtre à charbon');
  });
  it('compte zéro pour un objet absent', () => {
    expect(quantity(game({}), 'antidote')).toBe(0);
    expect(quantity(null, 'antidote')).toBe(0);
  });
});

describe('corruption de l’interface', () => {
  const infected = '2026-10-13T08:00:00Z';
  const transform = '2026-10-13T11:00:00Z';
  it('vaut 0 pour un survivant et 1 pour un zombie', () => {
    expect(corruption(player({ state: 'survivor' }))).toBe(0);
    expect(corruption(player({ state: 'zombie' }))).toBe(1);
  });
  it('augmente pendant l’incubation sans atteindre 1', () => {
    const p = player({ state: 'incubating', infected_at: infected, transform_at: transform });
    const start = corruption(p, Date.parse(infected));
    const middle = corruption(p, Date.parse('2026-10-13T09:30:00Z'));
    const end = corruption(p, Date.parse(transform));
    expect(start).toBeCloseTo(0.15);
    expect(middle).toBeCloseTo(0.525);
    expect(end).toBeCloseTo(0.9);
  });
});

describe('affichage', () => {
  it('formate le compte à rebours', () => {
    expect(formatCountdown(2 * 3600_000 + 5 * 60_000 + 9_000)).toBe('2:05:09');
    expect(formatCountdown(-5)).toBe('0:00:00');
  });
  it('donne l’heure de Paris', () => {
    expect(parisTime('2026-10-13T06:42:00Z')).toBe('8h42');
    expect(parisTime('2026-12-01T22:05:00Z')).toBe('23h05');
  });
  it('traduit les erreurs du serveur', () => {
    expect(errorMessage({ message: 'ration_already_claimed' })).toMatch(/demain/);
    expect(errorMessage(new Error('not_enough_items: tissu'))).toMatch(/ingrédients/);
    expect(errorMessage('boom')).toMatch(/Réessaie/);
  });
});
