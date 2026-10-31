// Pengaturan akademik (bagian kurikulum): mata pelajaran, penugasan guru, komponen nilai, jam pelajaran.
import { h, mount, icon, modal, field, toast, withBusy, emptyState, skeletons, badge, confirmDialog } from '../ui.js';
import { db, eq } from '../api.js';
import { S, can } from '../state.js';
import { loadClasses, classPicker, tabs, hhmm } from './akademik-common.js';

const EDIT = ['admin_sekolah', 'kurikulum'];
const asDbError = (e) => (/foreign key|violates/i.test(e.message || '') ? 'Data ini sudah dipakai (nilai/jadwal) sehingga tidak dapat dihapus. Nonaktifkan saja bila perlu.' : e.message);

export async function render(root) {
  const edit = can(...EDIT);
  let tab = 'mapel';
  const body = h('div', { class: 'stack' }), tabBar = h('div');
  const views = { mapel: subjectsView, tugas: assignmentsView, komponen: componentsView, jam: periodsView };
  const drawTabs = () => mount(tabBar, tabs([['mapel', 'Mata pelajaran'], ['tugas', 'Penugasan guru'], ['komponen', 'Komponen nilai'], ['jam', 'Jam pelajaran']], tab, (k) => { tab = k; drawTabs(); go(); }));
  async function go() { mount(body, skeletons(3)); try { await views[tab](body, edit); } catch (e) { mount(body, h('div', { class: 'card err' }, e.message)); } }
  mount(root, h('div', { class: 'page-head' }, h('h1', null, 'Akademik')), !edit ? h('div', { class: 'notice' }, 'Anda hanya dapat melihat pengaturan akademik.') : null, tabBar, body);
  drawTabs(); go();
}

const input = (type, value, extra = {}) => h('input', { class: 'input', type, value: value ?? '', ...extra });
const cancelBtn = (get) => h('button', { class: 'btn ghost', type: 'button', onclick: () => get().close() }, 'Batal');

// ------------------------------------------------ Mata pelajaran
async function subjectsView(body, edit) {
  const rows = await db.select('subjects', { select: 'id,code,name,kkm,status', school_id: eq(S.schoolId), order: 'name.asc' });
  const dlg = (s) => {
    const code = input('text', s?.code, { maxlength: 20, placeholder: 'MTK', readonly: s ? true : null });
    const name = input('text', s?.name, { maxlength: 80 }), kkm = input('number', s ? s.kkm : 75, { min: 0, max: 100 });
    const st = h('select', { class: 'input' }, h('option', { value: 'aktif' }, 'Aktif'), h('option', { value: 'nonaktif' }, 'Nonaktif')); st.value = s?.status || 'aktif';
    const err = h('div', { class: 'err', role: 'alert' });
    const save = h('button', { class: 'btn', type: 'button', onclick: () => withBusy(save, async () => {
      err.textContent = '';
      const v = { code: code.value.trim().toUpperCase(), name: name.value.trim(), kkm: Number(kkm.value), status: st.value };
      if (!/^[A-Z0-9._-]{2,20}$/.test(v.code)) { err.textContent = 'Kode 2-20 karakter (huruf besar/angka).'; return; }
      if (v.name.length < 2) { err.textContent = 'Isi nama mata pelajaran.'; return; }
      if (!(v.kkm >= 0 && v.kkm <= 100)) { err.textContent = 'KKM harus 0-100.'; return; }
      try { if (s) await db.update('subjects', { id: eq(s.id) }, { name: v.name, kkm: v.kkm, status: v.status }); else await db.insert('subjects', [{ school_id: S.schoolId, ...v }]); toast('Tersimpan.'); m.close(); subjectsView(body, edit).catch(() => {}); }
      catch (e) { err.textContent = /duplicate|unique/i.test(e.message) ? 'Kode sudah dipakai.' : e.message; }
    }) }, 'Simpan');
    const m = modal({ title: s ? 'Ubah mata pelajaran' : 'Tambah mata pelajaran', body: [field('Kode', code), field('Nama', name), field('KKM', kkm, 'Batas ketuntasan minimal.'), field('Status', st), err], actions: [cancelBtn(() => m), save] });
  };
  mount(body, edit ? h('div', { class: 'row' }, h('button', { class: 'btn gold', type: 'button', onclick: () => dlg(null) }, icon('plus', 18), 'Tambah mata pelajaran')) : null,
    rows.length ? h('div', { class: 'list' }, rows.map(s => h(edit ? 'button' : 'div', { class: 'item', type: edit ? 'button' : null, onclick: edit ? () => dlg(s) : null },
      h('div', { class: 'top' }, h('div', { class: 'name' }, s.name), badge(s.status === 'aktif' ? 'Aktif' : 'Nonaktif', s.status === 'aktif' ? 'ringan' : 'gray')), h('div', { class: 'small muted' }, `${s.code} • KKM ${s.kkm}`))))
      : emptyState('Belum ada mata pelajaran.'));
}

