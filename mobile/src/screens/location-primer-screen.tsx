import { useEffect, useState } from 'react';
import { View } from 'react-native';

import { Icon, Screen, type SymbolName } from '@/components/screen';
import { ActionButton, GlitchText, Mono, Panel } from '@/components/ui';
import { getLocationAccess, requestAlways, requestForeground, type LocationAccess } from '@/lib/location';
import { useGame } from '@/state/game-context';
import { useTheme } from '@/state/theme-context';

/**
 * Explique la permission « Toujours » avant de la demander.
 * Sans elle, on joue en mode réduit (ration quotidienne, rencontres appli ouverte).
 */
export function LocationPrimerScreen() {
  const { finishLocationPrimer } = useGame();
  const theme = useTheme();
  const [access, setAccess] = useState<LocationAccess | null>(null);
  const [askedAlways, setAskedAlways] = useState(false);

  useEffect(() => {
    getLocationAccess().then(setAccess);
  }, []);

  const bullet = (symbol: SymbolName, text: string) => (
    <View style={{ flexDirection: 'row', gap: 10, alignItems: 'center' }}>
      <Icon name={symbol} color={theme.accent} />
      <Mono size={13} style={{ flex: 1 }}>{text}</Mono>
    </View>
  );

  return (
    <Screen>
      <GlitchText size={26} weight="900">LE VIRUS TE SUIT</GlitchText>
      <Mono size={14}>
        Dans Contamination, tu peux être infecté dans le métro sans ouvrir l&apos;appli. Pour ça, le centre de crise
        a besoin de savoir à peu près où tu passes.
      </Mono>

      <Panel title="Ce que le jeu garde">
        {bullet('mappin.and.ellipse', 'Une zone de 50 m, jamais ta position exacte.')}
        {bullet('clock.arrow.circlepath', 'Effacée au bout de 6 heures.')}
        {bullet('eye.slash', 'Personne ne voit où tu es : la carte ne montre que des arrondissements.')}
        {bullet('battery.100', 'Pas de GPS continu : seulement tes déplacements.')}
      </Panel>

      <Panel title="Sans « Toujours »">
        <Mono size={13}>
          Tu joues en mode réduit : ration quotidienne, fabrication, et rencontres seulement quand l&apos;appli est
          ouverte.
        </Mono>
      </Panel>

      {access === 'undetermined' ? (
        <ActionButton title="Autoriser la localisation" onPress={async () => setAccess(await requestForeground())} />
      ) : access === 'foreground' && !askedAlways ? (
        <>
          <ActionButton
            title="Passer à « Toujours »"
            onPress={async () => {
              setAskedAlways(true);
              setAccess(await requestAlways());
            }}
          />
          <ActionButton title="Continuer en mode réduit" prominent={false} onPress={finishLocationPrimer} />
        </>
      ) : access ? (
        <ActionButton
          title={access === 'always' ? 'Entrer dans Paris' : 'Continuer en mode réduit'}
          onPress={finishLocationPrimer}
        />
      ) : null}
    </Screen>
  );
}
