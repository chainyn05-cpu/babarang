import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

async function hashCode(code: string) {
  const normalized = code.toUpperCase().replace(/-/g, "").trim();
  const bytes = new TextEncoder().encode(normalized);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map(b => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
  const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) return json(500, { error: "Server configuration missing" });

  let body: { code?: string; display_name?: string; password?: string };
  try { body = await req.json(); } catch { return json(400, { error: "Invalid request body" }); }

  const code = (body.code || "").trim().toUpperCase();
  const displayName = (body.display_name || "").trim();
  const password = body.password || "";
  if (!/^BAB-[A-F0-9]{10}$/.test(code)) return json(400, { error: "កូដមិនត្រឹមត្រូវទេ។" });
  if (displayName.length < 2 || displayName.length > 100) return json(400, { error: "សូមបញ្ចូលឈ្មោះឱ្យបានត្រឹមត្រូវ។" });
  if (password.length < 8) return json(400, { error: "Password ត្រូវមានយ៉ាងតិច 8 តួអក្សរ។" });

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { autoRefreshToken: false, persistSession: false } });
  const codeHash = await hashCode(code);
  const { data: codeRow, error: codeError } = await admin
    .from("staff_registration_codes")
    .select("id,staff_id,expires_at,used_at")
    .eq("code_hash", codeHash)
    .maybeSingle();

  if (codeError) return json(500, { error: "មិនអាចពិនិត្យកូដបានទេ។ សូមឱ្យ Manager ពិនិត្យ Supabase។" });
  if (!codeRow || codeRow.used_at || new Date(codeRow.expires_at).getTime() < Date.now()) {
    return json(400, { error: "កូដមិនត្រឹមត្រូវ ផុតកំណត់ ឬត្រូវបានប្រើរួចហើយ។" });
  }

  const { data: staffRow, error: staffError } = await admin.from("staff").select("id,full_name,active").eq("id", codeRow.staff_id).maybeSingle();
  if (staffError || !staffRow || !staffRow.active) return json(400, { error: "បុគ្គលិកនេះមិនសកម្មទេ។ សូមទាក់ទង Manager។" });
  if (staffRow.full_name.trim().toLowerCase() !== displayName.toLowerCase()) return json(400, { error: "ឈ្មោះមិនត្រូវនឹងឈ្មោះដែល Manager បានកំណត់សម្រាប់កូដនេះទេ។" });

  const email = `staff-${code.replace(/[^A-Z0-9]/g, "")}@babarang-staff.com`.toLowerCase();
  const { data: existing } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
  if (existing?.users?.some(u => (u.email || "").toLowerCase() === email)) return json(409, { error: "កូដនេះបានចុះឈ្មោះរួចហើយ។ សូមចូលដោយប្រើកូដ និង Password។" });

  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email, password, email_confirm: true,
    user_metadata: { display_name: displayName, staff_code: code }
  });
  if (createError || !created.user) return json(400, { error: createError?.message || "មិនអាចបង្កើតគណនីបានទេ។" });

  // Claim the one-time code. Conditional update prevents two registrations from consuming it.
  const { data: claimed, error: claimError } = await admin
    .from("staff_registration_codes")
    .update({ used_by: created.user.id, used_at: new Date().toISOString() })
    .eq("id", codeRow.id).is("used_at", null).gt("expires_at", new Date().toISOString())
    .select("id").maybeSingle();

  if (claimError || !claimed) {
    await admin.auth.admin.deleteUser(created.user.id);
    return json(409, { error: "កូដនេះត្រូវបានប្រើ ឬផុតកំណត់ហើយ។ សូមស្នើកូដថ្មីពី Manager។" });
  }

  const { error: profileError } = await admin.from("profiles").insert({
    user_id: created.user.id,
    display_name: displayName,
    role: "staff",
    staff_id: staffRow.id
  });

  if (profileError) {
    await admin.from("staff_registration_codes").update({ used_by: null, used_at: null }).eq("id", codeRow.id);
    await admin.auth.admin.deleteUser(created.user.id);
    return json(500, { error: "គណនីមិនអាចភ្ជាប់ទៅ Staff Profile បានទេ។ សូមឱ្យ Manager ពិនិត្យ Database។" });
  }

  return json(200, { ok: true, message: "គណនីត្រូវបានបង្កើត។ ឥឡូវអាចចូលដោយប្រើកូដបុគ្គលិក និង Password បាន។" });
});
