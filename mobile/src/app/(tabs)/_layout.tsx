import { Tabs } from 'expo-router';

import { Icon } from '@/components/screen';
import { useTheme } from '@/state/theme-context';

export default function TabLayout() {
  const theme = useTheme();
  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: theme.accent,
        tabBarInactiveTintColor: theme.muted,
        tabBarStyle: { backgroundColor: theme.surface, borderTopColor: theme.background },
        tabBarLabelStyle: { fontFamily: theme.mono, fontSize: 10 },
        sceneStyle: { backgroundColor: theme.background },
      }}
    >
      <Tabs.Screen
        name="index"
        options={{
          title: theme.isZombie ? 'Moi' : 'Statut',
          tabBarIcon: ({ color }) => (
            <Icon name={theme.isZombie ? 'eye.trianglebadge.exclamationmark' : 'waveform.path.ecg'} color={color} size={24} />
          ),
        }}
      />
      <Tabs.Screen
        name="carte"
        options={{ title: 'Paris', tabBarIcon: ({ color }) => <Icon name="map" color={color} size={24} /> }}
      />
      <Tabs.Screen
        name="labo"
        options={{ title: 'Labo', tabBarIcon: ({ color }) => <Icon name="flask" color={color} size={24} /> }}
      />
      <Tabs.Screen
        name="classement"
        options={{ title: 'Classement', tabBarIcon: ({ color }) => <Icon name="list.number" color={color} size={24} /> }}
      />
    </Tabs>
  );
}
