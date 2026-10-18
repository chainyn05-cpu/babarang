# Babarang Upsell Points Tracker

A responsive React + Vite dashboard for Babarang staff upsell tracking. Backend: Supabase Auth + Postgres with Row Level Security. Hosting: Vercel.

## Features
- Manager and staff sign-in using Supabase Auth.
- Staff directory.
- Record original amount and final amount; upsell and points are calculated automatically.
- $10 of upsell = 1 point (whole $10 increments only).
- Pending / Verified / Rejected review flow. Only Verified records count toward leaderboard and reports.
- Monthly leaderboard and Top 3 rewards: $30 / $20 / $10.
- Daily and monthly reports, search, CSV export.
- Responsive black/white/gold interface.

## 1. Create Supabase project
1. Open Supabase and create a project.
2. Open SQL Editor and run `supabase/schema.sql`.
3. In Authentication settings, keep public sign-up disabled if only managers should provision accounts.
4. In Project Settings > API, copy Project URL and the anon/publishable key. Never put the service-role key in frontend code.

## 2. Set up the first Manager and Staff profiles
The first manager profile must be inserted using the Supabase SQL Editor because no manager exists yet to use the app's manager-only policies.

1. In Supabase > Authentication > Users, create the manager user with email and password.
2. Copy that user's UUID.
3. Run this SQL, replacing the UUID and name:

```sql
insert into public.profiles (user_id, display_name, role, staff_id)
values ('MANAGER_AUTH_USER_UUID', 'Babarang Manager', 'manager', null);
```

4. Sign in to the website with the manager's email/password. Use Staff Management to create staff records.
5. For each staff member who needs login, create a user under Authentication > Users. Copy the Auth user's UUID, and the relevant Staff record UUID (from Table Editor > staff).
6. Run this SQL for each staff member:

```sql
insert into public.profiles (user_id, display_name, role, staff_id)
values ('STAFF_AUTH_USER_UUID', 'Staff Display Name', 'staff', 'STAFF_RECORD_UUID');
```

If the staff member does not need a login, they can still exist in the directory; however, a manager must record their sales if you want to track them. The current RLS allows staff to submit entries only for their own linked staff record and managers to review/update entries.

## 3. Run locally
1. Install Node.js 20 or newer.
2. Copy `.env.example` to `.env` and fill in:

```env
VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
```

3. Run:

```bash
npm install
npm run dev
```

## 4. Deploy to Vercel
1. Push this folder to a GitHub repository.
2. In Vercel, import that repository.
3. Add Environment Variables `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` with the values from Supabase.
4. Deploy. Vercel should detect Vite; build command is `npm run build`, output directory is `dist`.
5. If you change environment variables, redeploy the project.

## Important operating rules
- One invoice number can only be recorded once (unique invoice constraint).
- Upsell amount = max(final amount - original amount, 0).
- Points = floor(upsell amount / 10). Examples: $9.99 = 0 points; $30 = 3 points; $49.99 = 4 points.
- Only `verified` entries count toward monthly leaderboard and daily/monthly KPIs.
- Managers should verify against POS and net sales after refunds/discount corrections.
- Top 3 reward amounts are currently shown as a monthly reward guide; payout approval should be recorded by management outside the app until a payout ledger is added.
- Never expose a Supabase service-role key in frontend environment variables or client-side source code.


## Staff Registration Code update (additive; preserve existing data)

This update adds one-time, seven-day registration codes for existing active staff records.
It does not drop or replace `staff`, `profiles`, or `upsell_entries`.

### Required setup
1. Back up the Supabase database before changing production.
2. Apply `supabase/migrations/202610180001_staff_registration_codes.sql` in the Supabase SQL Editor. Do not rerun `supabase/schema.sql` against a live project.
3. Deploy the Edge Function from the project root:
   `supabase functions deploy staff-register`
4. Confirm the function has the standard Supabase secrets `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` set server-side. Never expose the service-role key in Vite or browser code.
5. Deploy a Vercel Preview first and test using a temporary staff record/account before production.
6. In the app, Manager opens Staff Management and clicks “បង្កើតកូដ” beside an existing active staff record. Send the displayed code privately to that staff member. It expires after 7 days and can be used once.
7. Staff use “ចុះឈ្មោះ Staff ដោយប្រើកូដ”, enter the code, their name, email, and a password of at least 8 characters. Supabase email confirmation may be required before login.

### Important security notes
- New registrations are assigned role `staff` by the server; the browser cannot select a role.
- Only a Manager profile can call `manager_create_staff_registration_code`.
- The registration-code table denies direct client access.
- Existing policies must still be reviewed to ensure staff cannot update `profiles.role` or approve entries. The existing schema's manager-only profile update and entry update policies are expected to remain in place.
- Do not expose the service-role key or commit it to GitHub.


## Simplified staff login
Staff enter their assigned name, one-time code and choose a password once. After registration, they sign in using the staff code and password; no personal Gmail is required. Manager continues to sign in using the existing Gmail. Browser session persistence is enabled on each device.
