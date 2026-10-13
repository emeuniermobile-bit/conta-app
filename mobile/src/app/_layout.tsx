// Les tâches de localisation en arrière-plan doivent être déclarées dès le
// chargement de l'appli : iOS peut la relancer uniquement pour elles.
import '@/lib/location';

import { Stack } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { StatusBar } from 'expo-status-bar';
import { useEffect } from 'react';
import { View } from 'react-native';

import { Toast } from '@/components/screen';
import { GameProvider, useGame } from '@/state/game-context';
import { ThemeProvider, useTheme } from '@/state/theme-context';

SplashScreen.preventAutoHideAsync().catch(() => {});

function Navigator() {
  const { phase } = useGame();
  const theme = useTheme();

  useEffect(() => {
    if (phase !== 'loading') SplashScreen.hideAsync().catch(() => {});
  }, [phase]);

  if (phase === 'loading') return <View style={{ flex: 1, backgroundColor: theme.background }} />;

  return (
    <View style={{ flex: 1, backgroundColor: theme.background }}>
      <StatusBar style="light" />
      <Stack screenOptions={{ headerShown: false, animation: 'fade', contentStyle: { backgroundColor: theme.background } }}>
        <Stack.Protected guard={phase === 'playing'}>
          <Stack.Screen name="(tabs)" />
        </Stack.Protected>
        <Stack.Protected guard={phase === 'signedOut'}>
          <Stack.Screen name="sign-in" />
        </Stack.Protected>
        <Stack.Protected guard={phase === 'needsProfile'}>
          <Stack.Screen name="profile" />
        </Stack.Protected>
        <Stack.Protected guard={phase === 'needsLocation'}>
          <Stack.Screen name="location" />
        </Stack.Protected>
      </Stack>
      <Toast />
    </View>
  );
}

export default function RootLayout() {
  return (
    <GameProvider>
      <ThemeProvider>
        <Navigator />
      </ThemeProvider>
    </GameProvider>
  );
}
