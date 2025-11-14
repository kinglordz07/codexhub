import { serve } from "https://deno.land/std@0.201.0/http/server.ts";

const FCM_LEGACY_KEY = Deno.env.get("FCM_LEGACY_KEY") || "";
// For production prefer OAuth2 with service account and HTTP v1 API

serve(async (req) => {
  try {
    if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

    const body = await req.json();
    // expected body: { token: string, caller_name: string, call_id: string }
    const token = body.token;
    const caller_name = body.caller_name || "Unknown";
    const call_id = body.call_id || Date.now().toString();

    if (!token) return new Response("Missing token", { status: 400 });

    const payload = {
      to: token,
      priority: "high",
      data: {
        type: "incoming_call",
        caller_name,
        call_id,
      },
      notification: {
        title: "Incoming call",
        body: `${caller_name} is calling`,
      },
    };

    const resp = await fetch("https://fcm.googleapis.com/fcm/send", {
      method: "POST",
      headers: {
        "Authorization": `key=${FCM_LEGACY_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    const text = await resp.text();
    return new Response(text, { status: resp.status });
  } catch (err) {
    console.error("send_call_notification error", err);
    return new Response(String(err), { status: 500 });
  }
});
