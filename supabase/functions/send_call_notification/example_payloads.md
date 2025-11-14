Example FCM payloads for incoming calls

1) Legacy FCM HTTP (for quick tests - uses server key)
{
  "to": "DEVICE_FCM_TOKEN",
  "priority": "high",
  "data": {
    "type": "incoming_call",
    "caller_name": "Alice",
    "call_id": "call-123"
  }
}

2) FCM HTTP v1 (recommended for production using service account OAuth2)
Request body:
{
  "message": {
    "token": "DEVICE_FCM_TOKEN",
    "android": {
      "priority": "HIGH",
      "notification": {
        "title": "Incoming call",
        "body": "Alice is calling"
      }
    },
    "data": {
      "type": "incoming_call",
      "caller_name": "Alice",
      "call_id": "call-123"
    }
  }
}

Notes:
- Android: Always send high priority data messages for background delivery.
- iOS VoIP: Use APNs VoIP pushes via PushKit for true CallKit behavior.
