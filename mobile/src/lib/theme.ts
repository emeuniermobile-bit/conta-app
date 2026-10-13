import { Platform } from 'react-native';

// Les deux visages de l'appli. Pendant l'incubation, l'interface glisse
// progressivement du centre de crise (cyan) vers la corruption (rouge).

export type Theme = {
  corruption: number;
  isZombie: boolean;
  background: string;
  surface: string;
  accent: string;
  text: string;
  muted: string;
  danger: string;
  safe: string;
  contested: string;
  mono: string;
};

const SURVIVOR = { background: '#090E12', surface: '#111B22', accent: '#2EE6D6', text: '#F2F5F7', muted: '#6B8794' };
const ZOMBIE = { background: '#0A0000', surface: '#1A0505', accent: '#FF1E1E', text: '#FFD6D6', muted: '#8A3A3A' };

export function mixHex(a: string, b: string, t: number): string {
  const pa = parseInt(a.slice(1), 16);
  const pb = parseInt(b.slice(1), 16);
  const channel = (shift: number) => {
    const ca = (pa >> shift) & 0xff;
    const cb = (pb >> shift) & 0xff;
    return Math.round(ca + (cb - ca) * t);
  };
  const value = (channel(16) << 16) | (channel(8) << 8) | channel(0);
  return `#${value.toString(16).padStart(6, '0').toUpperCase()}`;
}

export function withAlpha(hex: string, alpha: number): string {
  return `${hex}${Math.round(Math.min(Math.max(alpha, 0), 1) * 255).toString(16).padStart(2, '0')}`;
}

export function makeTheme(corruption: number): Theme {
  const t = Math.min(Math.max(corruption, 0), 1);
  const mix = (key: keyof typeof SURVIVOR) => mixHex(SURVIVOR[key], ZOMBIE[key], t);
  return {
    corruption: t,
    isZombie: t >= 1,
    background: mix('background'),
    surface: mix('surface'),
    accent: mix('accent'),
    text: mix('text'),
    muted: mix('muted'),
    danger: '#FF3B3B',
    safe: '#3DDC84',
    contested: '#FFB020',
    mono: Platform.select({ ios: 'Menlo', android: 'monospace', default: 'monospace' }),
  };
}

/** Bruit pseudo-aléatoire déterministe dans [-1, 1]. */
export function noise(seed: number, salt: number): number {
  const x = Math.sin(seed * 12.9898 + salt * 78.233) * 43758.5453;
  return (x - Math.floor(x)) * 2 - 1;
}

const SWAPS: Record<string, string> = {
  a: '@', e: '3', i: '!', o: '0', s: '$', t: '7',
  A: 'Λ', E: 'Ξ', O: 'Ø', S: '§', R: 'Я', N: 'И',
};

/** Remplace quelques lettres par des glyphes voisins, proportionnellement à la corruption. */
export function corruptText(text: string, corruption: number, seed: number): string {
  if (corruption <= 0) return text;
  const rate = corruption >= 1 ? 0.18 : corruption * 0.08;
  return Array.from(text)
    .map((char, i) => (SWAPS[char] && noise(seed + i * 31, 7) * 0.5 + 0.5 < rate ? SWAPS[char] : char))
    .join('');
}
