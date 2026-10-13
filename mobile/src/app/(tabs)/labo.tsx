import { Pressable, View } from 'react-native';

import { Icon, Screen, SeasonHeader, type SymbolName } from '@/components/screen';
import { ActionButton, GlitchText, Mono, Panel } from '@/components/ui';
import { canCraft, CRAFTABLE, INGREDIENTS, ITEMS, quantity, recipeLabel, type ItemId } from '@/lib/game';
import { useGame } from '@/state/game-context';
import { useTheme } from '@/state/theme-context';

const SYMBOLS: Record<ItemId, SymbolName> = {
  tissu: 'square.stack.3d.down.forward',
  filtre: 'circle.hexagongrid',
  alcool: 'drop',
  plante: 'leaf',
  reactif: 'testtube.2',
  masque: 'facemask',
  antidote: 'syringe',
};

/** Ration quotidienne, fabrication et dépôt d'échantillons au Laboratoire mondial. */
export default function LabTab() {
  const { game, refresh, claimRation, craft, contribute, busy } = useGame();
  const theme = useTheme();
  if (!game) return null;

  if (game.player.state === 'zombie') {
    return (
      <Screen onRefresh={refresh}>
        <SeasonHeader />
        <Panel title="Le Laboratoire">
          <GlitchText size={15}>Ils cherchent un remède. Qu&apos;ils cherchent.</GlitchText>
          <Mono size={12}>
            Plus je contamine, moins ils sont nombreux à alimenter leur barre. Si 90 % de la ville tombe, nous gagnons.
          </Mono>
        </Panel>
      </Screen>
    );
  }

  return (
    <Screen onRefresh={refresh}>
      <SeasonHeader />
      <Panel title="Ration quotidienne">
        {game.player.ration_available ? (
          <>
            <Mono size={13}>Le centre de crise a déposé ta ration du jour.</Mono>
            <ActionButton title="Récupérer" disabled={busy} onPress={claimRation} />
          </>
        ) : (
          <Mono size={13} color={theme.muted}>Prochaine ration demain.</Mono>
        )}
      </Panel>

      <Panel title="Fabrication">
        {CRAFTABLE.map((item) => (
          <View key={item} style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
            <Icon name={SYMBOLS[item]} color={theme.accent} size={26} />
            <View style={{ flex: 1, gap: 4 }}>
              <Mono size={15} weight="700">{`${ITEMS[item].name}  ×${quantity(game, item)}`}</Mono>
              <Mono size={11} color={theme.muted}>{recipeLabel(item)}</Mono>
            </View>
            <ActionButton
              title="Fabriquer"
              prominent={false}
              style={{ paddingHorizontal: 12 }}
              disabled={!canCraft(game, item) || busy}
              onPress={() => craft(item)}
            />
          </View>
        ))}
      </Panel>

      <Panel title="Ingrédients — dépôt au Laboratoire">
        {INGREDIENTS.map((item) => {
          const n = quantity(game, item);
          return (
            <View key={item} style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
              <Icon name={SYMBOLS[item]} color={theme.accent} />
              <Mono size={13} style={{ flex: 1 }}>{ITEMS[item].name}</Mono>
              <Mono size={13} weight="700">×{n}</Mono>
              <Pressable
                disabled={n === 0 || busy}
                onPress={() => contribute(item, 1)}
                style={({ pressed }) => ({
                  paddingHorizontal: 10,
                  paddingVertical: 6,
                  borderRadius: 4,
                  borderWidth: 1,
                  borderColor: theme.accent,
                  opacity: n === 0 || busy ? 0.35 : pressed ? 0.6 : 1,
                })}
              >
                <Mono size={11} weight="700" color={theme.accent}>+{ITEMS[item].labPoints} pt</Mono>
              </Pressable>
            </View>
          );
        })}
        <Mono size={11} color={theme.muted}>
          Chaque échantillon rapproche Paris du remède universel. Ta contribution : {game.player.lab_contribution} pts.
        </Mono>
      </Panel>
    </Screen>
  );
}
