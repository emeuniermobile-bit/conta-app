import { describe, expect, it } from '@jest/globals';

import { corruptText, makeTheme, mixHex, withAlpha } from '../theme';

describe('thème', () => {
  it('mélange deux couleurs', () => {
    expect(mixHex('#000000', '#FFFFFF', 0)).toBe('#000000');
    expect(mixHex('#000000', '#FFFFFF', 1)).toBe('#FFFFFF');
    expect(mixHex('#000000', '#FFFFFF', 0.5)).toBe('#808080');
  });
  it('passe du cyan au rouge', () => {
    expect(makeTheme(0).accent).toBe('#2EE6D6');
    expect(makeTheme(1).accent).toBe('#FF1E1E');
    expect(makeTheme(1).isZombie).toBe(true);
    expect(makeTheme(0.9).isZombie).toBe(false);
  });
  it('ajoute une transparence', () => {
    expect(withAlpha('#2EE6D6', 1)).toBe('#2EE6D6ff');
    expect(withAlpha('#2EE6D6', 0)).toBe('#2EE6D600');
  });
  it('ne corrompt le texte que chez les infectés', () => {
    const text = 'Les survivants resistent encore a Paris';
    expect(corruptText(text, 0, 3)).toBe(text);
    const zombie = Array.from({ length: 20 }, (_, seed) => corruptText(text, 1, seed));
    expect(zombie.some((t) => t !== text)).toBe(true);
    expect(zombie.every((t) => Array.from(t).length === Array.from(text).length)).toBe(true);
  });
});
