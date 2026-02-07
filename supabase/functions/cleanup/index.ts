// Balcony Cloud Relay - Cleanup Function (Phase 2)
// Deletes expired relay messages. Intended to run on a cron schedule.

import { serve } from "https://deno.land/std/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js";

serve(async (req: Request) => {
    // TODO: Implement cleanup
    // 1. Delete relay_messages where expires_at < NOW()
    // 2. Return count of deleted messages
    return new Response(JSON.stringify({ status: "not_implemented" }), {
        headers: { "Content-Type": "application/json" },
        status: 501,
    });
});