// ------------------------------------------------ Penugasan guru
async function assignmentsView(body, edit) {
  const classes = await loadClasses();
  if (!classes.length) return mount(body, emptyState('Belum ada kelas pada tahun ajaran aktif.', 'Buat kelas di menu Master Data.'));
  const out = h('div', { class: 'stack' });
  const cp = classPicker(classes, () => load());
  mount(body, h('div', { class: 'card flat' }, cp.el), out);
  async function load() {
    mount(out, skeletons(3));
    try {
      const classId = cp.sel.value;
      const rows = await db.rpc('list_assignments', { p_class: classId });
      const dlg = async (a) => {
        const [subjects, teachers] = await Promise.all([db.select('subjects', { select: 'id,name,status', school_id: eq(S.schoolId), status: 'eq.aktif', order: 'name.asc' }), db.rpc('list_teachers', { p_school: S.schoolId })]);
        const used = new Set(rows.map(r => r.subject_id));
        const subs = subjects.filter(s => !used.has(s.id) || (a && a.subject_id === s.id));
        const sub = h('select', { class: 'input', disabled: a ? true : null }, subs.map(s => h('option', { value: s.id }, s.name)));
        const tea = h('select', { class: 'input' }, teachers.map(t => h('option', { value: t.user_id }, t.full_name)));
        const hrs = input('number', a ? a.hours_per_week : 2, { min: 1, max: 40 });
        if (a) { sub.value = a.subject_id; tea.value = a.teacher_id; }
        const err = h('div', { class: 'err', role: 'alert' });
        if (!teachers.length) err.textContent = 'Belum ada pengguna berperan Guru/Wali Kelas pada unit ini (tambahkan di menu Pengguna).';
        if (!subs.length && !a) err.textContent = 'Semua mata pelajaran aktif sudah ditugaskan pada kelas ini.';
        const save = h('button', { class: 'btn', type: 'button', onclick: () => withBusy(save, async () => {
          try {
            if (a) await db.update('teaching_assignments', { id: eq(a.id) }, { teacher_id: tea.value, hours_per_week: Number(hrs.value) });
            else await db.insert('teaching_assignments', [{ school_id: S.schoolId, academic_year_id: S.year.id, class_id: classId, subject_id: sub.value, teacher_id: tea.value, hours_per_week: Number(hrs.value) }]);
            toast('Penugasan tersimpan.'); m.close(); load();
          } catch (e) { err.textContent = e.message; }
        }) }, 'Simpan');
        const del = a ? h('button', { class: 'btn ghost', type: 'button', onclick: async () => {
          if (!(await confirmDialog({ title: 'Hapus penugasan', message: `Hapus penugasan ${a.subject_name} di kelas ini?`, confirmText: 'Hapus', danger: true }))) return;
          try { await db.remove('teaching_assignments', { id: eq(a.id) }); toast('Penugasan dihapus.'); m.close(); load(); } catch (e) { err.textContent = asDbError(e); }
        } }, 'Hapus') : null;
        const m = modal({ title: a ? 'Ubah penugasan' : 'Tambah penugasan', body: [field('Mata pelajaran', sub), field('Guru pengampu', tea), field('Jam per minggu', hrs), err], actions: [del, cancelBtn(() => m), save] });
      };
      mount(out, edit ? h('div', { class: 'row' }, h('button', { class: 'btn gold', type: 'button', onclick: () => dlg(null).catch(e => toast(e.message, 'err')) }, icon('plus', 18), 'Tambah penugasan')) : null,
        rows.length ? h('div', { class: 'list' }, rows.map(a => h(edit ? 'button' : 'div', { class: 'item', type: edit ? 'button' : null, onclick: edit ? () => dlg(a).catch(e => toast(e.message, 'err')) : null },
          h('div', { class: 'top' }, h('div', { class: 'name' }, a.subject_name), badge(`${a.hours_per_week} jam/minggu`, 'gray')), h('div', { class: 'small muted' }, 'Pengampu: ' + (a.teacher_name || '-') + ` • KKM ${a.kkm}`))))
          : emptyState('Belum ada penugasan guru pada kelas ini.'));
    } catch (e) { mount(out, h('div', { class: 'card err' }, e.message)); }
  }
  await load();
}

