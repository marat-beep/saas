/* ============================================================
   B21 · Режимы резания
   расчёт S/F, MRR и проверка нагрузки по мощности станка
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  // базовая скорость резания Vc (м/мин) по материалу заготовки и материалу инструмента
  var VC = {
    steel: { hss: 25, carbide: 140 },
    ss: { hss: 15, carbide: 90 },
    al: { hss: 90, carbide: 320 },
    ti: { hss: 10, carbide: 55 },
    cast: { hss: 30, carbide: 160 }
  };
  // удельная энергия резания, кВт на 1 см³/мин (приближённо)
  var KC = { steel: 0.032, ss: 0.042, al: 0.012, ti: 0.055, cast: 0.028 };
  var MATS = { steel: 'Сталь конструкционная', ss: 'Нержавеющая сталь', al: 'Алюминий', ti: 'Титан', cast: 'Чугун' };

  var params = { mat: 'steel', tool: 'carbide', op: 0.8, d: 12, z: 4, ap: 2, ae: 6, pw: 15 };
  var result = null;

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  $('#mat').innerHTML = Object.keys(MATS).map(function (k) { return '<option value="' + k + '">' + MATS[k] + '</option>'; }).join('');
  $('#tool').innerHTML = '<option value="carbide">Твёрдый сплав</option><option value="hss">HSS</option>';

  $('#mat').addEventListener('change', function () { params.mat = this.value; });
  $('#tool').addEventListener('change', function () { params.tool = this.value; });
  ['d', 'z', 'ap', 'ae', 'pw'].forEach(function (id) { $('#' + id).addEventListener('input', function () { params[id] = parseFloat(this.value) || 0; }); });
  $('#op').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    $$('button', this).forEach(function (x) { x.classList.toggle('active', x === b); });
    params.op = parseFloat(b.dataset.k);
  });

  function calculate() {
    var D = Math.max(1, params.d), Z = Math.max(1, params.z);
    var Vc = (VC[params.mat] && VC[params.mat][params.tool] || 100) * params.op;
    var n = Math.round(Vc * 1000 / (Math.PI * D)); // об/мин
    var fz = 0.02 + D * 0.004;                    // мм/зуб (упрощённо)
    var Vf = Math.round(n * fz * Z);              // мм/мин
    var mrr = (params.ap * params.ae * Vf) / 1000; // см³/мин
    var Pc = mrr * (KC[params.mat] || 0.03);       // кВт
    result = { Vc: Vc, n: n, fz: fz, Vf: Vf, mrr: mrr, Pc: Pc, over: Pc > params.pw };

    $('#nOut').textContent = App.number(n) + ' об/мин';
    $('#vcOut').textContent = 'Vc ' + App.number(Vc) + ' м/мин · ' + MATS[params.mat] + ' / ' + (params.tool === 'carbide' ? 'твёрдый сплав' : 'HSS');
    $('#resGrid').innerHTML =
      cell(App.number(Vf) + ' мм/мин', 'Подача Vf') +
      cell(fz.toFixed(3) + ' мм', 'Подача на зуб fz') +
      cell(App.number(mrr, 1) + ' см³/мин', 'Съём MRR') +
      cell(Pc.toFixed(1) + ' кВт', 'Мощность Pc');
    $('#verdict').innerHTML = result.over
      ? '<div class="callout danger"><span class="ci">⚠️</span><div>Требуемая мощность ' + Pc.toFixed(1) + ' кВт выше мощности станка (' + params.pw + ' кВт). Уменьшите ap/ae или частоту.</div></div>'
      : '<div class="callout success"><span class="ci">✅</span><div>Режимы в пределах мощности станка (' + params.pw + ' кВт). Загрузка ≈ ' + Math.round(Pc / params.pw * 100) + '%.</div></div>';
    screens.go('s2');
  }
  function cell(v, l) { return '<div class="res-cell"><b>' + v + '</b><span>' + l + '</span></div>'; }

  $('#calcBtn').addEventListener('click', calculate);
  $('#saveBtn').addEventListener('click', function () {
    var num = 'CUT-' + App.pad(Math.floor(1 + Math.random() * 999), 3);
    App.Store.set('cuttingModes', (App.Store.get('cuttingModes', [])).concat([{ num: num, mat: params.mat, n: result.n, vf: result.Vf, created: App.today() }]));
    $('#actNum').textContent = num;
    screens.go('s3'); App.toast('Режимы ' + num + ' сохранены');
  });
  $('#editBtn').addEventListener('click', function () { screens.go('s1'); });
  $('#againBtn').addEventListener('click', function () { screens.go('s1'); });
  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });
})();
