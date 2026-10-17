# Babarang Upsell Points Tracker

A responsive React + Vite dashboard for Babarang staff upsell tracking. Backend: Supabase Auth + Postgres with Row Level Security. Hosting: Vercel.

## Features
- Manager and staff sign-in using Supabase Auth.
- Staff directory with staff photo upload (JPG, PNG, WebP; max 5 MB). Photos are stored in Supabase Storage and shown in staff list and Top 3 leaderboard.
- Record original amount and final amount; upsell and points are calculated automatically.
- $10 of upsell = 1 point (whole $10 increments only).
- Pending / Verified / Rejected review flow. Only Verified records count toward leaderboard and reports.
- Monthly leaderboard and Top 3 rewards: $30 / $20 / $10.
- Daily and monthly reports, search, CSV export.
- Responsive black/white/gold interface.

## 1. Create Supabase project
1. Open Supabase and create a project.
2. Open SQL Editor and run `supabase/schema.sql`. This creates the `staff-photos` public-read bucket and manager-only upload/update/delete policies. Public-read means anyone with a photo URL can view the photo; do not upload sensitive images.
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
5. In Staff Management, choose a staff photo while adding each staff member. Supported formats: JPG, PNG, WebP, maximum 5 MB. Existing projects can run the updated `supabase/schema.sql` again; it adds the `photo_url` column if missing.
6. For each staff member who needs login, create a user under Authentication > Users. Copy the Auth user's UUID, and the relevant Staff record UUID (from Table Editor > staff).
7. Run this SQL for each staff member:

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


## Staff self-service profile and photo upload

After deploying this version, run `supabase/staff-photo-self-service.sql` in Supabase SQL Editor. Each staff member must have a Supabase Auth user and a row in `public.profiles` with `role = 'staff'` and `staff_id` set to their matching row in `public.staff`. Staff can then sign in, open **My Profile**, view their own performance, and upload their own JPG/PNG/WebP photo (max 5 MB). Staff can only update the photo field on their linked staff record through the app; the policy limits uploads to their own staff-id folder.

Manager: keep using **Staff Management** to add staff and upload photos. To let a staff member log in, create the Auth user in Supabase Authentication, then link their profile using the user's Auth UUID and the staff row UUID. Never expose the Supabase service-role key in frontend variables.
