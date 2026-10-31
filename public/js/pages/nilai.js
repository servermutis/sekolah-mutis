import { h, mount, icon, modal, field, toast, withBusy, emptyState, skeletons, badge, csvDownload, confirmDialog, num } from '../ui.js';
import { db, eq } from '../api.js';
import { S, school } from '../state.js';
import { loadClasses, classPicker, semesterPicker, tabs, fmtScore } from './akademik-common.js';

export async function render(root) {
  const [assignments, classes] = await Promise.all([db.rpc('my_assignments', { p_school: S.schoolId }), loadClasses()]);
  const head = h('div', { class: 'page-head' }, h('h1', null, 'Nilai'));
  if (!S.year || !S.semesters.length) return mount(root, head, h('div', { class: 'notice' }, 'Belum ada tahun ajaran/semester aktif untuk unit ini.'));
  if (!assignments.length && !classes.length) return mount(root, head, emptyState('Belum ada kelas atau penugasan mengajar untuk Anda.', 'Hubungi bagian kurikulum.'));

  let tab = assignments.length ? 'input' : 'rekap';
  const body = h('div', { class: 'stack' });
  const tabBar = h('div');
  const drawTabs = () => mount(tabBar, assignments.length && classes.length ? tabs([['input', 'Input nilai'], ['rekap', 'Rekap kelas']], tab, (k) => { tab = k; drawTabs(); start(); }) : null);
  async function start() { mount(body, skeletons(3)); try { await (tab === 'input' ? inputView(body, assignments) : rekapView(body, classes)); } catch (e) { mount(body, h('div', { class: 'card err' }, e.message)); } }
  mount(root, head, tabBar, body); drawTabs(); start();
}

