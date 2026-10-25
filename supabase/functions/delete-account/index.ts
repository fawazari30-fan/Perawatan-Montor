import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

Deno.serve(async (request: Request) => {
  if (request.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }
  const authorization = request.headers.get('Authorization');
  if (!authorization?.startsWith('Bearer ')) {
    return Response.json({ error: 'Authentication required' }, { status: 401 });
  }

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceRoleKey) {
    return Response.json({ error: 'Function secrets are missing' }, { status: 500 });
  }

  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  if (authError || !authData.user) {
    return Response.json({ error: 'Invalid session' }, { status: 401 });
  }

  const admin = createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const userId = authData.user.id;
  const [recordsResult, motorcyclesResult] = await Promise.all([
    admin
      .from('service_records')
      .select('receipt_paths')
      .eq('user_id', userId),
    admin
      .from('motorcycles')
      .select('photo_path')
      .eq('user_id', userId),
  ]);
  if (recordsResult.error || motorcyclesResult.error) {
    return Response.json(
      { error: recordsResult.error?.message ?? motorcyclesResult.error?.message },
      { status: 500 },
    );
  }

  const recordedReceiptPaths = [
    ...new Set(
      (recordsResult.data ?? []).flatMap((row) => row.receipt_paths ?? []),
    ),
  ];
  const recordedMotorcyclePhotoPaths = [
    ...new Set(
      (motorcyclesResult.data ?? [])
        .map((row) => row.photo_path)
        .filter((path): path is string => typeof path === 'string'),
    ),
  ];
  const [storedReceiptPaths, storedMotorcyclePhotoPaths] = await Promise.all([
    listOwnedFiles(admin, 'service-receipts', userId),
    listOwnedFiles(admin, 'motorcycle-photos', userId),
  ]);
  const receiptPaths = [...new Set([...recordedReceiptPaths, ...storedReceiptPaths])];
  const motorcyclePhotoPaths = [
    ...new Set([...recordedMotorcyclePhotoPaths, ...storedMotorcyclePhotoPaths]),
  ];
  if (receiptPaths.length > 0) {
    const { error } = await admin.storage
      .from('service-receipts')
      .remove(receiptPaths);
    if (error) return Response.json({ error: error.message }, { status: 500 });
  }
  if (motorcyclePhotoPaths.length > 0) {
    const { error } = await admin.storage
      .from('motorcycle-photos')
      .remove(motorcyclePhotoPaths);
    if (error) return Response.json({ error: error.message }, { status: 500 });
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
  if (deleteError) {
    return Response.json({ error: deleteError.message }, { status: 500 });
  }
  return Response.json({ success: true });
});

async function listOwnedFiles(
  admin: SupabaseClient,
  bucket: string,
  userId: string,
): Promise<string[]> {
  const directories = [userId];
  const files: string[] = [];
  while (directories.length > 0) {
    const directory = directories.pop()!;
    var offset = 0;
    while (true) {
      const { data, error } = await admin.storage.from(bucket).list(directory, {
        limit: 1000,
        offset,
      });
      if (error) throw error;
      for (const entry of data ?? []) {
        const path = `${directory}/${entry.name}`;
        if (entry.id == null) {
          directories.push(path);
        } else {
          files.push(path);
        }
      }
      if (!data || data.length < 1000) break;
      offset += data.length;
    }
  }
  return files;
}
