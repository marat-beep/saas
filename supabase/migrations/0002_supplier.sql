-- ============================================================
-- 3DMP Service · 0002_supplier.sql
-- Модуль «Портал закупок для поставщиков»: закупки и предложения (КП).
-- Применение: Supabase → SQL Editor → вставить целиком → Run.
-- Зависит от 0001_init.sql (auth.users). Схемы gravirovka / norms_* не затрагивает.
-- ============================================================

-- ---------- Закупки ----------
create table if not exists public.tenders (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  description text,
  category    text,
  material    text,
  qty         numeric,
  unit        text,
  customer    text,
  deadline    date,
  status      text not null default 'open',   -- open | closed | awarded
  created_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now()
);

-- ---------- Предложения поставщиков (КП) ----------
create table if not exists public.bids (
  id            uuid primary key default gen_random_uuid(),
  tender_id     uuid not null references public.tenders (id) on delete cascade,
  supplier_id   uuid not null references auth.users (id) on delete cascade,
  supplier_name text,
  price         numeric not null default 0,
  term_days     integer,
  comment       text,
  status        text not null default 'submitted',  -- submitted | accepted | rejected
  created_at    timestamptz not null default now(),
  unique (tender_id, supplier_id)
);

create index if not exists bids_supplier_idx on public.bids (supplier_id);
create index if not exists bids_tender_idx   on public.bids (tender_id);

-- ---------- RLS ----------
alter table public.tenders enable row level security;
alter table public.bids    enable row level security;

-- Закупки: авторизованный видит открытые; автор — свои в любом статусе.
drop policy if exists tenders_read on public.tenders;
create policy tenders_read on public.tenders for select to authenticated
  using (status = 'open' or created_by = auth.uid());

drop policy if exists tenders_insert on public.tenders;
create policy tenders_insert on public.tenders for insert to authenticated
  with check (created_by = auth.uid());

drop policy if exists tenders_update_own on public.tenders;
create policy tenders_update_own on public.tenders for update to authenticated
  using (created_by = auth.uid());

-- Предложения: поставщик видит свои; заказчик — по своим закупкам.
drop policy if exists bids_read on public.bids;
create policy bids_read on public.bids for select to authenticated
  using (
    supplier_id = auth.uid()
    or tender_id in (select id from public.tenders where created_by = auth.uid())
  );

drop policy if exists bids_insert_own on public.bids;
create policy bids_insert_own on public.bids for insert to authenticated
  with check (supplier_id = auth.uid());

drop policy if exists bids_update_own on public.bids;
create policy bids_update_own on public.bids for update to authenticated
  using (supplier_id = auth.uid()) with check (supplier_id = auth.uid());

-- ---------- Демо-закупки (только если таблица пуста) ----------
insert into public.tenders (title, description, category, material, qty, unit, customer, deadline, status)
select v.title, v.description, v.category, v.material, v.qty, v.unit, v.customer, v.deadline, 'open'
from (values
  ('Изготовление пресс-формы втулки', 'Комплект КД и 3D-модель прилагаются. Материал формообразующих — сталь 40Х.', 'Оснастка', 'Сталь 40Х', 1, 'компл', 'ООО «Привод»', (current_date + 14)::date),
  ('Фрезеровка корпусных деталей, 5 осей', 'Партия корпусов из алюминия Д16Т, допуск ±0,05 мм.', 'Механообработка', 'Д16Т', 200, 'шт', 'АО «Урал-Штамп»', (current_date + 21)::date),
  ('Токарные работы: валы и шейки', 'Валы из стали 45, закалка ТВЧ, шлифовка шеек.', 'Механообработка', 'Сталь 45', 120, 'шт', 'ООО «Точмаш-Сервис»', (current_date + 10)::date),
  ('Лазерная резка листа 4 мм', 'Раскрой листов 09Г2С по карте раскроя, кромка без заусенцев.', 'Лазерная резка', '09Г2С', 60, 'лист', 'ООО «ЛазерПро-Юг»', (current_date + 7)::date)
) as v(title, description, category, material, qty, unit, customer, deadline)
where not exists (select 1 from public.tenders);
