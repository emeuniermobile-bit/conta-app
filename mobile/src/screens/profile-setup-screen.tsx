import { useState } from 'react';
import { Pressable, TextInput, View } from 'react-native';

import { AvatarView } from '@/components/avatar';
import { Screen } from '@/components/screen';
import { ActionButton, GlitchText, Mono, Panel } from '@/components/ui';
import { AVATAR_COLORS, DEFAULT_AVATAR, isValidDisplayName, MASK_STYLES, type Avatar } from '@/lib/game';
import { withAlpha } from '@/lib/theme';
import { useGame } from '@/state/game-context';
import { useTheme } from '@/state/theme-context';

export function ProfileSetupScreen() {
  const { setupProfile, busy } = useGame();
  const theme = useTheme();
  const [name, setName] = useState('');
  const [avatar, setAvatar] = useState<Avatar>(DEFAULT_AVATAR);

  return (
    <Screen>
      <GlitchText size={24} weight="900">FICHE SURVIVANT</GlitchText>
      <View style={{ alignItems: 'center' }}>
        <AvatarView avatar={avatar} size={140} />
      </View>
      <Panel title="Nom de code">
        <TextInput
          value={name}
          onChangeText={setName}
          placeholder="2 à 24 caractères"
          placeholderTextColor={theme.muted}
          autoCapitalize="none"
          autoCorrect={false}
          maxLength={24}
          style={{ fontFamily: theme.mono, fontSize: 20, fontWeight: '700', color: theme.text }}
        />
      </Panel>
      <Panel title="Masque">
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
          {MASK_STYLES.map((m) => (
            <Pressable
              key={m.id}
              onPress={() => setAvatar({ ...avatar, mask: m.id })}
              style={{
                paddingHorizontal: 12,
                paddingVertical: 8,
                borderRadius: 4,
                borderWidth: 1,
                borderColor: theme.accent,
                backgroundColor: avatar.mask === m.id ? theme.accent : withAlpha(theme.accent, 0),
              }}
            >
              <Mono size={12} weight="600" color={avatar.mask === m.id ? theme.background : theme.accent}>
                {m.label}
              </Mono>
            </Pressable>
          ))}
        </View>
        <View style={{ flexDirection: 'row', gap: 12 }}>
          {AVATAR_COLORS.map((hex) => (
            <Pressable
              key={hex}
              accessibilityLabel={`Couleur ${hex}`}
              onPress={() => setAvatar({ ...avatar, color: hex })}
              style={{
                width: 32,
                height: 32,
                borderRadius: 16,
                backgroundColor: hex,
                borderWidth: avatar.color === hex ? 3 : 0,
                borderColor: theme.text,
              }}
            />
          ))}
        </View>
      </Panel>
      <ActionButton
        title="Rejoindre Paris"
        disabled={!isValidDisplayName(name) || busy}
        onPress={() => setupProfile(name, avatar)}
      />
    </Screen>
  );
}