// ---------------- Input nilai (guru mapel) ----------------
async function inputView(body, assignments) {
  const asgSel = h('select', { class: 'input' }, assignments.map(a => h('option', { value: a.id }, `${a.class_name} — ${a.subject_name}`)));
  try { const k = localStorage.getItem('ymic.asg'); if (assignments.some(a => a.id === k)) asgSel.value = k; } catch { /* */ }
  const sem = semesterPicker(() => load());
  const out = h('div', { class: 'stack' });
  asgSel.addEventListener('change', () => { try { localStorage.setItem('ymic.asg', asgSel.value); } catch { /* */ } load(); });
  mount(body, h('div', { class: 'card flat' }, h('div', { class: 'form-grid two' }, field('Kelas & mata pelajaran', asgSel), sem.el)), out);

  async function load() {
    mount(out, skeletons(3));
    const asg = assignments.find(a => a.id === asgSel.value);
    const [roster, comps, grades, recap] = await Promise.all([
      db.rpc('class_roster', { p_class: asg.class_id }),
      db.select('assessment_components', { select: 'id,code,name,weight,sort_order', academic_year_id: eq(S.year.id), order: 'sort_order.asc' }),
      db.rpc('list_grades', { p_assignment: asg.id, p_semester: sem.sel.value }),
      db.rpc('rekap_nilai', { p_class: asg.class_id, p_semester: sem.sel.value }),
    ]);
    if (!comps.length) return mount(out, h('div', { class: 'notice' }, 'Komponen penilaian belum diatur. Minta bagian kurikulum mengaturnya di menu Akademik.'));
    const gmap = new Map(grades.map(g => [`${g.student_id}|${g.component_id}|${g.title}`, g.score]));
    const cols = []; // [{comp,title,filled}]
    const seen = new Map();
    for (const g of grades) {
      const k = g.component_id + '|' + g.title;
      if (!seen.has(k)) { const c = { comp: comps.find(x => x.id === g.component_id), title: g.title, filled: 0 }; seen.set(k, c); cols.push(c); }
      seen.get(k).filled++;
    }
    cols.sort((a, b) => (a.comp?.sort_order ?? 0) - (b.comp?.sort_order ?? 0) || a.title.localeCompare(b.title, 'id', { numeric: true }));
    const mine = recap.filter(r => r.assignment_id === asg.id);
    const totalW = comps.reduce((a, c) => a + c.weight, 0);

    const open = (comp, title) => openEntry({ asg, semId: sem.sel.value, comp, title, roster, gmap, onDone: load });
    const chips = h('div', { class: 'row wrap' }, cols.map(c => h('button', { class: 'tab', type: 'button', onclick: () => open(c.comp, c.title) }, `${c.comp?.code || '?'} · ${c.title}`, h('span', { class: 'n' }, `${c.filled}/${roster.length}`))));
    const add = h('button', { class: 'btn gold', type: 'button', onclick: () => addDialog() }, icon('plus', 18), 'Tambah penilaian');
    function addDialog() {
      const cs = h('select', { class: 'input' }, comps.map(c => h('option', { value: c.id }, `${c.name} (${c.weight}%)`)));
      const ti = h('input', { class: 'input', type: 'text', maxlength: 60 });
      const err = h('div', { class: 'err', role: 'alert' });
      const suggest = () => { const c = comps.find(x => x.id === cs.value); const n = cols.filter(x => x.comp?.id === cs.value).length + 1; ti.value = c ? (c.code === 'UTS' || c.code === 'UAS' ? c.code : `${c.code} ${n}`) : ''; };
      cs.addEventListener('change', suggest); suggest();
      const go = h('button', { class: 'btn', type: 'button', onclick: () => {
        const t = ti.value.trim();
        if (!t) { err.textContent = 'Isi judul penilaian.'; return; }
        const c = comps.find(x => x.id === cs.value); m.close(); open(c, t);
      } }, 'Lanjut isi nilai');
      const m = modal({ title: 'Tambah penilaian', body: [field('Komponen', cs, 'Bobot komponen diatur bagian kurikulum.'), field('Judul', ti, 'Contoh: UH 1, Tugas 2, UTS.'), err], actions: [h('button', { class: 'btn ghost', type: 'button', onclick: () => m.close() }, 'Batal'), go] });
    }

    const tbl = h('div', { class: 'table-wrap' }, h('table', { class: 'tbl' },
      h('thead', null, h('tr', null, h('th', null, 'Nama'), h('th', { class: 'num' }, 'Nilai akhir'), h('th', null, 'Predikat'), h('th', null, 'Status'))),
      h('tbody', null, mine.map(r => h('tr', null, h('td', null, h('b', null, r.full_name), h('div', { class: 'small muted' }, r.nis)),
        h('td', { class: 'num' }, fmtScore(r.final_score)), h('td', null, r.predikat || '–'),
        h('td', null, r.final_score === null ? badge('Belum ada nilai', 'gray') : !r.lengkap ? badge('Belum lengkap', 'gold') : r.tuntas ? badge('Tuntas', 'ringan') : badge('Belum tuntas', 'red')))))));
    mount(out,
      totalW !== 100 ? h('div', { class: 'notice' }, `Total bobot komponen ${totalW}% (seharusnya 100%). Hubungi bagian kurikulum.`) : null,
      h('div', { class: 'card' }, h('div', { class: 'row between wrap' }, h('h2', null, 'Penilaian'), add),
        cols.length ? chips : h('p', { class: 'muted' }, 'Belum ada penilaian. Ketuk "Tambah penilaian".'),
        h('p', { class: 'small muted' }, `KKM ${asg.kkm}. Nilai akhir = rata-rata tiap komponen dikali bobotnya (${comps.map(c => `${c.code} ${c.weight}%`).join(', ')}).`)),
      mine.length ? tbl : emptyState('Belum ada siswa di kelas ini.'));
  }
  await load();
}

