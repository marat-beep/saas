-- ============================================================
-- 3DMP Service · 0178_module_reports_v3.sql  (план v3, W34 «Отчёты/BI»)
-- Расширение app_module_report ветками новых модулей (v2/v3):
-- tooling, mdm, plm, edo, kedo, eam, safety, holding, projbudget, pmo,
-- logistics, itsm, elearning, accounting, tasks, crm_reminders.
-- Идемпотентно. Зависит от 0001..0177.
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
  -- ---------- W34: новые модули (v2/v3) ----------
  elsif m = 'tooling' then
    return query select coalesce(jsonb_agg(jsonb_build_object('serial',t.serial,'status',t.status,'machine',t.machine,'used_min',t.used_min,'resource_min',t.resource_min,'holder_login',t.holder_login,'created_at',to_char(t.created_at,'DD.MM.YY')) order by t.created_at desc), '[]'::jsonb)
      from public.app_tool_items t where (urole='admin' or t.tenant_id = ten);
  elsif m = 'mdm' then
    return query select coalesce(jsonb_agg(jsonb_build_object('code',i.code,'name',i.name,'item_type',i.item_type,'unit',i.unit,'grp',i.grp,'status',i.status,'source',i.source,'created_at',to_char(i.created_at,'DD.MM.YY')) order by i.code), '[]'::jsonb)
      from public.app_master_items i where (urole='admin' or i.tenant_id = ten);
  elsif m = 'plm' then
    return query select coalesce(jsonb_agg(jsonb_build_object('code',p.code,'name',p.name,'version',p.version,'state',p.state,'created_at',to_char(p.created_at,'DD.MM.YY')) order by p.code), '[]'::jsonb)
      from public.app_products p where (urole='admin' or p.tenant_id = ten);
  elsif m = 'edo' then
    return query select coalesce(jsonb_agg(jsonb_build_object('reg_number',f.reg_number,'kind',f.kind,'doc_type',f.doc_type,'title',f.title,'correspondent',f.correspondent,'status',f.status,'responsible_login',f.responsible_login,'due_date',to_char(f.due_date,'DD.MM.YY')) order by f.created_at desc), '[]'::jsonb)
      from public.app_doc_flows f where (urole='admin' or f.tenant_id = ten);
  elsif m = 'kedo' then
    return query select coalesce(jsonb_agg(jsonb_build_object('number',d.number,'doc_type',d.doc_type,'title',d.title,'employee_login',d.employee_login,'status',d.status,'signed_at',to_char(d.signed_at,'DD.MM.YY')) order by d.created_at desc), '[]'::jsonb)
      from public.app_hr_docs d where (urole='admin' or d.tenant_id = ten);
  elsif m = 'eam' then
    return query select coalesce(jsonb_agg(jsonb_build_object('equipment',e.name,'value',v.value,'unit',v.unit,'result',v.result,'ts',to_char(v.ts,'DD.MM.YY HH24:MI')) order by v.ts desc), '[]'::jsonb)
      from public.app_vibro_readings v left join public.app_equipment e on e.id = v.equipment_id
     where (urole='admin' or v.tenant_id = ten) and v.ts::date between d1 and d2;
  elsif m = 'safety' then
    return query select coalesce(jsonb_agg(jsonb_build_object('kind',s.kind,'event_date',to_char(s.event_date,'DD.MM.YY'),'location',s.location,'description',s.description,'severity',s.severity,'status',s.status) order by s.event_date desc), '[]'::jsonb)
      from public.app_safety_incidents s where (urole='admin' or s.tenant_id = ten);
  elsif m = 'holding' then
    return query select coalesce(jsonb_agg(jsonb_build_object('name',h.name,'code',h.code,'region',h.region,'share',h.share,'active',h.active) order by h.name), '[]'::jsonb)
      from public.app_holding_units h where (urole='admin' or h.tenant_id = ten);
  elsif m = 'projbudget' then
    return query select coalesce(jsonb_agg(jsonb_build_object('name',b.name,'version',b.version,'currency',b.currency,'status',b.status,'created_at',to_char(b.created_at,'DD.MM.YY')) order by b.created_at desc), '[]'::jsonb)
      from public.app_proj_budgets b where (urole='admin' or b.tenant_id = ten);
  elsif m = 'pmo' then
    return query select coalesce(jsonb_agg(jsonb_build_object('name',m2.name,'due_date',to_char(m2.due_date,'DD.MM.YY'),'status',m2.status,'weight',m2.weight) order by m2.due_date nulls last), '[]'::jsonb)
      from public.app_pmo_milestones m2 where (urole='admin' or m2.tenant_id = ten);
  elsif m = 'logistics' then
    return query select coalesce(jsonb_agg(jsonb_build_object('number',t.number,'direction',t.direction,'counterparty',t.counterparty,'cargo',t.cargo,'from_loc',t.from_loc,'to_loc',t.to_loc,'pickup_date',to_char(t.pickup_date,'DD.MM.YY'),'deliver_date',to_char(t.deliver_date,'DD.MM.YY'),'cost',t.cost,'status',t.status) order by t.created_at desc), '[]'::jsonb)
      from public.app_transport_orders t where (urole='admin' or t.tenant_id = ten);
  elsif m = 'itsm' then
    return query select coalesce(jsonb_agg(jsonb_build_object('number',t.number,'title',t.title,'priority',t.priority,'status',t.status,'assignee_login',t.assignee_login,'due_at',to_char(t.due_at,'DD.MM.YY HH24:MI'),'created_at',to_char(t.created_at,'DD.MM.YY')) order by t.created_at desc), '[]'::jsonb)
      from public.app_it_tickets t where (urole='admin' or t.tenant_id = ten);
  elsif m = 'elearning' then
    return query select coalesce(jsonb_agg(jsonb_build_object('code',c.code,'name',c.name,'category',c.category,'hours',c.hours,'active',c.active) order by c.name), '[]'::jsonb)
      from public.app_courses c where (urole='admin' or c.tenant_id = ten);
  elsif m = 'accounting' then
    return query select coalesce(jsonb_agg(jsonb_build_object('number',p.number,'period_date',to_char(p.period_date,'DD.MM.YY'),'debit_code',p.debit_code,'credit_code',p.credit_code,'amount',p.amount,'memo',p.memo) order by p.period_date desc, p.created_at desc), '[]'::jsonb)
      from public.app_postings p where (urole='admin' or p.tenant_id = ten) and p.period_date between d1 and d2;
  elsif m = 'tasks' then
    return query select coalesce(jsonb_agg(jsonb_build_object('title',t.title,'status',t.status,'priority',t.priority,'assignee_login',t.assignee_login,'due_date',to_char(t.due_date,'DD.MM.YY'),'est_hours',t.est_hours,'fact_hours',t.fact_hours) order by t.created_at desc), '[]'::jsonb)
      from public.app_tasks t where (urole='admin' or t.tenant_id = ten);
  elsif m = 'crm_reminders' then
    return query select coalesce(jsonb_agg(jsonb_build_object('title',r.title,'due_at',to_char(r.due_at,'DD.MM.YY HH24:MI'),'channel',r.channel,'status',r.status,'owner_login',r.owner_login) order by r.due_at desc), '[]'::jsonb)
      from public.app_crm_reminders r where (urole='admin' or r.tenant_id = ten);
  else
    return query select '[]'::jsonb;
  end if;
end $$;

grant execute on function public.app_module_report(uuid,text,date,date) to anon, authenticated;
