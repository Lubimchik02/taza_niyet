// Edge Function «push»: новое уведомление → пуш на телефоны пользователя через FCM HTTP v1.
// Секреты (supabase secrets set …): FCM_SERVICE_ACCOUNT — JSON служебного аккаунта Firebase.
// SUPABASE_URL и SUPABASE_SERVICE_ROLE_KEY Supabase подставляет сам.
import { createClient } from "npm:@supabase/supabase-js@2";

type Row = { id: string; user_id: string; kind: string; args: Record<string, unknown>; route: string | null };

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "{}");

// Какой переключатель из настроек отвечает за тип уведомления.
const TOGGLE: Record<string, string> = {
  hours_approved: "n.hours", penalty: "n.hours", shift_rejected: "n.hours",
  chat: "n.chats", friend_request: "n.friends", friend_accepted: "n.friends",
  org_approved: "n.quests", org_rejected: "n.quests", waitlist_promoted: "n.shifts", shift_report: "n.shifts",
};
// Важные о смене — даже в тихие часы.
const URGENT = new Set(["waitlist_promoted"]);

const T: Record<string, Record<string, (a: Record<string, unknown>) => string>> = {
  ru: {
    hours_approved: (a) => `Часы подтверждены: +${a.tz} Tz · «${a.quest}»`,
    penalty: (a) => `Списано ${a.tz} Tz: ${a.note ?? ""}`,
    shift_rejected: (a) => `Координатор вернул отчёт по «${a.quest}»`,
    chat: (a) => `${a.name}: ${a.text}`,
    friend_request: (a) => `${a.name} хочет добавить вас в друзья`,
    friend_accepted: (a) => `${a.name} теперь в друзьях`,
    org_approved: (a) => `${a.org} одобрила заявку — можно записываться на квесты`,
    org_rejected: (a) => `${a.org} сейчас не принимает новых волонтёров`,
    waitlist_promoted: (a) => `Место освободилось — вы записаны на «${a.quest}»`,
    shift_report: (a) => `Отчёт смены «${a.quest}» ждёт проверки`,
  },
  kk: {
    hours_approved: (a) => `Сағаттар расталды: +${a.tz} Tz · «${a.quest}»`,
    penalty: (a) => `${a.tz} Tz алынды: ${a.note ?? ""}`,
    shift_rejected: (a) => `Үйлестіруші «${a.quest}» есебін қайтарды`,
    chat: (a) => `${a.name}: ${a.text}`,
    friend_request: (a) => `${a.name} сізді досқа қосқысы келеді`,
    friend_accepted: (a) => `${a.name} енді досыңыз`,
    org_approved: (a) => `${a.org} өтінімді мақұлдады — квесттерге жазылуға болады`,
    org_rejected: (a) => `${a.org} қазір жаңа еріктілерді қабылдамайды`,
    waitlist_promoted: (a) => `Орын босады — сіз «${a.quest}» квесіне жазылдыңыз`,
    shift_report: (a) => `«${a.quest}» ауысым есебі тексеруді күтуде`,
  },
  en: {
    hours_approved: (a) => `Hours confirmed: +${a.tz} Tz · “${a.quest}”`,
    penalty: (a) => `${a.tz} Tz deducted: ${a.note ?? ""}`,
    shift_rejected: (a) => `The coordinator returned the report for “${a.quest}”`,
    chat: (a) => `${a.name}: ${a.text}`,
    friend_request: (a) => `${a.name} wants to add you as a friend`,
    friend_accepted: (a) => `${a.name} is now your friend`,
    org_approved: (a) => `${a.org} approved your request — you can sign up for quests`,
    org_rejected: (a) => `${a.org} isn’t taking new volunteers right now`,
    waitlist_promoted: (a) => `A spot opened up — you’re signed up for “${a.quest}”`,
    shift_report: (a) => `Shift report for “${a.quest}” is waiting for review`,
  },
};

// Казахстан: UTC+5. Тихие часы 22:00–08:00.
const isQuiet = (d = new Date()) => {
  const h = (d.getUTCHours() + 5) % 24;
  return h >= 22 || h < 8;
};

let cached: { token: string; exp: number } | null = null;
async function accessToken(): Promise<string> {
  if (cached && cached.exp > Date.now() + 60_000) return cached.token;
  const now = Math.floor(Date.now() / 1000);
  const b64 = (o: unknown) => btoa(typeof o === "string" ? o : JSON.stringify(o)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
  const head = b64({ alg: "RS256", typ: "JWT" });
  const body = b64({ iss: sa.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging", aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600 });
  const pem = (sa.private_key as string).replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  const key = await crypto.subtle.importKey("pkcs8", Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${head}.${body}`)));
  const jwt = `${head}.${body}.${b64(String.fromCharCode(...sig))}`;
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
  });
  const j = await r.json();
  cached = { token: j.access_token, exp: Date.now() + j.expires_in * 1000 };
  return cached.token;
}

Deno.serve(async (req) => {
  const { record } = (await req.json()) as { record: Row };
  if (!record?.user_id) return new Response("skip", { status: 200 });

  const { data: p } = await db.from("profiles").select("locale, notify").eq("id", record.user_id).single();
  const prefs = (p?.notify ?? {}) as Record<string, boolean>;
  const toggle = TOGGLE[record.kind];
  if (toggle && prefs[toggle] === false) return new Response("muted", { status: 200 });
  if (prefs["n.quiet"] !== false && isQuiet() && !URGENT.has(record.kind)) return new Response("quiet", { status: 200 });

  const text = (T[p?.locale ?? "ru"] ?? T.ru)[record.kind]?.(record.args ?? {});
  if (!text) return new Response("no template", { status: 200 });

  const { data: tokens } = await db.from("push_tokens").select("token").eq("user_id", record.user_id);
  if (!tokens?.length) return new Response("no devices", { status: 200 });

  const bearer = await accessToken();
  for (const { token } of tokens) {
    const r = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: "POST",
      headers: { authorization: `Bearer ${bearer}`, "content-type": "application/json" },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: "Taza Niyet", body: text.slice(0, 180) },
          data: { route: record.route ?? "/home", id: record.id },
          android: { priority: "high", notification: { channel_id: record.kind === "chat" ? "chats" : "shifts" } },
          apns: { payload: { aps: { sound: "default", "thread-id": record.kind } } },
        },
      }),
    });
    // Телефон удалил приложение или сменил токен — забываем устройство.
    if (r.status === 404 || r.status === 400) {
      const err = await r.json().catch(() => ({}));
      if (JSON.stringify(err).includes("UNREGISTERED") || JSON.stringify(err).includes("INVALID_ARGUMENT")) {
        await db.from("push_tokens").delete().eq("token", token);
      }
    }
  }
  return new Response("sent", { status: 200 });
});
