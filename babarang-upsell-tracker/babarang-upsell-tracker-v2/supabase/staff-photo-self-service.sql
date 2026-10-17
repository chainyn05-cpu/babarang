-- Babarang Upsell Tracker: safe staff self-service photo upload.
-- Run in Supabase SQL Editor AFTER the main schema.sql.
-- Manager must create each Auth user and link profiles.staff_id to the matching staff.id.

create or replace function public.update_my_staff_photo(new_photo_url text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or public.current_user_role() <> 'staff' or public.current_staff_id() is null then
    raise exception 'Only a linked staff account can update its own photo';
  end if;
  if new_photo_url is null or length(new_photo_url) > 2048 then
    raise exception 'Invalid photo URL';
  end if;
  update public.staff set photo_url = new_photo_url where id = public.current_staff_id();
  if not found then raise exception 'Linked staff record not found'; end if;
end;
$$;
revoke all on function public.update_my_staff_photo(text) from public;
grant execute on function public.update_my_staff_photo(text) to authenticated;

drop policy if exists "manager or linked staff upload staff photos" on storage.objects;
create policy "manager or linked staff upload staff photos" on storage.objects
for insert to authenticated
with check (
  bucket_id = 'staff-photos'
  and (
    public.current_user_role() = 'manager'
    or (public.current_user_role() = 'staff' and public.current_staff_id() is not null
      and (storage.foldername(name))[1] = public.current_staff_id()::text)
  )
);
