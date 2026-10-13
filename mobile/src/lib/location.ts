// Envoi de la position approximative au serveur.
//
// Batterie : précision « Balanced » (Wi-Fi / antennes, ~100 m), mises à jour
// regroupées tous les 150 m environ, et pause automatique quand on ne bouge pas.
//
// Appli fermée par l'utilisateur : iOS arrête le suivi, mais relance l'appli
// quand on sort d'une zone surveillée (geofencing). On garde donc en permanence
// une zone de 250 m autour de la dernière position ; en sortir réveille l'appli,
// qui envoie la nouvelle position et réarme une zone autour d'elle.
import * as Location from 'expo-location';
import * as TaskManager from 'expo-task-manager';

import { api } from './api';

export const LOCATION_TASK = 'contamination-location';
export const GEOFENCE_TASK = 'contamination-geofence';

const WAKE_RADIUS_M = 250;
const MAX_ACCURACY_M = 500;

let lastSent: { latitude: number; longitude: number; at: number } | null = null;

function distanceMeters(a: { latitude: number; longitude: number }, b: { latitude: number; longitude: number }) {
  const rad = Math.PI / 180;
  const x = (b.longitude - a.longitude) * rad * Math.cos(((a.latitude + b.latitude) / 2) * rad);
  const y = (b.latitude - a.latitude) * rad;
  return Math.sqrt(x * x + y * y) * 6_371_000;
}

/** Faut-il envoyer ce point ? Pas deux fois le même endroit à moins de 2 minutes d'écart. */
export function shouldSend(location: Location.LocationObject): boolean {
  const { latitude, longitude, accuracy } = location.coords;
  if (accuracy != null && (accuracy < 0 || accuracy > MAX_ACCURACY_M)) return false;
  if (lastSent && distanceMeters(lastSent, { latitude, longitude }) < 50 && location.timestamp - lastSent.at < 120_000) {
    return false;
  }
  return true;
}

async function send(location: Location.LocationObject) {
  if (!shouldSend(location)) return;
  const { latitude, longitude, accuracy } = location.coords;
  lastSent = { latitude, longitude, at: location.timestamp };
  try {
    await api.reportLocation({ latitude, longitude, accuracy, recordedAt: new Date(location.timestamp) });
  } catch {
    // Pas de réseau ou session expirée : la position suivante prendra le relais.
  }
}

async function armWakeZone(latitude: number, longitude: number) {
  try {
    await Location.startGeofencingAsync(GEOFENCE_TASK, [
      { identifier: 'here', latitude, longitude, radius: WAKE_RADIUS_M, notifyOnEnter: false, notifyOnExit: true },
    ]);
  } catch {
    // Indisponible (Expo Go, permission « Toujours » absente).
  }
}

// Les tâches doivent être définies au chargement du module, avant tout rendu :
// iOS peut relancer l'appli en arrière-plan uniquement pour elles.
TaskManager.defineTask<{ locations: Location.LocationObject[] }>(LOCATION_TASK, async ({ data, error }) => {
  if (error || !data?.locations?.length) return;
  // Mises à jour regroupées : la première et la dernière suffisent.
  const { locations } = data;
  const picks = locations.length > 1 ? [locations[0], locations[locations.length - 1]] : locations;
  for (const location of picks) await send(location);
  const last = locations[locations.length - 1];
  await armWakeZone(last.coords.latitude, last.coords.longitude);
});

TaskManager.defineTask<{ eventType: Location.GeofencingEventType }>(GEOFENCE_TASK, async ({ data, error }) => {
  if (error || data?.eventType !== Location.GeofencingEventType.Exit) return;
  try {
    const location = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
    await send(location);
    await armWakeZone(location.coords.latitude, location.coords.longitude);
  } catch {
    // On réessaiera à la prochaine sortie de zone.
  }
});

export type LocationAccess = 'undetermined' | 'denied' | 'foreground' | 'always';

export async function getLocationAccess(): Promise<LocationAccess> {
  const fg = await Location.getForegroundPermissionsAsync();
  if (fg.status === 'undetermined') return 'undetermined';
  if (fg.status !== 'granted') return 'denied';
  const bg = await Location.getBackgroundPermissionsAsync().catch(() => null);
  return bg?.status === 'granted' ? 'always' : 'foreground';
}

/** Première étape : « Pendant l'utilisation ». */
export async function requestForeground(): Promise<LocationAccess> {
  await Location.requestForegroundPermissionsAsync();
  return getLocationAccess();
}

/** Deuxième étape : « Toujours » (iOS ne propose ce choix qu'ensuite). */
export async function requestAlways(): Promise<LocationAccess> {
  await Location.requestBackgroundPermissionsAsync().catch(() => null);
  return getLocationAccess();
}

/** Démarre le suivi en arrière-plan si la permission « Toujours » est accordée. */
export async function startBackgroundTracking(): Promise<boolean> {
  if ((await getLocationAccess()) !== 'always') return false;
  try {
    if (!(await Location.hasStartedLocationUpdatesAsync(LOCATION_TASK))) {
      await Location.startLocationUpdatesAsync(LOCATION_TASK, {
        accuracy: Location.Accuracy.Balanced,
        distanceInterval: 150,
        deferredUpdatesDistance: 300,
        deferredUpdatesInterval: 5 * 60_000,
        pausesUpdatesAutomatically: true,
        activityType: Location.ActivityType.Other,
        showsBackgroundLocationIndicator: false,
        foregroundService: {
          notificationTitle: 'Contamination',
          notificationBody: 'Le virus te suit dans Paris.',
          notificationColor: '#2EE6D6',
        },
      });
    }
    return true;
  } catch {
    // Expo Go ne permet pas la localisation en arrière-plan : mode réduit.
    return false;
  }
}

/** Appli ouverte : une position fraîche, et réarmement de la zone de réveil. */
export async function reportCurrentPosition(): Promise<void> {
  const access = await getLocationAccess();
  if (access !== 'foreground' && access !== 'always') return;
  try {
    const location = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
    await send(location);
    if (access === 'always') await armWakeZone(location.coords.latitude, location.coords.longitude);
  } catch {
    // Position indisponible pour l'instant.
  }
}
