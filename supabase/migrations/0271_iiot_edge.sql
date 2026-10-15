-- ============================================================
-- 3DMP Service · 0271_iiot_edge.sql  (R4 · PROP-27 — MQTT/Sparkplug и edge-буфер)
-- Буфер store-and-forward для телеметрии (edge): при обрыве сети данные копятся и
-- доставляются после восстановления. Источник — 'mqtt'. Идемпотентно.
-- ============================================================

create table if not exists public.app_iiot_edge (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  machine text,
  metric text,
  value numeric,
  source text not null default 'mqtt',
  payload jsonb,
  delivered boolean not null default false,
  ts timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index if not exists app_iiot_edge_idx on public.app_iiot_edge (tenant_id, delivered, ts);

create or replace function public.app_iiot_edge_list(p_token uuid, p_undelivered boolean default true)
returns table (id uuid, machine text, metric text, value numeric, source text, delivered boolean, ts timestamptz)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select e.id, e.machine, e.metric, e.value, e.source, e.delivered, e.ts
    from public.app_iiot_edge e
    where (urole = 'admin' or e.tenant_id = ten) and (not coalesce(p_undelivered, true) or e.delivered = false)
    order by e.ts desc limit 500;
end $$;
grant execute on function public.app_iiot_edge_list(uuid,boolean) to anon, authenticated;

create or replace function public.app_iiot_edge_push(p_token uuid, p_machine text, p_metric text, p_value numeric, p_source text, p_payload jsonb default null)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  insert into public.app_iiot_edge (tenant_id, machine, metric, value, source, payload)
  values (ten, p_machine, p_metric, p_value, coalesce(p_source, 'mqtt'), p_payload);
  return query select true, 'Принято в edge-буфер';
end $$;
grant execute on function public.app_iiot_edge_push(uuid,text,text,numeric,text,jsonb) to anon, authenticated;

create or replace function public.app_iiot_edge_ack(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  update public.app_iiot_edge set delivered = true where id = p_id and (urole = 'admin' or tenant_id = ten);
  return query select true, 'Отмечено доставленным';
end $$;
grant execute on function public.app_iiot_edge_ack(uuid,uuid) to anon, authenticated;

create or replace function public.app_iiot_edge_flush(p_token uuid)
returns table (ok boolean, message text, count integer)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  with u as (update public.app_iiot_edge set delivered = true
    where (urole = 'admin' or tenant_id = ten) and delivered = false returning 1)
  select count(*) into n from u;
  return query select true, 'Доставлено (сброшено из буфера)', coalesce(n, 0);
end $$;
grant execute on function public.app_iiot_edge_flush(uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags
from (values
  ('IIoT','MQTT/Sparkplug и edge-буфер (store-and-forward)',
   'Реальный приём телеметрии выполняет edge-воркер: по MQTT/Sparkplug B (или OPC-UA/MTConnect/Modbus). При обрыве сети данные копятся в edge-буфере (app_iiot_edge) и доставляются после восстановления (store-and-forward). В «IIoT» панель «MQTT/Edge-буфер» показывает недоставленные сообщения и позволяет отметить их доставленными/сбросить буфер.',
   'IIoT MQTT Sparkplug edge буфер store-and-forward телеметрия обрыв сети')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.question=v.question);
