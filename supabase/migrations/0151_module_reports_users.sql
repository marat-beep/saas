-- ============================================================
-- 3DMP Service · 0151_module_reports_users.sql  (ветка users для app_module_report)
-- Идемпотентно. Зависит от 0001..0150.
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
  elsif m = 'naryads' then
    return query select coalesce(jsonb_agg(jsonb_build_object('number',n.number,'title',n.title,'status',n.status,'priority',n.priority,'assignee',n.assignee,'plan_hours',n.plan_hours,'fact_hours',n.fact_hours) order by n.created_at desc), '[]'::jsonb)
      from public.app_naryads n where (urole='admin' or n.tenant_id = ten);
  elsif m = 'quality' then
    return query select coalesce(jsonb_agg(jsonb_build_object('number',c.number,'product',c.product,'status',c.status,'inspector',c.inspector,'created_at',to_char(c.created_at,'DD.MM.YY')) order by c.created_at desc), '[]'::jsonb)
      from public.app_qc_checks c where (urole='admin' or c.tenant_id = ten) and c.created_at::date between d1 and d2;
  elsif m = 'routes' then
    return query select coalesce(jsonb_agg(jsonb_build_object('number',r.number,'name',r.name,'qty',r.qty,'status',r.status) order by r.created_at desc), '[]'::jsonb)
      from public.app_routes r where (urole='admin' or r.tenant_id = ten);
  elsif m = 'mes' then
    return query select coalesce(jsonb_agg(jsonb_build_object('number',t.number,'title',t.title,'status',t.status,'priority',t.priority,'operator',t.operator) order by t.created_at desc), '[]'::jsonb)
      from public.app_mes_tasks t where (urole='admin' or t.tenant_id = ten);
  elsif m = 'nc' then
    return query select coalesce(jsonb_agg(jsonb_build_object('detail',p.detail,'program_no',p.program_no,'version',p.version,'status',p.status,'program_time_min',p.program_time_min) order by p.created_at desc), '[]'::jsonb)
      from public.app_nc_programs p where (urole='admin' or p.tenant_id = ten);
  elsif m = 'invoices' then
    return query select coalesce(jsonb_agg(jsonb_build_object('number',i.number,'customer',i.customer,'amount',i.amount,'status',i.status,'due_date',to_char(i.due_date,'DD.MM.YY')) order by i.created_at desc), '[]'::jsonb)
      from public.app_invoices i where (urole='admin' or i.tenant_id = ten);
  elsif m = 'claims' then
    return query select coalesce(jsonb_agg(jsonb_build_object('number',cl.number,'customer',cl.customer,'product',cl.product,'reason',cl.reason,'severity',cl.severity,'status',cl.status) order by cl.created_at desc), '[]'::jsonb)
      from public.app_claims cl where (urole='admin' or cl.tenant_id = ten);
  elsif m = 'tenders' then
    return query select coalesce(jsonb_agg(jsonb_build_object('title',t.title,'category',t.category,'material',t.material,'qty',t.qty,'status',t.status,'deadline',to_char(t.deadline,'DD.MM.YY')) order by t.created_at desc), '[]'::jsonb)
      from public.tenders t where (urole='admin' or t.tenant_id = ten);
  elsif m = 'users' then
    if urole not in ('admin','owner') then raise exception 'Нет прав'; end if;
    return query select coalesce(jsonb_agg(jsonb_build_object('login',u.login,'name',u.full_name,'role',u.role,'status',case when u.active then 'активен' else 'выкл' end) order by u.login), '[]'::jsonb)
      from public.app_users u;
  else
    return query select '[]'::jsonb;
  end if;
end $$;

grant execute on function public.app_module_report(uuid,text,date,date) to anon, authenticated;
