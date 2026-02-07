// Balcony Cloud Relay - Push Notification Function (Phase 2)
// Dispatches FCM push notifications when user is away.

import { serve } from "https://deno.land/std/http/server.ts";

serve(async (req: Request) => {
    // TODO: Implement push notification dispatch
    // 1. Authenticate request
    // 2. Look up device FCM token
    // 3. Send notification via FCM HTTP v1 API
    return new Response(JSON.stringify({ status: "not_implemented" }), {
        headers: { "Content-Type": "application/json" },
        status: 501,
    });
});
