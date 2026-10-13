// Contours des arrondissements (source : opendata.paris.fr, licence ODbL), simplifiés à ~8 m.
import geojson from '@/assets/data/arrondissements.json';

export type LatLng = { latitude: number; longitude: number };

export type ArrondissementShape = {
  code: number;
  name: string;
  rings: LatLng[][];
  center: LatLng;
};

type Feature = {
  properties: { code: number; name: string };
  geometry: { type: 'Polygon' | 'MultiPolygon'; coordinates: number[][][] | number[][][][] };
};

const toLatLng = ([longitude, latitude]: number[]): LatLng => ({ latitude, longitude });

/** Centre approximatif (moyenne des sommets du contour extérieur). */
function centroid(ring: LatLng[]): LatLng {
  const sum = ring.reduce((acc, p) => ({ latitude: acc.latitude + p.latitude, longitude: acc.longitude + p.longitude }), {
    latitude: 0,
    longitude: 0,
  });
  return { latitude: sum.latitude / ring.length, longitude: sum.longitude / ring.length };
}

export function parseArrondissements(data: { features: Feature[] }): ArrondissementShape[] {
  return data.features
    .map((feature) => {
      const polygons = (
        feature.geometry.type === 'Polygon' ? [feature.geometry.coordinates] : feature.geometry.coordinates
      ) as number[][][][];
      // On ne garde que les contours extérieurs (Paris n'a pas d'arrondissement troué).
      const rings = polygons.map((polygon) => polygon[0].map(toLatLng));
      const largest = rings.reduce((a, b) => (b.length > a.length ? b : a));
      return { code: feature.properties.code, name: feature.properties.name, rings, center: centroid(largest) };
    })
    .sort((a, b) => a.code - b.code);
}

export const ARRONDISSEMENTS = parseArrondissements(geojson as { features: Feature[] });

export const PARIS_REGION = {
  latitude: 48.8575,
  longitude: 2.346,
  latitudeDelta: 0.13,
  longitudeDelta: 0.17,
};
