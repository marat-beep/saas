-- ============================================================
-- 3DMP Service · 0081_doc_templates_ext.sql  (v59 — расширение шаблонов)
-- Дополнительные шаблоны документов, словарь типов документов, дублирование
-- шаблона. База знаний. Зависит от 0001..0080.
-- ============================================================

-- ---------- Дублирование шаблона ----------
create or replace function public.app_doc_template_duplicate(p_token uuid, p_id uuid)
returns table (id uuid, name text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; mid uuid; mname text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  insert into public.app_doc_templates (tenant_id, doc_type, name, body, active)
  select t.tenant_id, t.doc_type, t.name || ' (копия)', t.body, t.active
    from public.app_doc_templates t
   where t.id=p_id and (urole='admin' or t.tenant_id=ten)
   returning id, name into mid, mname;
  return query select mid, mname, 'Шаблон скопирован';
end $$;

grant execute on function public.app_doc_template_duplicate(uuid,uuid) to anon, authenticated;

-- ---------- Словарь типов документов ----------
do $$
declare did uuid;
begin
  if not exists (select 1 from public.app_dictionaries where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and lower(code)='doc_type') then
    insert into public.app_dictionaries (tenant_id, code, name, description)
    values ('aaaaaaaa-0000-0000-0000-000000000001','doc_type','Типы документов','Шаблоны документов') returning id into did;
    insert into public.app_dictionary_items (dict_id, value, label, sort) values
      (did,'kp','Коммерческое предложение',10),
      (did,'contract','Договор',20),
      (did,'act','Акт',30),
      (did,'invoice','Счёт на оплату',40),
      (did,'waybill','Накладная',50),
      (did,'tz','Техническое задание',60),
      (did,'techcard','Технологическая карта',70),
      (did,'passport','Паспорт качества',80),
      (did,'other','Прочее',90);
  end if;
end $$;

-- ---------- Дополнительные шаблоны (тенант A) ----------
do $$
declare A constant uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
begin
  insert into public.app_doc_templates (tenant_id, doc_type, name, body, active)
  select A, v.t, v.n, v.b, true
  from (values
    ('invoice','Счёт на оплату',
     'СЧЁТ на оплату № {{order}} от {{date}}' || chr(10) || 'Плательщик: {{customer}}' || chr(10) || 'Основание: {{title}}' || chr(10) || 'Сумма: {{amount}} ₽'),
    ('waybill','Накладная (ТОРГ-12)',
     'НАКЛАДНАЯ № {{order}} от {{date}}' || chr(10) || 'Поставщик: 3DMP' || chr(10) || 'Получатель: {{customer}}' || chr(10) || 'Наименование: {{title}}'),
    ('act','Акт приёма-передачи',
     'АКТ приёма-передачи № {{order}} от {{date}}' || chr(10) || 'Работы выполнены: {{title}}' || chr(10) || 'Заказчик: {{customer}}' || chr(10) || 'Стоимость: {{amount}} ₽'),
    ('tz','Техническое задание',
     'ТЕХНИЧЕСКОЕ ЗАДАНИЕ' || chr(10) || 'Изделие: {{title}}' || chr(10) || 'Заказчик: {{customer}}' || chr(10) || 'Требования: (заполните)'),
    ('passport','Паспорт качества',
     'ПАСПОРТ КАЧЕСТВА' || chr(10) || 'Изделие: {{title}}' || chr(10) || 'Заказ № {{order}} от {{date}}' || chr(10) || 'Соответствует ТУ/ГОСТ: (указать)')
  ) as v(t,n,b)
  where not exists (select 1 from public.app_doc_templates t2 where t2.tenant_id=A and t2.name=v.n);
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Документы','Шаблоны документов — расширение',
   'Модуль «Шаблоны документов»: пользователь сам создаёт/редактирует шаблоны (типы берутся из справочника «Типы документов»), подставляет переменные {{customer}}, {{order}}, {{title}}, {{amount}}, {{date}} и создаёт готовый документ по заявке. Добавлены типовые шаблоны: счёт, накладная, акт приёма-передачи, ТЗ, паспорт качества; любой шаблон можно дублировать и править.',
   'шаблоны документы КП договор акт счёт накладная ТЗ паспорт подстановки дублирование')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Шаблоны документов — расширение');
