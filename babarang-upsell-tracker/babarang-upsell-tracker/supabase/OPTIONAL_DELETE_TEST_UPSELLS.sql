-- DANGER: This deletes EVERY upsell entry. Run only if all current entries are test data.
-- Does not delete staff, profiles, or auth users.
-- Review/backup first.
BEGIN;
DELETE FROM public.upsell_entries;
COMMIT;
