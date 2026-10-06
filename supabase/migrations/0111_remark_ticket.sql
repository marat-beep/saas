-- ============================================================
-- 3DMP Service · 0111_remark_ticket.sql  (v98 — «Замечания» → тикет поддержки)
-- Связка модулей «Замечания к странице»/Bug Mode с Support Desk:
--   * app_support_from_remark: создать тикет из замечания и связать (related_type='remark').
-- Идемпотентно. Зависит от 0001..0110.
-- ============================================================

alter table public.app_page_remarks
  add column if not exists related_ticket_id uuid references public.app_support_tickets (id) on delete set null,
  add column if not exists status text;

create or replace function public.app_support_from_remark(p_token uuid, p_remark_id uuid)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; ulogin text; r record; subj text; descr text; cat text; tid uuid; tnum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select r0.* into r from public.app_page_remarks r0
    where r0.id = p_remark_id and (urole='admin' or r0.tenant_id=ten or r0.created_login=ulogin);
  if r.id is null then raise exception 'Замечание не найдено'; return; end if;
  if r.related_ticket_id is not null then
    select t.id, t.number into tid, tnum from public.app_support_tickets t where t.id = r.related_ticket_id;
    if tid is not null then return query select tid, tnum, 'Тикет уже создан'; return; end if;
  end if;

  subj := 'Замечание' || (case when coalesce(r.type,'') <> '' then ' (' || r.type || ')' else '' end) ||
          ' · ' || coalesce(r.module, '');
  cat := case lower(coalesce(r.type,''))
           when 'bug' then 'Ошибка'
           when 'error' then 'Ошибка'
           when 'idea' then 'Идея'
           else 'Замечание' end;
  descr := coalesce(r.text, '') || E'\n\n' ||
           'Страница: ' || coalesce(r.url, '') || E'\n' ||
           'Модуль: ' || coalesce(r.module, '') || E'\n' ||
           'Автор: ' || coalesce(r.author, ulogin) || E'\n' ||
           'Метка: x=' || coalesce(r.x::text, '—') || ', y=' || coalesce(r.y::text, '—');

  select c.id, c.number into tid, tnum
    from public.app_support_ticket_create(p_token, subj, descr, cat, 'normal', 'internal', r.module, r.url, 'remark', r.id) c;
  update public.app_page_remarks set related_ticket_id = tid, status = 'ticket' where id = r.id;
  return query select tid, tnum, 'Тикет создан из замечания';
end $$;

grant execute on function public.app_support_from_remark(uuid,uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Поддержка','Как отправить замечание в поддержку?',
   'В списке «Замечания/Bug Mode» кнопка «В поддержку» создаёт тикет из замечания (тема, текст, страница, координаты, автор) и связывает тикет с замечанием (related_type=remark). Повторная отправка вернёт уже созданный тикет.',
   'замечания bug mode поддержка тикет related remark app_support_from_remark')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Как отправить замечание в поддержку?');
