import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

const jakartaDate = (date: Date): string => {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Jakarta',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);
  const value = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${value.year}-${value.month}-${value.day}`;
};

const daysBetween = (from: string, to: string): number => {
  const a = Date.parse(`${from}T00:00:00Z`);
  const b = Date.parse(`${to}T00:00:00Z`);
  return Math.round((b - a) / 86_400_000);
};

Deno.serve(async (request: Request) => {
  if (request.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }
  const cronSecret = Deno.env.get('CRON_SECRET');
  if (!cronSecret || request.headers.get('x-cron-secret') !== cronSecret) {
    return new Response('Unauthorized', { status: 401 });
  }

  const url = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceRoleKey) {
    return new Response('Supabase function secrets are missing', { status: 500 });
  }

  const supabase = createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const today = jakartaDate(new Date());
  const [scheduleResult, settingsResult] = await Promise.all([
    supabase
      .from('v_schedule_status')
      .select(
        'id, user_id, motorcycle_id, title, next_due_date, effective_due_date, next_due_km, odometer_km, status, last_done_km, last_done_date',
      ),
    supabase
      .from('user_settings')
      .select('user_id, push_enabled, remind_days_before, remind_km_before'),
  ]);
  if (scheduleResult.error || settingsResult.error) {
    return Response.json(
      { error: scheduleResult.error?.message ?? settingsResult.error?.message },
      { status: 500 },
    );
  }

  const settingsByUser = new Map(
    (settingsResult.data ?? []).map((row) => [row.user_id, row]),
  );
  let created = 0;
  for (const schedule of scheduleResult.data ?? []) {
    if (schedule.status === 'snoozed') continue;
    const settings = settingsByUser.get(schedule.user_id);
    const daysBefore = settings?.remind_days_before ?? 3;
    const dueDate = (schedule.effective_due_date ?? schedule.next_due_date) as string | null;
    if (dueDate) {
      const daysLeft = daysBetween(today, dueDate);
      const allowedDays = new Set([7, 3, 1, 0, daysBefore]);
      if (allowedDays.has(daysLeft)) {
        const title = daysLeft === 0
          ? 'Perawatan jatuh tempo hari ini'
          : `Perawatan jatuh tempo dalam ${daysLeft} hari`;
        const inserted = await insertOnce(supabase, {
          user_id: schedule.user_id,
          motorcycle_id: schedule.motorcycle_id,
          schedule_id: schedule.id,
          title,
          body: schedule.title,
          notification_type: 'date',
          dedupe_key: `${schedule.id}:date:${today}`,
        });
        created += inserted ? 1 : 0;
      } else if (daysLeft < 0 && Math.abs(daysLeft) % 3 === 0) {
        const cycle = `${schedule.last_done_km}:${schedule.last_done_date}`;
        const prefix = `${schedule.id}:overdue:${cycle}:`;
        const { count, error } = await supabase
          .from('notification_inbox')
          .select('id', { count: 'exact', head: true })
          .eq('user_id', schedule.user_id)
          .like('dedupe_key', `${prefix}%`);
        if (!error && (count ?? 0) < 3) {
          const inserted = await insertOnce(supabase, {
            user_id: schedule.user_id,
            motorcycle_id: schedule.motorcycle_id,
            schedule_id: schedule.id,
            title: 'Jadwal perawatan terlambat',
            body: `${schedule.title} belum dicatat selesai.`,
            notification_type: 'overdue',
            dedupe_key: `${prefix}${today}`,
          });
          created += inserted ? 1 : 0;
        }
      }
    }

    const kmLeft = schedule.next_due_km == null
      ? null
      : schedule.next_due_km - schedule.odometer_km;
    const kmThreshold = settings?.remind_km_before ?? 200;
    if (kmLeft != null && kmLeft <= kmThreshold && kmLeft >= 0) {
      const inserted = await insertOnce(supabase, {
        user_id: schedule.user_id,
        motorcycle_id: schedule.motorcycle_id,
        schedule_id: schedule.id,
        title: 'Perawatan hampir jatuh tempo',
        body: `${schedule.title} tersisa ${kmLeft} km.`,
        notification_type: 'odometer',
        dedupe_key: `${schedule.id}:km:${schedule.last_done_km}:${schedule.last_done_date}`,
      });
      created += inserted ? 1 : 0;
    }
  }

  return Response.json({ created, date: today });
});

async function insertOnce(
  supabase: SupabaseClient,
  notification: Record<string, unknown>,
): Promise<boolean> {
  const { error } = await supabase
    .from('notification_inbox')
    .insert(notification);
  if (!error) return true;
  if (error.code === '23505') return false;
  console.error('Could not create reminder notification', error.message);
  return false;
}