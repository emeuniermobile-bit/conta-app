import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Haptics from 'expo-haptics';
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { AppState } from 'react-native';

import { api } from '@/lib/api';
import {
  errorMessage,
  ITEMS,
  type ArrondissementStatus,
  type Avatar,
  type EncounterLog,
  type GameState,
  type ItemId,
  type LeaderboardEntry,
} from '@/lib/game';
import { getLocationAccess, reportCurrentPosition, startBackgroundTracking } from '@/lib/location';
import { onNotification, registerForPush } from '@/lib/push';
import { supabase } from '@/lib/supabase';

export type Phase = 'loading' | 'signedOut' | 'needsProfile' | 'needsLocation' | 'playing';

const PRIMER_KEY = 'locationPrimerDone';
const REFRESH_MS = 30_000;

type GameContextValue = {
  phase: Phase;
  game: GameState | null;
  city: ArrondissementStatus[];
  leaderboard: LeaderboardEntry[];
  encounters: EncounterLog[];
  busy: boolean;
  toast: string | null;
  dismissToast: () => void;
  refresh: () => Promise<void>;
  sendCode: (phone: string) => Promise<boolean>;
  verifyCode: (phone: string, code: string) => Promise<boolean>;
  setupProfile: (name: string, avatar: Avatar) => Promise<void>;
  finishLocationPrimer: () => Promise<void>;
  claimRation: () => Promise<void>;
  craft: (item: ItemId) => Promise<void>;
  wearMask: () => Promise<void>;
  injectAntidote: () => Promise<void>;
  contribute: (item: ItemId, quantity: number) => Promise<void>;
  signOut: () => Promise<void>;
};

const GameContext = createContext<GameContextValue | null>(null);

export function useGame(): GameContextValue {
  const value = useContext(GameContext);
  if (!value) throw new Error('useGame() hors de <GameProvider>');
  return value;
}

export function GameProvider({ children }: { children: ReactNode }) {
  const [signedIn, setSignedIn] = useState<boolean | null>(null);
  const [primerDone, setPrimerDone] = useState<boolean | null>(null);
  const [game, setGame] = useState<GameState | null>(null);
  const [city, setCity] = useState<ArrondissementStatus[]>([]);
  const [leaderboard, setLeaderboard] = useState<LeaderboardEntry[]>([]);
  const [encounters, setEncounters] = useState<EncounterLog[]>([]);
  const [busy, setBusy] = useState(false);
  const [toast, setToast] = useState<string | null>(null);
  const previousState = useRef<string | null>(null);

  const phase: Phase = useMemo(() => {
    if (signedIn === null || primerDone === null) return 'loading';
    if (!signedIn) return 'signedOut';
    if (!game) return 'loading';
    if (!game.player.display_name) return 'needsProfile';
    if (!primerDone) return 'needsLocation';
    return 'playing';
  }, [signedIn, primerDone, game]);

  const refresh = useCallback(async () => {
    try {
      const state = await api.gameState();
      const before = previousState.current;
      previousState.current = state.player.state;
      if (before && before !== state.player.state) {
        // Survivant : battement sec. Zombie : pulsation lourde.
        Haptics.notificationAsync(
          state.player.state === 'survivor'
            ? Haptics.NotificationFeedbackType.Success
            : Haptics.NotificationFeedbackType.Error,
        );
      }
      setGame(state);
      if (state.player.display_name) {
        const [map, board, log] = await Promise.allSettled([api.cityMap(), api.leaderboard(), api.myEncounters()]);
        if (map.status === 'fulfilled') setCity(map.value);
        if (board.status === 'fulfilled') setLeaderboard(board.value);
        if (log.status === 'fulfilled') setEncounters(log.value);
      }
    } catch {
      // Réseau indisponible : on garde le dernier état connu.
    }
  }, []);

  // Session et préférences enregistrées.
  useEffect(() => {
    AsyncStorage.getItem(PRIMER_KEY).then((v) => setPrimerDone(v === '1'));
    // Appelé tout de suite avec la session enregistrée, puis à chaque connexion / déconnexion.
    const { data } = supabase.auth.onAuthStateChange((event, session) => {
      setSignedIn(!!session);
      if (!session) {
        setGame(null);
        previousState.current = null;
      } else if (event === 'INITIAL_SESSION' || event === 'SIGNED_IN') {
        // Hors du rappel : Supabase déconseille d'y appeler d'autres requêtes.
        setTimeout(() => {
          refresh();
          registerForPush();
        }, 0);
      }
    });
    return () => data.subscription.unsubscribe();
  }, [refresh]);

  useEffect(() => {
    if (phase !== 'playing') return;
    (async () => {
      const background = await startBackgroundTracking();
      const access = await getLocationAccess();
      await api.registerDevice(null, background && access === 'always').catch(() => {});
      await reportCurrentPosition();
      refresh();
    })();

    let timer = setInterval(refresh, REFRESH_MS);
    const appState = AppState.addEventListener('change', (state) => {
      clearInterval(timer);
      if (state === 'active') {
        reportCurrentPosition().then(refresh);
        timer = setInterval(refresh, REFRESH_MS);
      }
    });
    const unsubscribe = onNotification(refresh);
    return () => {
      clearInterval(timer);
      appState.remove();
      unsubscribe();
    };
  }, [phase, refresh]);

  const run = useCallback(async (action: () => Promise<void>): Promise<boolean> => {
    setBusy(true);
    try {
      await action();
      return true;
    } catch (error) {
      setToast(errorMessage(error));
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
      return false;
    } finally {
      setBusy(false);
    }
  }, []);

  const succeed = useCallback(
    async (message: string) => {
      setToast(message);
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
      await refresh();
    },
    [refresh],
  );

  const value: GameContextValue = {
    phase,
    game,
    city,
    leaderboard,
    encounters,
    busy,
    toast,
    dismissToast: () => setToast(null),
    refresh,
    sendCode: (phone) => run(() => api.sendCode(phone)),
    verifyCode: (phone, code) => run(() => api.verifyCode(phone, code)),
    setupProfile: async (name, avatar) => {
      if (await run(() => api.setupProfile(name, avatar))) await refresh();
    },
    finishLocationPrimer: async () => {
      await AsyncStorage.setItem(PRIMER_KEY, '1');
      setPrimerDone(true);
    },
    claimRation: async () => {
      let received = 0;
      const ok = await run(async () => {
        const items = await api.claimDailyRation();
        received = Object.values(items).reduce((sum, n) => sum + (n ?? 0), 0);
      });
      if (ok) await succeed(`Ration reçue : ${received} ingrédients.`);
    },
    craft: async (item) => {
      if (await run(() => api.craft(item))) await succeed(`${ITEMS[item].name} fabriqué.`);
    },
    wearMask: async () => {
      if (await run(async () => void (await api.useMask()))) await succeed('Masque en place.');
    },
    injectAntidote: async () => {
      if (await run(() => api.useAntidote())) await succeed('Antidote injecté. Infection enrayée.');
    },
    contribute: async (item, quantity) => {
      if (await run(async () => void (await api.contributeToLab(item, quantity)))) {
        await succeed(`+${ITEMS[item].labPoints * quantity} points de recherche.`);
      }
    },
    signOut: async () => {
      await run(async () => void (await api.signOut()));
    },
  };

  return <GameContext.Provider value={value}>{children}</GameContext.Provider>;
}
