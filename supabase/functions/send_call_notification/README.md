Deployable Supabase Edge Function to send FCM data messages for incoming calls.

Environment
- FCM_LEGACY_KEY: your Firebase legacy server key (for quick tests). For production use FCM HTTP v1 with service account.

Request
POST JSON: { "token": "DEVICE_FCM_TOKEN", "caller_name": "Alice", "call_id": "call-123" }

Example (curl)

curl -X POST 'https://<YOUR-SUPABASE-URL>/functions/v1/send_call_notification' \
  -H 'Authorization: Bearer <SERVICE_ROLE_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{ "token": "DEVICE_FCM_TOKEN", "caller_name": "Alice", "call_id": "call-123" }'

Notes
- For production, configure FCM HTTP v1 using OAuth2 and a service account. Do not commit server keys to source control.
- This function sends a high-priority data message plus optional notification payload. Android will receive the data in background and the app's background handler should display a full-screen incoming-call notification.
