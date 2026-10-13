// Notifications d'alerte : autorisation et enregistrement du jeton Expo auprès du serveur.
import Constants from 'expo-constants';
import * as Notifications from 'expo-notifications';
import { Platform } from 'react-native';

import { api } from './api';

// Appli ouverte : on affiche quand même l'alerte.
Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: true,
    shouldSetBadge: false,
  }),
});

export async function registerForPush(): Promise<string | null> {
  try {
    if (Platform.OS === 'android') {
      await Notifications.setNotificationChannelAsync('alerts', {
        name: 'Alertes sanitaires',
        importance: Notifications.AndroidImportance.HIGH,
        vibrationPattern: [0, 200, 120, 200],
      });
    }
    let { status } = await Notifications.getPermissionsAsync();
    if (status !== 'granted') {
      ({ status } = await Notifications.requestPermissionsAsync());
    }
    if (status !== 'granted') return null;

    const projectId = Constants.expoConfig?.extra?.eas?.projectId ?? Constants.easConfig?.projectId;
    if (!projectId) return null; // projet pas encore lié à EAS (`eas init`)
    const { data: token } = await Notifications.getExpoPushTokenAsync({ projectId });
    await api.registerDevice(token, null);
    return token;
  } catch {
    // Expo Go, simulateur ou pas de réseau : on réessaiera au prochain lancement.
    return null;
  }
}

/** Appelle `listener` quand une notification arrive appli ouverte (pour rafraîchir l'état). */
export function onNotification(listener: () => void) {
  const sub = Notifications.addNotificationReceivedListener(listener);
  return () => sub.remove();
}
