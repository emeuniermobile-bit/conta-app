import { createContext, useContext, type ReactNode } from 'react';

import { useNow } from '@/components/use-tick';
import { corruption } from '@/lib/game';
import { makeTheme, type Theme } from '@/lib/theme';
import { useGame } from './game-context';

const ThemeContext = createContext<Theme>(makeTheme(0));

export const useTheme = () => useContext(ThemeContext);

/** Recalcule la corruption de l'interface au fil de l'incubation. */
export function ThemeProvider({ children }: { children: ReactNode }) {
  const { game } = useGame();
  const now = useNow(30_000, game?.player.state === 'incubating');

  const theme = makeTheme(corruption(game?.player, now));
  return <ThemeContext.Provider value={theme}>{children}</ThemeContext.Provider>;
}
