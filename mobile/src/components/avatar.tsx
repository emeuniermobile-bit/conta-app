import { View } from 'react-native';

import type { Avatar, PlayerState } from '@/lib/game';

/** Silhouette avec masque à gaz ; se transforme quand le joueur devient zombie. */
export function AvatarView({ avatar, state = 'survivor', size = 96 }: { avatar: Avatar; state?: PlayerState; size?: number }) {
  const zombie = state === 'zombie';
  const color = zombie ? '#7A8F5A' : avatar.color;
  const s = (k: number) => size * k;
  const eye = { width: s(0.15), height: s(0.15), borderRadius: s(0.075), backgroundColor: '#000000D9', borderWidth: s(0.02), borderColor: color };

  return (
    <View
      style={{
        width: size,
        height: size,
        borderRadius: size / 2,
        overflow: 'hidden',
        borderWidth: 2,
        borderColor: zombie ? '#FF1E1E' : `${color}B3`,
        backgroundColor: '#0D1418',
        alignItems: 'center',
        transform: [{ rotate: zombie ? '-6deg' : '0deg' }],
      }}
    >
      {/* Épaules */}
      <View style={{ position: 'absolute', bottom: -s(0.1), width: s(0.95), height: s(0.5), borderRadius: s(0.25), backgroundColor: '#1B262E' }} />
      {/* Tête */}
      <View
        style={{
          position: 'absolute',
          top: s(0.11),
          width: s(0.62),
          height: s(0.62),
          borderRadius: s(0.31),
          backgroundColor: zombie ? '#3E4A33' : '#26343D',
        }}
      />
      {/* Masque */}
      <View
        style={{
          position: 'absolute',
          top: s(0.24),
          alignItems: 'center',
          gap: s(0.02),
          opacity: zombie ? 0.35 : 1,
          transform: [{ rotate: zombie ? '18deg' : '0deg' }],
        }}
      >
        {avatar.mask === 'visor' ? (
          <View style={{ width: s(0.42), height: s(0.14), borderRadius: s(0.07), backgroundColor: '#000000D9', borderWidth: s(0.02), borderColor: color }} />
        ) : (
          <View style={{ flexDirection: 'row', gap: s(0.08) }}>
            <View style={eye} />
            <View style={eye} />
          </View>
        )}
        {avatar.mask === 'filter' ? (
          <View style={{ flexDirection: 'row', gap: s(0.12) }}>
            <View style={{ width: s(0.14), height: s(0.14), borderRadius: s(0.07), backgroundColor: color }} />
            <View style={{ width: s(0.14), height: s(0.14), borderRadius: s(0.07), backgroundColor: color }} />
          </View>
        ) : avatar.mask === 'plague' ? (
          <View
            style={{
              width: 0,
              height: 0,
              borderLeftWidth: s(0.08),
              borderRightWidth: s(0.08),
              borderTopWidth: s(0.2),
              borderLeftColor: 'transparent',
              borderRightColor: 'transparent',
              borderTopColor: color,
            }}
          />
        ) : (
          <View style={{ width: s(0.18), height: s(0.18), borderRadius: s(0.09), backgroundColor: color, borderWidth: s(0.015), borderColor: '#00000066' }} />
        )}
      </View>
      {zombie ? (
        // Masque arraché, yeux rouges.
        <View style={{ position: 'absolute', top: s(0.3), flexDirection: 'row', gap: s(0.14) }}>
          <View style={{ width: s(0.07), height: s(0.07), borderRadius: s(0.035), backgroundColor: '#FF1E1E' }} />
          <View style={{ width: s(0.07), height: s(0.07), borderRadius: s(0.035), backgroundColor: '#FF1E1E' }} />
        </View>
      ) : null}
    </View>
  );
}
