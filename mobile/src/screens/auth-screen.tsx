import { useState } from 'react';
import { TextInput, View } from 'react-native';

import { ActionButton, GlitchText, Mono, Panel } from '@/components/ui';
import { Screen } from '@/components/screen';
import { isValidPhone, normalizePhone } from '@/lib/game';
import { useGame } from '@/state/game-context';
import { useTheme } from '@/state/theme-context';

/** Inscription et connexion par numéro de téléphone (un compte par numéro). */
export function AuthScreen() {
  const { sendCode, verifyCode, busy } = useGame();
  const theme = useTheme();
  const [phone, setPhone] = useState('');
  const [code, setCode] = useState('');
  const [codeSent, setCodeSent] = useState(false);
  const e164 = normalizePhone(phone);
  const input = { fontFamily: theme.mono, color: theme.text, fontWeight: '700' as const, paddingVertical: 4 };

  return (
    <Screen>
      <View style={{ height: 60 }} />
      <View style={{ gap: 8 }}>
        <Mono size={11} weight="600" color={theme.muted} style={{ letterSpacing: 3 }}>
          CENTRE DE CRISE — PARIS
        </Mono>
        <GlitchText size={34} weight="900">CONTAMINATION</GlitchText>
        <Mono size={14} color={theme.text}>
          Une épidémie se propage dans la ville quand les gens se croisent. Tu commences survivant.
        </Mono>
      </View>

      <Panel title={codeSent ? 'Code reçu par SMS' : 'Identification'}>
        {codeSent ? (
          <>
            <TextInput
              value={code}
              onChangeText={setCode}
              placeholder="123456"
              placeholderTextColor={theme.muted}
              keyboardType="number-pad"
              textContentType="oneTimeCode"
              autoComplete="sms-otp"
              maxLength={6}
              style={[input, { fontSize: 28 }]}
            />
            <ActionButton
              title="Entrer"
              disabled={code.length < 6 || busy}
              onPress={() => verifyCode(e164, code)}
            />
            <ActionButton
              title="Changer de numéro"
              prominent={false}
              onPress={() => {
                setCodeSent(false);
                setCode('');
              }}
            />
          </>
        ) : (
          <>
            <TextInput
              value={phone}
              onChangeText={setPhone}
              placeholder="06 12 34 56 78"
              placeholderTextColor={theme.muted}
              keyboardType="phone-pad"
              textContentType="telephoneNumber"
              autoComplete="tel"
              style={[input, { fontSize: 24 }]}
            />
            <ActionButton
              title="Recevoir un code"
              disabled={!isValidPhone(e164) || busy}
              onPress={async () => setCodeSent(await sendCode(e164))}
            />
          </>
        )}
      </Panel>
      <Mono size={11} color={theme.muted}>
        Un compte par numéro de téléphone. Ton numéro n&apos;est jamais montré aux autres joueurs.
      </Mono>
    </Screen>
  );
}