// ------------------------------------------------ Komponen nilai
async function componentsView(body, edit) {
  if (!S.year) return mount(body, h('div', { class: 'notice' }, 'Belum ada tahun ajaran aktif.'));
  const rows = await db.select('assessment_components', { select: 'id,code,name,weight,sort_order', academic_year_id: eq(S.year.id), order: 'sort_order.asc' });
  const total = rows.reduce((a, r) => a + r.weight, 0);
  const dlg = (c) => {
    const code = input('text', c?.code, { maxlength: 12, placeholder: 'UH', readonly: c ? true : null });
    const name = input('text', c?.name, { maxlength: 60 }), w = input('number', c ? c.weight : 10, { min: 1, max: 100 });
    const ord = input('number', c ? c.sort_order : rows.length + 1, { min: 0, max: 99 });
    const err = h('div', { class: 'err', role: 'alert' });
    const save = h('button', { class: 'btn', type: 'button', onclick: () => withBusy(save, async () => {
      err.textContent = '';
      const v = { code: code.value.trim().toUpperCase(), name: name.value.trim(), weight: Number(w.value), sort_order: Number(ord.value) };
      if (!/^[A-Z0-9._-]{1,12}$/.test(v.code)) { err.textContent = 'Kode 1-12 karakter (huruf besar/angka).'; return; }
      if (v.name.length < 2) { err.textContent = 'Isi nama komponen.'; return; }
      if (!(v.weight >= 1 && v.weight <= 100)) { err.textContent = 'Bobot 1-100.'; return; }
      try { if (c) await db.update('assessment_components', { id: eq(c.id) }, { name: v.name, weight: v.weight, sort_order: v.sort_order }); else await db.insert('assessment_components', [{ school_id: S.schoolId, academic_year_id: S.year.id, ...v }]); toast('Tersimpan.'); m.close(); componentsView(body, edit).catch(() => {}); }
      catch (e) { err.textContent = /duplicate|unique/i.test(e.message) ? 'Kode sudah dipakai.' : e.message; }
    }) }, 'Simpan');
    const del = c ? h('button', { class: 'btn ghost', type: 'button', onclick: async () => {
      if (!(await confirmDialog({ title: 'Hapus komponen', message: `Hapus komponen ${c.name}?`, confirmText: 'Hapus', danger: true }))) return;
      try { await db.remove('assessment_components', { id: eq(c.id) }); toast('Komponen dihapus.'); m.close(); componentsView(body, edit).catch(() => {}); } catch (e) { err.textContent = asDbError(e); }
    } }, 'Hapus') : null;
    const m = modal({ title: c ? 'Ubah komponen' : 'Tambah komponen', body: [field('Kode', code), field('Nama', name), field('Bobot (%)', w), field('Urutan', ord), err], actions: [del, cancelBtn(() => m), save] });
  };
  mount(body,
    h('div', { class: 'card flat' }, h('div', { class: 'row between' }, h('b', null, `Tahun ajaran ${S.year.year_name}`), badge(`Total bobot ${total}%`, total === 100 ? 'ringan' : 'red')),
      h('div', { class: 'weight-bar' }, h('i', { style: { width: Math.min(total, 100) + '%' } })),
      total !== 100 ? h('p', { class: 'small', style: { color: 'var(--danger)' } }, 'Total bobot sebaiknya tepat 100%. Nilai akhir tetap dihitung proporsional atas komponen yang terisi.') : null),
    edit ? h('div', { class: 'row' }, h('button', { class: 'btn gold', type: 'button', onclick: () => dlg(null) }, icon('plus', 18), 'Tambah komponen')) : null,
    rows.length ? h('div', { class: 'list' }, rows.map(c => h(edit ? 'button' : 'div', { class: 'item', type: edit ? 'button' : null, onclick: edit ? () => dlg(c) : null },
      h('div', { class: 'top' }, h('div', { class: 'name' }, `${c.name} (${c.code})`), badge(c.weight + '%', 'gold'))))) : emptyState('Belum ada komponen penilaian.'),
    h('p', { class: 'small muted' }, 'Setiap guru dapat membuat beberapa penilaian dalam satu komponen (mis. UH 1, UH 2); nilainya dirata-rata lalu dikalikan bobot.'));
}

