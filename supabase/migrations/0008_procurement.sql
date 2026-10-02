-- ============================================================
-- 3DMP Service · 0008_procurement.sql  (v1.4 — закупки и поставщики)
-- Аккредитация поставщика, публикация закупок, КП, выбор победителя.
-- Зависит от 0001..0007. public.orders НЕ трогаем.
-- ============================================================

-- ---------- Профиль поставщика (аккредитация) ----------
create table if not exists public.app_supplier_profiles (
  id          uuid primary key default gen_random_uuid(),
  app_user_id uuid unique not null references public.app_users (id) on delete cascade,
  company     text,
  inn         text,
  contact     text,
  phone       text,
  email       text,
  status      text not null default 'pending',  -- pending | approved | rejected
  note        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
alter table public.app_supplier_profiles enable row level security;

-- ---------- Закупки: поля победителя ----------
alter table public.tenders add column if not exists awarded_bid_id uuid references public.bids (id) on delete set null;
alter table public.tenders add column if not exists closed_at timestamptz;

-- ---------- Мой профиль поставщика ----------
create or replace function public.app_supplier_profile_get(p_token uuid)
returns table (company text, inn text, contact text, phone text, email text, status text, note text, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare uid uuid;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return; end if;
  return query select p.company, p.inn, p.contact, p.phone, p.email, p.status, p.note, p.updated_at
    from public.app_supplier_profiles p where p.app_user_id = uid;
end $$;

create or replace function public.app_supplier_profile_save(
  p_token uuid, p_company text, p_inn text, p_contact text, p_phone text, p_email text
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if coalesce(trim(p_company), '') = '' then return query select false, 'Укажите организацию'; return; end if;

  insert into public.app_supplier_profiles (app_user_id, company, inn, contact, phone, email, status)
  values (uid, trim(p_company), nullif(trim(p_inn),''), nullif(trim(p_contact),''), nullif(trim(p_phone),''), nullif(trim(p_email),''), 'pending')
  on conflict (app_user_id) do update
    set company = excluded.company, inn = excluded.inn, contact = excluded.contact,
        phone = excluded.phone, email = excluded.email, status = 'pending', updated_at = now();

  perform public.app_notif_roles(array['admin','manager','owner'], 'Аккредитация: ' || trim(p_company),
          'Заявка от ' || coalesce(ulogin,''), 'apps/procurement/index.html');
  return query select true, 'Заявка на аккредитацию отправлена';
end $$;

-- ---------- Публикация закупки (закупщик) ----------
create or replace function public.app_tender_create(
  p_token uuid, p_title text, p_description text, p_category text, p_material text,
  p_qty numeric, p_unit text, p_customer text, p_deadline date
) returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; tid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid into uid from public.app_session_user(p_token) s;
  if coalesce(trim(p_title), '') = '' then raise exception 'Укажите название закупки'; end if;

  insert into public.tenders (title, description, category, material, qty, unit, customer, deadline, status, created_by)
  values (trim(p_title), nullif(trim(p_description),''), nullif(trim(p_category),''), nullif(trim(p_material),''),
          p_qty, nullif(trim(p_unit),''), nullif(trim(p_customer),''), p_deadline, 'open', uid)
  returning tenders.id into tid;

  perform public.app_notif_roles(array['supplier'], 'Новая закупка: ' || trim(p_title),
          coalesce(nullif(trim(p_customer),''), '') , 'apps/supplier/index.html');
  return query select tid, 'Закупка опубликована';
end $$;

-- ---------- Закупки для закупщика (с числом КП) ----------
create or replace function public.app_tender_list_full(p_token uuid)
returns table (id uuid, title text, category text, customer text, deadline date, status text,
               bids_count bigint, awarded_bid_id uuid, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  return query
    select t.id, t.title, t.category, t.customer, t.deadline, t.status,
           (select count(*) from public.bids b where b.tender_id = t.id), t.awarded_bid_id, t.created_at
    from public.tenders t order by t.created_at desc;
end $$;

create or replace function public.app_bids_for_tender(p_token uuid, p_tender_id uuid)
returns table (id uuid, supplier_name text, price numeric, term_days integer, comment text, status text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  return query select b.id, b.supplier_name, b.price, b.term_days, b.comment, b.status, b.created_at
    from public.bids b where b.tender_id = p_tender_id order by b.price asc, b.created_at;
end $$;

-- ---------- Выбор победителя ----------
create or replace function public.app_tender_award(p_token uuid, p_tender_id uuid, p_bid_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ttitle text; win_user uuid; win_name text; sup record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select t.title into ttitle from public.tenders t where t.id = p_tender_id;
  if ttitle is null then return query select false,'Закупка не найдена'; return; end if;
  select b.app_user_id, b.supplier_name into win_user, win_name from public.bids b where b.id = p_bid_id and b.tender_id = p_tender_id;
  if win_user is null then return query select false,'Предложение не найдено'; return; end if;

  update public.bids set status = case when id = p_bid_id then 'accepted' else 'rejected' end where tender_id = p_tender_id;
  update public.tenders set status = 'awarded', awarded_bid_id = p_bid_id, closed_at = now() where id = p_tender_id;

  for sup in select b.app_user_id from public.bids b where b.tender_id = p_tender_id and b.app_user_id is not null loop
    if sup.app_user_id = win_user then
      perform public.app_notif_send(sup.app_user_id, 'Вы выбраны: ' || ttitle, 'Ваше КП принято', 'apps/supplier/index.html');
    else
      perform public.app_notif_send(sup.app_user_id, 'Закупка ' || ttitle || ': победитель определён', 'Ваше КП отклонено', 'apps/supplier/index.html');
    end if;
  end loop;
  return query select true, 'Победитель: ' || coalesce(win_name,'—');
end $$;

-- ---------- Смена статуса закупки ----------
create or replace function public.app_tender_set_status(p_token uuid, p_tender_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  update public.tenders set status = p_status, closed_at = case when p_status in ('closed','awarded') then now() else closed_at end
   where id = p_tender_id;
  return query select true, 'Статус обновлён';
end $$;

-- ---------- Аккредитация учитывается при подаче КП ----------
create or replace function public.supplier_submit_bid(
  p_token uuid, p_tender_id uuid, p_price numeric, p_term_days integer, p_comment text
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; uname text; ttitle text; pstatus text;
begin
  select u.id, coalesce(u.full_name, u.login) into uid, uname
  from public.app_sessions s join public.app_users u on u.id = s.user_id
  where s.token = p_token and s.expires_at > now() and u.active;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if p_price is null or p_price <= 0 then return query select false, 'Укажите цену больше нуля'; return; end if;

  select p.status into pstatus from public.app_supplier_profiles p where p.app_user_id = uid;
  if pstatus = 'rejected' then return query select false, 'Аккредитация отклонена — подача КП недоступна'; return; end if;

  insert into public.bids (tender_id, app_user_id, supplier_name, price, term_days, comment)
  values (p_tender_id, uid, uname, p_price, p_term_days, nullif(p_comment, ''))
  on conflict (tender_id, app_user_id) do update
    set price = excluded.price, term_days = excluded.term_days, comment = excluded.comment;

  select t.title into ttitle from public.tenders t where t.id = p_tender_id;
  perform public.app_notif_roles(array['admin','manager','owner'], 'Новое КП: ' || coalesce(ttitle,'закупка'),
          uname || ' · ' || to_char(p_price, 'FM999G999G999G999') || ' ₽', 'apps/procurement/index.html');
  return query select true, 'Предложение сохранено';
end $$;

grant execute on function public.app_supplier_profile_get(uuid) to anon, authenticated;
grant execute on function public.app_supplier_profile_save(uuid,text,text,text,text,text) to anon, authenticated;
grant execute on function public.app_tender_create(uuid,text,text,text,text,numeric,text,text,date) to anon, authenticated;
grant execute on function public.app_tender_list_full(uuid) to anon, authenticated;
grant execute on function public.app_bids_for_tender(uuid,uuid) to anon, authenticated;
grant execute on function public.app_tender_award(uuid,uuid,uuid) to anon, authenticated;
grant execute on function public.app_tender_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.supplier_submit_bid(uuid,uuid,numeric,integer,text) to anon, authenticated;
