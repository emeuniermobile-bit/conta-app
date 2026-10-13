// Accès au serveur : toutes les actions de jeu passent par des fonctions RPC
// (voir supabase/migrations). L'appli ne lit ni n'écrit aucune table directement.
import type {
  ArrondissementStatus,
  Avatar,
  EncounterLog,
  GameState,
  ItemId,
  LeaderboardEntry,
} from './game';
import { supabase } from './supabase';

async function rpc<T>(fn: string, args?: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args);
  if (error) throw error;
  return data as T;
}

export const api = {
  sendCode: async (phone: string) => {
    const { error } = await supabase.auth.signInWithOtp({ phone });
    if (error) throw error;
  },
  verifyCode: async (phone: string, token: string) => {
    const { error } = await supabase.auth.verifyOtp({ phone, token, type: 'sms' });
    if (error) throw error;
  },
  signOut: () => supabase.auth.signOut(),

  gameState: () => rpc<GameState>('get_game_state'),
  cityMap: () => rpc<ArrondissementStatus[]>('get_city_map'),
  leaderboard: () => rpc<LeaderboardEntry[]>('get_leaderboard'),
  myEncounters: () => rpc<EncounterLog[]>('get_my_encounters'),

  setupProfile: (name: string, avatar: Avatar) =>
    rpc<void>('setup_profile', { p_display_name: name.trim(), p_avatar: avatar }),
  registerDevice: (pushToken: string | null, backgroundLocation: boolean | null) =>
    rpc<void>('register_device', { p_push_token: pushToken, p_background_location: backgroundLocation }),
  reportLocation: (p: { latitude: number; longitude: number; accuracy: number | null; recordedAt: Date; until?: Date }) =>
    rpc<{ stored: boolean; reason?: string }>('report_location', {
      p_lat: p.latitude,
      p_lng: p.longitude,
      p_accuracy: p.accuracy,
      p_recorded_at: p.recordedAt.toISOString(),
      p_until: p.until?.toISOString() ?? null,
    }),

  claimDailyRation: () => rpc<Partial<Record<ItemId, number>>>('claim_daily_ration'),
  craft: (item: ItemId) => rpc<void>('craft', { p_item: item, p_quantity: 1 }),
  useMask: () => rpc<string>('use_mask'),
  useAntidote: () => rpc<void>('use_antidote'),
  contributeToLab: (item: ItemId, quantity: number) =>
    rpc<{ points: number }>('contribute_to_lab', { p_item: item, p_quantity: quantity }),
};
