import { useEffect, useState } from 'react';

/** Renvoie un compteur qui avance toutes les `ms` millisecondes (si `enabled`). */
export function useTick(ms: number, enabled = true): number {
  const [tick, setTick] = useState(0);
  useEffect(() => {
    if (!enabled) return;
    const timer = setInterval(() => setTick((t) => t + 1), ms);
    return () => clearInterval(timer);
  }, [ms, enabled]);
  return tick;
}

/** Heure courante (ms), rafraîchie toutes les `ms` millisecondes. */
export function useNow(ms: number, enabled = true): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!enabled) return;
    const timer = setInterval(() => setNow(Date.now()), ms);
    return () => clearInterval(timer);
  }, [ms, enabled]);
  return now;
}