function openEntry({ asg, semId, comp, title, roster, gmap, onDone }) {
  const inputs = new Map();
  const rows = roster.map(r => {
    const cur = gmap.get(`${r.student_id}|${comp.id}|${title}`);
    const inp = h('input', { class: 'input score-in', type: 'number', inputmode: 'decimal', min: 0, max: 100, step: '0.01', value: cur === undefined ? '' : String(cur), 'aria-label': 'Nilai ' + r.full_name });
    inputs.set(r.student_id, inp);
    return h('div', { class: 'item row between' }, h('div', null, h('div', { class: 'name' }, r.full_name), h('div', { class: 'small muted' }, 'NIS ' + r.nis)), inp);
  });
  const err = h('div', { class: 'err', role: 'alert' });
  const collect = (clear) => roster.map(r => ({ student_id: r.student_id, score: clear ? null : (inputs.get(r.student_id).value.trim() === '' ? null : Number(inputs.get(r.student_id).value.replace(',', '.'))) }));
  const save = h('button', { class: 'btn', type: 'button', onclick: () => withBusy(save, async () => {
    err.textContent = '';
    const scores = collect(false);
    if (scores.some(s => s.score !== null && (!Number.isFinite(s.score) || s.score < 0 || s.score > 100))) { err.textContent = 'Nilai harus berupa angka 0–100.'; return; }
    try { await db.rpc('save_grades', { p_assignment: asg.id, p_semester: semId, p_component: comp.id, p_title: title, p_scores: scores }); toast('Nilai tersimpan.'); m.close(); onDone(); }
    catch (e) { err.textContent = e.message; }
  }) }, 'Simpan nilai');
  const del = h('button', { class: 'btn ghost', type: 'button', onclick: async () => {
    if (!(await confirmDialog({ title: 'Hapus penilaian', message: `Hapus semua nilai "${title}" untuk kelas ini?`, confirmText: 'Hapus', danger: true }))) return;
    try { await db.rpc('save_grades', { p_assignment: asg.id, p_semester: semId, p_component: comp.id, p_title: title, p_scores: collect(true) }); toast('Penilaian dihapus.'); m.close(); onDone(); }
    catch (e) { err.textContent = e.message; }
  } }, 'Hapus');
  const m = modal({ title: `${asg.class_name} • ${asg.subject_name}`, wide: true, body: [
    h('p', { class: 'small muted' }, `${comp.name} (${comp.weight}%) — ${title}. Kosongkan kolom untuk siswa yang belum dinilai.`), h('div', { class: 'list' }, rows), err],
    actions: [del, save] });
}

// ---------------- Rekap kelas ----------------
async function rekapView(body, classes) {
  const out = h('div', { class: 'stack' });
  const cp = classPicker(classes, () => load());
  const sem = semesterPicker(() => load());
  mount(body, h('div', { class: 'card flat' }, h('div', { class: 'form-grid two' }, cp.el, sem.el)), out);
  async function load() {
    mount(out, skeletons(3));
    try {
      const rows = await db.rpc('rekap_nilai', { p_class: cp.sel.value, p_semester: sem.sel.value });
      if (!rows.length) return mount(out, emptyState('Belum ada data penilaian atau penugasan untuk kelas ini.'));
      const subjects = [...new Map(rows.map(r => [r.subject_id, { id: r.subject_id, name: r.subject_name, kkm: r.kkm }])).values()];
      const byStudent = new Map();
      rows.forEach(r => { if (!byStudent.has(r.student_id)) byStudent.set(r.student_id, { nis: r.nis, name: r.full_name, cells: {} }); byStudent.get(r.student_id).cells[r.subject_id] = r; });
      const list = [...byStudent.values()];
      const avg = (s) => { const v = Object.values(s.cells).filter(c => c.final_score !== null).map(c => Number(c.final_score)); return v.length ? v.reduce((a, b) => a + b, 0) / v.length : null; };
      const csv = () => csvDownload(`nilai-${school().code}-${cp.sel.selectedOptions[0].textContent}.csv`, [['NIS', 'Nama', ...subjects.map(s => s.name), 'Rata-rata'], ...list.map(s => [s.nis, s.name, ...subjects.map(x => s.cells[x.id]?.final_score ?? ''), avg(s) === null ? '' : avg(s).toFixed(2)])]);
      mount(out,
        h('div', { class: 'row between' }, h('p', { class: 'small muted' }, `${num(list.length)} siswa • ${subjects.length} mata pelajaran`), h('button', { class: 'btn ghost small', type: 'button', onclick: csv }, icon('download', 16), 'CSV')),
        h('div', { class: 'table-wrap' }, h('table', { class: 'tbl' },
          h('thead', null, h('tr', null, h('th', null, 'Nama'), ...subjects.map(s => h('th', { class: 'num', title: 'KKM ' + s.kkm }, s.name)), h('th', { class: 'num' }, 'Rata-rata'))),
          h('tbody', null, list.map(s => h('tr', null, h('td', null, h('b', null, s.name), h('div', { class: 'small muted' }, s.nis)),
            ...subjects.map(x => { const c = s.cells[x.id]; return h('td', { class: 'num' }, !c || c.final_score === null ? '–' : badge(fmtScore(c.final_score) + (c.lengkap ? '' : '*'), c.tuntas ? 'ringan' : 'red')); }),
            h('td', { class: 'num' }, avg(s) === null ? '–' : fmtScore(avg(s)))))))),
        h('p', { class: 'small muted' }, 'Merah = di bawah KKM. Tanda * = komponen penilaian belum lengkap (nilai sementara).'));
    } catch (e) { mount(out, h('div', { class: 'card err' }, e.message)); }
  }
  await load();
}
