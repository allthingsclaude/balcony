// Balcony Cloud Relay - Message Relay Function (Phase 2)
// Stores encrypted messages for forwarding between paired devices.

import { serve } from "https://deno.land/std/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js";

serve(async (req: Request) => {
    // TODO: Implement message relay
    // 1. Authenticate request
    // 2. Validate pairing exists
    // 3. Store encrypted message
    // 4. Notify recipient via Realtime channel
    return new Response(JSON.stringify({ status: "not_implemented" }), {
        headers: { "Content-Type": "application/json" },
        status: 501,
    });
});
