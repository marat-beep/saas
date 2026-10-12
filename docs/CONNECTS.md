# Связи модулей каталога (connects) — семантика и односторонние связи (U5)

_Автогенерация `tools/catalog-connects.js --md`. Модулей: **97**; связей: **462**; односторонних (A→B без B→A): **314**._

## Семантика

`connects` в `assets/js/catalog.js` — это **направленные** связи: «модуль передаёт данные / ссылается на другой модуль». Поэтому отсутствие обратной связи — норма (а не дефект), кроме явно парных сценариев. Аудит `tools/audit.ps1` проверяет только **валидность** id (битые связи = 0). Односторонние связи здесь перечислены для прозрачности; часть из них — «хаб-модули» (в них ссылаются многие, сами ссылаются точечно).

## Хаб-модули (по числу входящих ссылок)

| Модуль | Входящих |
|---|---|
| `production` | 29 |
| `orders` | 28 |
| `registry` | 23 |
| `economics` | 19 |
| `org` | 17 |
| `finance` | 17 |
| `docs` | 15 |
| `platform` | 13 |
| `panel` | 12 |
| `warehouse` | 11 |
| `hr` | 11 |
| `issues` | 10 |
| `procurement` | 10 |
| `integrations` | 9 |
| `mes` | 9 |

## Односторонние связи по источникам

- `access` → `roles`, `admin`, `hr`, `departments`
- `accounting` → `finance`, `economics`, `integrations`, `billing`
- `adoption` → `platform`, `usage`, `guide`, `roles`
- `ai` → `norms`, `production`, `qc`, `warehouse`, `maintenance`, `tooling`, `assistant`, `forecast`
- `announcements` → `dashboard`, `panel`, `support`, `org`
- `api` → `platform`, `orders`, `procurement`, `mdm`
- `assistant` → `registry`, `production`
- `auth` → `dashboard`, `panel`
- `bi` → `production`
- `billing` → `org`, `usage`, `finance`, `integrations`
- `bom` → `production`
- `bugbox` → `remarks`, `issues`, `diagnostics`
- `builder` → `registry`, `hr`, `org`
- `calc` → `registry`, `bom`, `economics`, `assistant`, `orders`
- `calendar` → `planning`, `orders`
- `claims` → `quality`, `issues`, `passport`, `service`
- `client` → `finance`, `tkp`
- `competences` → `roles`
- `config` → `norms`, `calc`, `economics`, `tkp`
- `crm` → `docs`, `finance`, `calendar`, `integrations`
- `dashboard` → `org`, `orders`, `production`, `finance`
- `dealer` → `orders`, `client`
- `departments` → `org`, `roles`
- `diagnostics` → `platform`, `guide`
- `dicts` → `registry`, `builder`, `org`
- `docbuilder` → `bom`, `equipment`, `registry`, `nc`, `qc`, `passport`, `norms`, `economics`, `orders`, `edo`
- `docs` → `procurement`, `service`
- `eam` → `maintenance`, `iiot`, `oee`, `nc`, `equipment`
- `eco` → `guide`, `panel`
- `economics` → `billing`
- `edo` → `files`, `workflow`, `access`, `crm`, `integrations`
- `elearning` → `hr`, `staff`, `safety`, `tasks`
- `equipment` → `crm`, `tkp`, `docs`
- `escrow` → `orders`, `finance`, `teo`, `client`
- `files` → `docs`, `orders`, `norms`, `platform`
- `finance` → `reports`
- `forecast` → `slots`, `production`, `economics`, `maintenance`
- `holding` → `platform`, `finance`, `bi`, `economics`, `reports`
- `hr` → `production`, `mes`, `roles`
- `iiot` → `production`, `nc`, `tooling`, `maintenance`, `integrations`
- `industry` → `bi`, `economics`, `oee`
- `integrations` → `platform`, `support`, `org`
- `issues` → `maintenance`, `orders`
- `itsm` → `support`, `issues`, `access`, `tasks`, `announcements`
- `kedo` → `access`, `docs`, `files`, `integrations`
- `labels` → `orders`, `docs`, `warehouse`
- `lean` → `production`, `issues`, `bi`, `hr`
- `logistics` → `procurement`, `warehouse`, `orders`, `finance`
- `maintenance` → `registry`, `production`, `mes`, `economics`, `warehouse`, `equipment`
- `marketplace` → `procurement`, `production`, `orders`
- `mdm` → `registry`, `bom`, `norms`, `warehouse`, `procurement`, `integrations`
- `mes` → `registry`
- `modules` → `registry`
- `nc` → `registry`, `production`, `mes`, `orders`, `terminal`
- `norms` → `registry`, `calc`, `bom`, `economics`, `production`
- `oee` → `mes`, `tooling`, `bi`
- `onboarding` → `adoption`, `org`, `roles`, `departments`, `guide`, `setup`, `panel`
- `orders` → `supplier`, `registry`
- `panel` → `diagnostics`
- `partners` → `crm`, `orders`, `finance`
- `passport` → `docs`
- `platform` → `workflow`, `dicts`, `registry`
- `plm` → `mdm`, `bom`, `registry`, `docs`, `workflow`, `production`
- `pmo` → `tasks`, `economics`, `projbudget`, `production`
- `procurement` → `finance`, `orders`, `production`
- `projbudget` → `finance`, `economics`, `tasks`, `bi`
- `qc` → `scale`, `workflow`, `files`
- `quality` → `registry`
- `remarks` → `issues`, `files`, `diagnostics`
- `reports` → `bi`, `orders`
- `reverse` → `registry`, `nc`, `production`, `tkp`
- `roles` → `admin`, `panel`
- `safety` → `hr`, `staff`, `tasks`, `workflow`, `warehouse`
- `scale` → `diagnostics`, `platform`, `reports`
- `service` → `maintenance`, `client`, `equipment`, `issues`, `iiot`, `edo`, `integrations`
- `setup` → `production`, `tooling`, `nc`, `forecast`
- `slots` → `production`, `issues`, `registry`
- `staff` → `departments`, `org`
- `suppliers` → `procurement`, `supplier`, `warehouse`, `marketplace`
- `support` → `dashboard`, `issues`, `files`, `org`, `panel`
- `tasks` → `calendar`, `crm`, `orders`, `announcements`, `guide`
- `templates` → `orders`, `client`
- `teo` → `orders`, `economics`, `calc`, `finance`
- `terminal` → `oee`, `tooling`, `issues`
- `tkp` → `orders`, `docs`
- `tooling` → `registry`, `mes`, `procurement`, `production`, `warehouse`, `labels`
- `usage` → `platform`, `scale`, `bi`
- `warehouse` → `registry`, `economics`, `production`, `passport`
- `whitelabel` → `org`, `platform`, `panel`
- `workflow` → `builder`, `access`, `admin`, `orders`, `docs`

> Если для парного сценария нужна обратная связь — добавляйте id в `connects` обоих модулей (только валидные id).
