// Envoie les notifications en attente (table public.notifications) via le
// service de notifications d'Expo, qui relaie vers Apple (APNs) et Google (FCM).
// Appelée chaque minute par pg_cron (voir migration *_schedule.sql).
//
// Secret facultatif (supabase secrets set ...) :
//   EXPO_ACCESS_TOKEN  si la « sécurité renforcée des notifications » est activée sur expo.dev
import { createClient } from "jsr:@supabase/supabase-js@2";

const BATCH_SIZE = 500;
const EXPO_PUSH_URL = "https://exp.host/--/api/v2/push/send";
const EXPO_CHUNK = 100; // maximum de messages par requête Expo

type Pending = {
  id: number;
  kind: string;
  title: string;
  body: string;
  push_token: string | null;
  state: "survivor" | "incubating" | "zombie";
};

type Ticket = { status: "ok"; id: string } | {
  status: "error";
  message: string;
  details?: { error?: string };
};

const env = (name: string) => {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`variable d'environnement manquante : ${name}`);
  return value;
};

const supabase = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
  auth: { persistSession: false },
});

// Les alertes de contamination doivent percer le mode concentration.
const TIME_SENSITIVE = new Set(["infected", "incubation_warning", "transformed"]);

function toMessage(n: Pending) {
  return {
    to: n.push_token,
    title: n.title,
    body: n.body,
    sound: "default",
    priority: "high",
    interruptionLevel: TIME_SENSITIVE.has(n.kind) ? "time-sensitive" : "active",
    channelId: "alerts",
    data: { kind: n.kind },
  };
}

async function sendChunk(chunk: Pending[]): Promise<(string | null)[]> {
  const headers: Record<string, string> = {
    "content-type": "application/json",
    accept: "application/json",
  };
  const accessToken = Deno.env.get("EXPO_ACCESS_TOKEN");
  if (accessToken) headers.authorization = `Bearer ${accessToken}`;

  const response = await fetch(EXPO_PUSH_URL, {
    method: "POST",
    headers,
    body: JSON.stringify(chunk.map(toMessage)),
  });
  if (!response.ok) {
    const failure = `http_${response.status}`;
    return chunk.map(() => failure);
  }
  const { data } = (await response.json()) as { data: Ticket[] };
  return chunk.map((_n, i) => {
    const ticket = data?.[i];
    if (!ticket) return "no_ticket";
    if (ticket.status === "ok") return null;
    return ticket.details?.error ?? ticket.message;
  });
}

Deno.serve(async (req) => {
  const auth = req.headers.get("authorization") ?? "";
  if (auth !== `Bearer ${env("SUPABASE_SERVICE_ROLE_KEY")}`) {
    return new Response("forbidden", { status: 403 });
  }

  // Les lignes réservées sont déjà marquées envoyées ; seul l'échec est noté.
  const { data, error } = await supabase.rpc("claim_notifications", { p_limit: BATCH_SIZE });
  if (error) return Response.json({ error: error.message }, { status: 500 });

  const pending = (data ?? []) as Pending[];
  const withToken = pending.filter((n) => n.push_token);
  let failed = 0;

  for (let i = 0; i < withToken.length; i += EXPO_CHUNK) {
    const chunk = withToken.slice(i, i + EXPO_CHUNK);
    let results: (string | null)[];
    try {
      results = await sendChunk(chunk);
    } catch (e) {
      const failure = e instanceof Error ? e.message : String(e);
      results = chunk.map(() => failure);
    }
    await Promise.all(chunk.map(async (n, j) => {
      const failure = results[j];
      if (!failure) return;
      failed++;
      await supabase.from("notifications").update({ error: failure }).eq("id", n.id);
      // Appli désinstallée ou notifications refusées : on oublie le jeton.
      if (failure === "DeviceNotRegistered") {
        await supabase.from("profiles").update({ push_token: null }).eq("push_token", n.push_token);
      }
    }));
  }

  return Response.json({ processed: pending.length, sent: withToken.length - failed, failed });
});
