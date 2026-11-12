-- KOINOS · Ejecutar completo en Supabase → SQL Editor.
-- Zona horaria usada para "miércoles": America/Tegucigalpa (cámbiala si hace falta).
--
-- DESPUÉS de ejecutar: crea cada Líder/Maestro en Authentication → Users (Auto Confirm) y vincúlalo:
--   insert into public.members (full_name, role, auth_user_id)
--   select 'Nombre Apellido', 'master', id from auth.users where email = 'maestro@correo.com';   -- o 'leader'

create type public.user_role as enum ('member', 'leader', 'master');

create table public.members (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id) on delete set null,
  full_name text not null,
  role public.user_role not null default 'member',
  avatar_url text,
  qr_code_data text not null unique default gen_random_uuid()::text,
  cv_data jsonb not null default '{}',
  consecutive_absences int not null default 0,
  created_at timestamptz not null default now()
);
create unique index members_full_name_uq on public.members (lower(full_name));

create table public.events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  start_date date not null,
  end_date date not null,
  event_time time,
  location text,
  cover_image_url text,
  attachment_url text,
  created_by uuid references public.members(id) on delete set null,
  created_at timestamptz default now(),
  check (end_date >= start_date)
);

create table public.event_registrations (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  registered_at timestamptz default now(),
  unique (event_id, member_id)
);

create table public.attendance (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id) on delete cascade,
  event_id uuid references public.events(id) on delete set null,
  attendance_date date not null default (now() at time zone 'America/Tegucigalpa')::date,
  status boolean not null default true,
  scanned_by uuid references public.members(id) on delete set null,
  unique (member_id, attendance_date)
);
create index on public.attendance (attendance_date);

create table public.alerts (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id) on delete cascade,
  message text not null,
  resolved boolean not null default false,
  created_at timestamptz default now()
);

-- ───────── Funciones ─────────
create or replace function public.my_role() returns text
language sql stable security definer set search_path = public as
$$ select role::text from public.members where auth_user_id = auth.uid() limit 1 $$;

create or replace function public.last_wednesday(d date) returns date
language sql immutable as $$ select d - ((extract(dow from d)::int + 4) % 7) $$;

-- Cuenta miércoles consecutivos sin asistir (hacia atrás desde el último miércoles ya pasado)
-- y abre/cierra alertas cuando son 2 o más. Solo la ejecuta el Maestro (el panel la llama al cargar).
create or replace function public.refresh_alerts() returns void
language plpgsql security definer set search_path = public as $$
declare
  m record; w date; n int;
  today date := (now() at time zone 'America/Tegucigalpa')::date;
begin
  if public.my_role() is distinct from 'master' then return; end if;
  for m in select id, full_name, created_at::date as since from public.members where role = 'member' loop
    n := 0; w := public.last_wednesday(today - 1);
    while w >= m.since loop
      exit when exists (select 1 from public.attendance where member_id = m.id and attendance_date = w and status);
      n := n + 1; w := w - 7;
    end loop;
    update public.members set consecutive_absences = n where id = m.id;
    if n >= 2 then
      update public.alerts set message = m.full_name || ' lleva ' || n || ' miércoles seguidos sin asistir'
        where member_id = m.id and not resolved;
      if not found then
        insert into public.alerts (member_id, message)
        values (m.id, m.full_name || ' lleva ' || n || ' miércoles seguidos sin asistir');
      end if;
    else
      update public.alerts set resolved = true where member_id = m.id and not resolved;
    end if;
  end loop;
end $$;
revoke execute on function public.refresh_alerts() from public, anon;
grant execute on function public.refresh_alerts() to authenticated;

-- ───────── RLS ─────────
alter table public.members enable row level security;
alter table public.events enable row level security;
alter table public.event_registrations enable row level security;
alter table public.attendance enable row level security;
alter table public.alerts enable row level security;

-- Miembros: lectura pública (buscador y QR); cualquiera puede crear su perfil SOLO como 'member'.
create policy members_read on public.members for select using (true);
create policy members_signup on public.members for insert with check (role = 'member' and auth_user_id is null);
create policy members_master_update on public.members for update using (public.my_role() = 'master');
create policy members_master_delete on public.members for delete using (public.my_role() = 'master');

create policy events_read on public.events for select using (true);
create policy events_master on public.events for all using (public.my_role() = 'master') with check (public.my_role() = 'master');

create policy reg_read on public.event_registrations for select using (true);
create policy reg_insert on public.event_registrations for insert with check (true);
create policy reg_master_delete on public.event_registrations for delete using (public.my_role() = 'master');

-- Asistencia: solo Líder/Maestro pueden leer y registrar (escaneo); solo Maestro corrige.
create policy att_staff_read on public.attendance for select using (public.my_role() in ('leader', 'master'));
create policy att_staff_insert on public.attendance for insert with check (public.my_role() in ('leader', 'master'));
create policy att_master_write on public.attendance for update using (public.my_role() = 'master');
create policy att_master_delete on public.attendance for delete using (public.my_role() = 'master');

create policy alerts_master on public.alerts for all using (public.my_role() = 'master') with check (public.my_role() = 'master');

-- ───────── Storage ─────────
insert into storage.buckets (id, name, public) values
  ('avatars', 'avatars', true), ('event-covers', 'event-covers', true), ('event-attachments', 'event-attachments', true)
on conflict (id) do nothing;

create policy avatars_upload on storage.objects for insert with check (bucket_id = 'avatars');
create policy master_files on storage.objects for all
  using (public.my_role() = 'master') with check (public.my_role() = 'master');
