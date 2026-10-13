// Types et règles côté appli. La source de vérité reste le serveur
// (supabase/migrations) : ces valeurs ne servent qu'à l'affichage.

export type PlayerState = 'survivor' | 'incubating' | 'zombie';

export type MaskStyle = 'classic' | 'visor' | 'filter' | 'plague';

export type Avatar = { mask: MaskStyle; color: string };

export const DEFAULT_AVATAR: Avatar = { mask: 'classic', color: '#2EE6D6' };
export const AVATAR_COLORS = ['#2EE6D6', '#F2F5F7', '#7CFF6B', '#FFB020', '#5B8CFF', '#FF5C8A'];
export const MASK_STYLES: { id: MaskStyle; label: string }[] = [
  { id: 'classic', label: 'Classique' },
  { id: 'visor', label: 'Visière' },
  { id: 'filter', label: 'Double filtre' },
  { id: 'plague', label: 'Bec' },
];

export type Player = {
  id: string;
  display_name: string | null;
  avatar: Avatar;
  state: PlayerState;
  infected_at: string | null;
  infected_place: string | null;
  transform_at: string | null;
  mask_until: string | null;
  ration_available: boolean;
  contaminations: number;
  cures: number;
  lab_contribution: number;
  arrondissement: number | null;
};

export type Season = {
  id: number;
  strain_name: string;
  started_at: string;
  ends_at: string;
  lab_points: number;
  lab_goal: number;
  active_players: number;
  zombies: number;
  infection_ratio: number;
};

export type GameState = {
  player: Player;
  inventory: Partial<Record<ItemId, number>>;
  season: Season | null;
  server_time: string;
};

export type ZoneStatus = 'green' | 'contested' | 'red' | 'unknown';

export type ArrondissementStatus = {
  code: number;
  name: string;
  active_players: number | null;
  infection_ratio: number | null;
  status: ZoneStatus;
};

export type LeaderboardEntry = {
  rank: number;
  display_name: string;
  contaminations: number;
  is_me: boolean;
};

export type EncounterLog = {
  occurred_at: string;
  place: string;
  infected: boolean;
  by_ghost: boolean;
};

// --- Objets -----------------------------------------------------------------

export type ItemId = 'tissu' | 'filtre' | 'alcool' | 'plante' | 'reactif' | 'masque' | 'antidote';

export const ITEMS: Record<ItemId, { name: string; labPoints: number }> = {
  tissu: { name: 'Tissu', labPoints: 1 },
  filtre: { name: 'Filtre à charbon', labPoints: 2 },
  alcool: { name: 'Alcool médical', labPoints: 1 },
  plante: { name: 'Plante médicinale', labPoints: 2 },
  reactif: { name: 'Réactif', labPoints: 3 },
  masque: { name: 'Masque', labPoints: 0 },
  antidote: { name: 'Antidote', labPoints: 0 },
};

export const INGREDIENTS: ItemId[] = ['tissu', 'filtre', 'alcool', 'plante', 'reactif'];
export const CRAFTABLE: ItemId[] = ['masque', 'antidote'];

export const RECIPES: Partial<Record<ItemId, [ItemId, number][]>> = {
  masque: [['tissu', 2], ['filtre', 1]],
  antidote: [['plante', 2], ['alcool', 1], ['reactif', 1]],
};

export function quantity(game: GameState | null, item: ItemId): number {
  return game?.inventory[item] ?? 0;
}

export function canCraft(game: GameState | null, item: ItemId): boolean {
  const recipe = RECIPES[item];
  return !!recipe && recipe.every(([ingredient, n]) => quantity(game, ingredient) >= n);
}

export function recipeLabel(item: ItemId): string {
  return (RECIPES[item] ?? []).map(([i, n]) => `${n} ${ITEMS[i].name.toLowerCase()}`).join(' · ');
}

// --- Incubation ---------------------------------------------------------------

const INCUBATION_MS = 3 * 3600 * 1000;

/** Degré de corruption de l'interface : 0 survivant sain, 1 zombie. */
export function corruption(player: Player | null | undefined, now: number = Date.now()): number {
  if (!player || player.state === 'survivor') return 0;
  if (player.state === 'zombie') return 1;
  const end = player.transform_at ? Date.parse(player.transform_at) : now + INCUBATION_MS;
  const start = player.infected_at ? Date.parse(player.infected_at) : end - INCUBATION_MS;
  const total = Math.max(end - start, 1);
  const elapsed = Math.min(Math.max(1 - (end - now) / total, 0), 1);
  // On démarre à 0,15 pour que l'infection se voie immédiatement, sans jamais atteindre 1.
  return 0.15 + 0.75 * elapsed;
}

/** « 2:05:09 » */
export function formatCountdown(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}

/** « 8h42 », heure de Paris. */
export function parisTime(iso: string): string {
  const text = new Date(iso).toLocaleTimeString('fr-FR', {
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
    timeZone: 'Europe/Paris',
  });
  const [hour, minute] = text.split(/\D+/);
  return `${Number(hour)}h${minute}`;
}

export function arrondissementLabel(code: number): string {
  return code === 1 ? '1er' : `${code}e`;
}

// --- Compte -----------------------------------------------------------------

/** « 06 12 34 56 78 » → « +33612345678 ». */
export function normalizePhone(input: string): string {
  const digits = input.replace(/[^\d+]/g, '');
  if (digits.startsWith('+')) return digits;
  if (digits.startsWith('00')) return `+${digits.slice(2)}`;
  if (digits.startsWith('0')) return `+33${digits.slice(1)}`;
  return `+33${digits}`;
}

export function isValidPhone(e164: string): boolean {
  return /^\+\d{10,15}$/.test(e164);
}

export function isValidDisplayName(name: string): boolean {
  const n = name.trim().length;
  return n >= 2 && n <= 24;
}

/** Messages lisibles pour les erreurs levées par les fonctions SQL. */
export function errorMessage(error: unknown): string {
  const text = error instanceof Error ? error.message : typeof error === 'object' && error && 'message' in error
    ? String((error as { message: unknown }).message)
    : String(error);
  const known: [string, string][] = [
    ['ration_already_claimed', "Ration déjà récupérée aujourd'hui. Reviens demain."],
    ['not_enough_items', 'Il te manque des ingrédients.'],
    ['zombies_cannot_craft', 'Les zombies ne fabriquent rien.'],
    ['zombies_cannot_research', "Le Laboratoire n'ouvre pas aux zombies."],
    ['mask_useless_now', 'Trop tard pour un masque : tu es déjà infecté.'],
    ['not_incubating', "Tu n'es pas infecté."],
    ['not_a_sample', 'Cet objet ne sert pas d’échantillon.'],
    ['no_active_season', 'Aucune saison en cours.'],
    ['Invalid phone', 'Numéro de téléphone invalide.'],
    ['Token has expired or is invalid', 'Code incorrect ou expiré.'],
  ];
  return known.find(([key]) => text.includes(key))?.[1] ?? 'Liaison avec le centre de crise perdue. Réessaie.';
}
