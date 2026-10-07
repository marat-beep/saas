-- ============================================================
-- 3DMP Service · 0149_module_reports.sql  (универсальный отчёт по модулю + KB-пакет)
-- Один RPC app_module_report(p_module) отдаёт данные модуля как jsonb для PDF/CSV.
-- Идемпотентно. Зависит от 0001..0148.
-- ============================================================

drop function if exists public.app_module_report(uuid,text,date,date);
create or replace function public.app_module_report(p_token uuid, p_module text, p_from date default null, p_to date default null)
returns table (rows jsonb)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; d1 date; d2 date; m text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  d1 := coalesce(p_from, current_date - 3650); d2 := coalesce(p_to, current_date);
  m := lower(coalesce(trim(p_module),''));

  if m = 'customers' then
    return query select coalesce(jsonb_agg(jsonb_build_object('name',c.name,'inn',c.inn,'contact',c.contact_person,'phone',c.phone,'email',c.email,'address',c.address) order by c.name), '[]'::jsonb)
      from public.app_customers c where (urole='admin' or c.tenant_id = ten);
  elsif m = 'suppliers' then
    return query select coalesce(jsonb_agg(jsonb_build_object('name',s.name,'inn',s.inn,'contact',s.contact,'phone',s.phone,'email',s.email,'category',s.category,'status',s.status,'rating',s.rating) order by s.name), '[]'::jsonb)
      from public.app_suppliers s where (urole='admin' or s.tenant_id = ten);
  elsif m = 'departments' then
    return query select coalesce(jsonb_agg(jsonb_build_object('name',d.name,'code',d.code,'head',d.head,'active',d.active) order by d.name), '[]'::jsonb)
      from public.app_departments d where (urole='admin' or d.tenant_id = ten);
  elsif m = 'equipment' then
    return query select coalesce(jsonb_agg(jsonb_build_object('name',e.name,'code',e.code,'kind',e.kind,'model',e.model,'dept',e.dept,'status',e.status) order by e.name), '[]'::jsonb)
      from public.app_equipment e where (urole='admin' or e.tenant_id = ten);
  elsif m = 'materials' then
    return query select coalesce(jsonb_agg(jsonb_build_object('name',mm.name,'unit',mm.unit,'qty',mm.qty,'min_qty',mm.min_qty,'price',mm.price) order by mm.name), '[]'::jsonb)
      from public.app_materials mm where (urole='admin' or mm.tenant_id = ten);
  elsif m = 'knowledge' then
    return query select coalesce(jsonb_agg(jsonb_build_object('category',k.category,'question',k.question,'tags',k.tags) order by k.category, k.question), '[]'::jsonb)
      from public.app_knowledge k where (urole='admin' or k.tenant_id = ten or k.tenant_id is null);
  elsif m = 'iiot' then
    return query select coalesce(jsonb_agg(jsonb_build_object('machine',r.machine,'metric',r.metric,'value',r.value,'ts',to_char(r.ts,'DD.MM.YY HH24:MI')) order by r.ts desc), '[]'::jsonb)
      from public.app_iiot_readings r where (urole='admin' or r.tenant_id = ten) and r.ts::date between d1 and d2;
  elsif m = 'service' then
    return query select coalesce(jsonb_agg(jsonb_build_object('number',r.number,'customer',c.name,'title',r.title,'priority',r.priority,'status',r.status,'reported_at',to_char(coalesce(r.reported_at,r.created_at),'DD.MM.YY')) order by r.created_at desc), '[]'::jsonb)
      from public.app_service_requests r left join public.app_customers c on c.id = r.customer_id
     where (urole='admin' or r.tenant_id = ten) and coalesce(r.reported_at,r.created_at)::date between d1 and d2;
  else
    return query select '[]'::jsonb;
  end if;
end $$;

grant execute on function public.app_module_report(uuid,text,date,date) to anon, authenticated;

-- ---------- KB-пакет для новых модулей ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('IIoT','Телеметрия станков: показания и отчёт',
   'Приём телеметрии (app_iiot_readings: станок, метрика, значение, время), просмотр истории, авто-тикеты сервиса по правилам. Универсальный отчёт по модулю — app_module_report(''iiot'', from, to); кнопка «📄 Отчёт PDF». Связи: OEE (наработка), Сервис (авто-тикеты), Производство.',
   'IIoT телеметрия станки метрики показания отчёт OEE сервис'),
  ('CRM','Заказчики: реестр и отчёт',
   'Заказчики (app_customer_list): название, ИНН, контакт, телефон, e-mail, адрес; заявки/заказы/счета по заказчику. Универсальный отчёт — app_module_report(''customers''); кнопка «📄 Отчёт PDF». Связи: Заказы, Сервис (карточка завода), Финансы, Документы.',
   'CRM заказчики реестр отчёт контакты ИНН'),
  ('Закупки','Поставщики: реестр и отчёт',
   'Поставщики (app_suppliers): название, ИНН, контакт, категория, рейтинг, статус (аккредитован/заблокирован). Универсальный отчёт — app_module_report(''suppliers''); кнопка «📄 Отчёт PDF». Связи: Закупки (КП), Портал поставщика.',
   'поставщики реестр аккредитация рейтинг отчёт закупки'),
  ('Организация','Подразделения: структура и отчёт',
   'Подразделения (app_departments): название, код, руководитель, родитель (иерархия), активность. Универсальный отчёт — app_module_report(''departments''); кнопка «📄 Отчёт PDF». Связи: Сотрудники, Роли, Производство.',
   'организация подразделения структура иерархия отчёт'),
  ('База знаний','Гид и база знаний: поиск и отчёт',
   'База знаний (app_knowledge): категория, вопрос, ответ, теги; поиск (app_knowledge_search) и системный поиск в шапке (app_global_search). Универсальный отчёт — app_module_report(''knowledge''); кнопка «📄 Отчёт PDF».',
   'база знаний гид статьи поиск отчёт')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = v.question
);
