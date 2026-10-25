insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'motorcycle-photos', 'motorcycle-photos', false, 1048576,
  array['image/jpeg']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists motorcycle_photos_read on storage.objects;
create policy motorcycle_photos_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'motorcycle-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
drop policy if exists motorcycle_photos_insert on storage.objects;
create policy motorcycle_photos_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'motorcycle-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
drop policy if exists motorcycle_photos_delete on storage.objects;
create policy motorcycle_photos_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'motorcycle-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