// ------------------------------------------------ Jam pelajaran
async function periodsView(body, edit) {
  const rows = await db.select('lesson_periods', { select: 'id,period,start_time,end_time', school_id: eq(S.schoolId), order: 'period.asc' });
  const rowEl = (r) => {
    const a = input('time', hhmm(r.start_time)), b = input('time', hhmm(r.end_time));
    const save = h('button', { class: 'btn ghost small', type: 'button', onclick: () => withBusy(save, async () => {
      if (!a.value || !b.value || b.value <= a.value) { toast('Jam selesai harus setelah jam mulai.', 'err'); return; }
      try { await db.update('lesson_periods', { id: eq(r.id) }, { start_time: a.value, end_time: b.value }); toast(`Jam ke-${r.period} tersimpan.`); } catch (e) { toast(e.message, 'err'); }
    }) }, 'Simpan');
    return h('div', { class: 'item row between wrap' }, h('b', null, `Jam ke-${r.period}`), edit ? h('div', { class: 'row wrap' }, a, h('span', null, '–'), b, save) : h('span', null, `${hhmm(r.start_time)}–${hhmm(r.end_time)}`));
  };
  const add = h('button', { class: 'btn gold', type: 'button', onclick: () => withBusy(add, async () => {
    const n = (rows.at(-1)?.period || 0) + 1;
    if (n > 15) { toast('Maksimal 15 jam pelajaran.', 'err'); return; }
    const prev = rows.at(-1);
    try { await db.insert('lesson_periods', [{ school_id: S.schoolId, period: n, start_time: prev ? hhmm(prev.end_time) : '07:00', end_time: prev ? addMin(hhmm(prev.end_time), 40) : '07:40' }]); toast('Jam ditambahkan.'); periodsView(body, edit).catch(() => {}); } catch (e) { toast(e.message, 'err'); }
  }) }, icon('plus', 18), 'Tambah jam ke-' + ((rows.at(-1)?.period || 0) + 1));
  mount(body, edit ? h('div', { class: 'row' }, add) : null, rows.length ? h('div', { class: 'list' }, rows.map(rowEl)) : emptyState('Belum ada jam pelajaran.'), h('p', { class: 'small muted' }, 'Jam pelajaran dipakai pada grid jadwal. Atur jam istirahat dengan melewatkan rentang waktunya.'));
}
function addMin(t, m) { const [hh, mm] = t.split(':').map(Number); const x = hh * 60 + mm + m; return `${String(Math.floor(x / 60) % 24).padStart(2, '0')}:${String(x % 60).padStart(2, '0')}`; }
