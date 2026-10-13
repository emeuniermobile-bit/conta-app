// Envoie les notifications en attente (table public.notifications) via APNs.
// Appelée chaque minute par pg_cron (voir migration *_schedule.sql).
//
// Secrets (supabase secrets set ...) :
//   APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID,
//   APNS_PRIVATE_KEY  (contenu du fichier .p8, BEGIN/END compris)
import { createClient } from "jsr:@supabase/supabase-js@2";

const BATCH_SIZE = 200;

type Pending = {
  id: number;
  kind: string;
  title: string;
  body: string;
  apns_token: string | null;
  apns_sandbox: boolean;
  state: "survivor" | "incubating" | "zombie";
};

const env = (name: string) => {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`variable d'environnement manquante : ${name}`);
  return value;
};

const supabase = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
  auth: { persistSession: false },
});

// --- Jeton d'authentification APNs (ES256, valable 1 h, renouvelé toutes les 50 min) ---

let cachedJwt: { token: string; issuedAt: number } | null = null;

const base64url = (data: ArrayBuffer | Uint8Array | string) => {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

async function apnsJwt(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && now - cachedJwt.issuedAt < 50 * 60) return cachedJwt.token;

  const pem = env("APNS_PRIVATE_KEY").replace(/\\n/g, "\n");
  const der = Uint8Array.from(
    atob(pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "")),
    (c) => c.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const header = base64url(JSON.stringify({ alg: "ES256", kid: env("APNS_KEY_ID") }));
  const claims = base64url(JSON.stringify({ iss: env("APNS_TEAM_ID"), iat: now }));
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const token = `${header}.${claims}.${base64url(signature)}`;
  cachedJwt = { token, issuedAt: now };
  return token;
}

// --- Envoi ---

// Les alertes de contamination doivent percer le mode concentration.
const TIME_SENSITIVE = new Set(["infected", "incubation_warning", "transformed"]);

async function send(n: Pending): Promise<string | null> {
  if (!n.apns_token) return "no_token";

  const host = n.apns_sandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const response = await fetch(`https://${host}/3/device/${n.apns_token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await apnsJwt()}`,
      "apns-topic": env("APNS_BUNDLE_ID"),
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-collapse-id": `${n.kind}-${n.id}`,
    },
    body: JSON.stringify({
      aps: {
        alert: { title: n.title, body: n.body },
        sound: n.state === "zombie" ? "zombie.caf" : "alert.caf",
        "interruption-level": TIME_SENSITIVE.has(n.kind) ? "time-sensitive" : "active",
        "thread-id": n.kind,
      },
      kind: n.kind,
    }),
  });
  if (response.ok) return null;

  const reason = (await response.json().catch(() => ({})))?.reason ?? `http_${response.status}`;
  // Jeton périmé (appli supprimée, réinstallée...) : on l'oublie.
  if (response.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered") {
    await supabase.from("profiles").update({ apns_token: null }).eq("apns_token", n.apns_token);
  }
  return reason;
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
  const results = await Promise.all(pending.map(async (n) => {
    let failure: string | null;
    try {
      failure = await send(n);
    } catch (e) {
      failure = e instanceof Error ? e.message : String(e);
    }
    if (failure) await supabase.from("notifications").update({ error: failure }).eq("id", n.id);
    return failure;
  }));

  return Response.json({
    processed: results.length,
    failed: results.filter((r) => r !== null && r !== "no_token").length,
  });
});
