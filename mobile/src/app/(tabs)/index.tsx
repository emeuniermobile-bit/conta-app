import { useEffect, useState } from 'react';
import { Linking, View } from 'react-native';

import { AvatarView } from '@/components/avatar';
import { Icon, Screen, SeasonHeader } from '@/components/screen';
import { useNow } from '@/components/use-tick';
import { ActionButton, GlitchText, Mono, Panel } from '@/components/ui';
import { formatCountdown, parisTime, quantity, type Player, type PlayerState } from '@/lib/game';
import { getLocationAccess } from '@/lib/location';
import { useGame } from '@/state/game-context';
import { useTheme } from '@/state/theme-context';

const STATE_LABEL: Record<PlayerState, string> = {
  survivor: 'SURVIVANT',
  incubating: 'INFECTÉ — INCUBATION',
  zombie: 'ZOMBIE',
};

export default function StatusTab() {
  const { game, encounters, refresh, signOut } = useGame();
  const theme = useTheme();
  const [background, setBackground] = useState(true);

  useEffect(() => {
    getLocationAccess().then((a) => setBackground(a === 'always'));
  }, []);

  if (!game) return null;
  const { player } = game;

  return (
    <Screen onRefresh={refresh}>
      <SeasonHeader />
      <View style={{ flexDirection: 'row', gap: 16, alignItems: 'center' }}>
        <AvatarView avatar={player.avatar} state={player.state} size={72} />
        <View style={{ gap: 4, flex: 1 }}>
          <GlitchText size={22} weight="700">{player.display_name ?? '—'}</GlitchText>
          <Mono size={12} weight="700" color={player.state === 'survivor' ? theme.safe : theme.danger} style={{ letterSpacing: 2 }}>
            {STATE_LABEL[player.state]}
          </Mono>
        </View>
      </View>

      {player.state === 'survivor' ? <SurvivorPanel /> : null}
      {player.state === 'incubating' ? <IncubationPanel player={player} /> : null}
      {player.state === 'zombie' ? <ZombiePanel player={player} /> : null}

      {!background ? (
        <Panel title="Mode réduit">
          <Mono size={12}>
            Sans la localisation « Toujours », tes rencontres ne comptent que quand l&apos;appli est ouverte.
          </Mono>
          <ActionButton title="Ouvrir les réglages" prominent={false} onPress={() => Linking.openSettings()} />
        </Panel>
      ) : null}

      {encounters.length > 0 ? (
        <Panel title="Journal des rencontres">
          {encounters.slice(0, 8).map((e) => (
            <View key={e.occurred_at} style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
              <Icon
                name={e.infected ? 'exclamationmark.triangle.fill' : 'checkmark.shield'}
                color={e.infected ? theme.danger : theme.safe}
                size={16}
              />
              <Mono size={13} style={{ flex: 1 }}>{e.place}</Mono>
              <Mono size={12} color={theme.muted}>{parisTime(e.occurred_at)}</Mono>
            </View>
          ))}
        </Panel>
      ) : null}

      <ActionButton title="Se déconnecter" prominent={false} onPress={signOut} style={{ marginTop: 24 }} />
    </Screen>
  );
}

function SurvivorPanel() {
  const { game, wearMask, busy } = useGame();
  const theme = useTheme();
  const maskUntil = game?.player.mask_until;
  return (
    <Panel title="État sanitaire">
      <Mono size={15}>Aucune infection détectée.</Mono>
      {maskUntil ? (
        <Mono size={13} color={theme.accent}>Masque actif jusqu&apos;à {parisTime(maskUntil)}</Mono>
      ) : quantity(game, 'masque') > 0 ? (
        <ActionButton title="Mettre un masque" prominent={false} disabled={busy} onPress={wearMask} />
      ) : (
        <Mono size={12} color={theme.muted}>Aucun masque. Fabrique-en un au Labo.</Mono>
      )}
    </Panel>
  );
}

function IncubationPanel({ player }: { player: Player }) {
  const { game, injectAntidote, busy } = useGame();
  const theme = useTheme();
  const now = useNow(1000);
  const left = player.transform_at ? Date.parse(player.transform_at) - now : 0;
  return (
    <Panel title="Infection détectée">
      {player.infected_place && player.infected_at ? (
        <GlitchText size={15}>{`${player.infected_place}, ${parisTime(player.infected_at)}`}</GlitchText>
      ) : null}
      <View style={{ gap: 4 }}>
        <Mono size={11} weight="600" color={theme.muted}>TRANSFORMATION DANS</Mono>
        <Mono size={44} weight="900" color={theme.danger}>{formatCountdown(left)}</Mono>
      </View>
      {quantity(game, 'antidote') > 0 ? (
        <ActionButton title="Injecter l'antidote" disabled={busy} onPress={injectAntidote} />
      ) : (
        <Mono size={12}>Fabrique un antidote au Labo avant la fin du compte à rebours.</Mono>
      )}
    </Panel>
  );
}

function ZombiePanel({ player }: { player: Player }) {
  const theme = useTheme();
  return (
    <Panel title="Instinct">
      <GlitchText size={15}>Ils sont partout. Je les sens passer.</GlitchText>
      <View style={{ flexDirection: 'row', alignItems: 'baseline', gap: 8 }}>
        <Mono size={44} weight="900" color={theme.accent}>{player.contaminations}</Mono>
        <Mono size={12} color={theme.muted}>contaminations cette saison</Mono>
      </View>
      <Mono size={12}>
        Chaque survivant qui reste près de moi plus de 2 minutes peut tomber. Je n&apos;ai qu&apos;à vivre ma vie.
      </Mono>
    </Panel>
  );
}
