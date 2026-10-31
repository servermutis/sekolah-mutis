import { h, mount, icon, toast, withBusy, emptyState, skeletons, todayWIB, csvDownload, num } from '../ui.js';
import { db } from '../api.js';
import { S, school } from '../state.js';
import { ATT, ATT_LABEL, loadClasses, classPicker, tabs, firstOfMonth } from './akademik-common.js';

export async function render(root) {
  const classes = await loadClasses();
  const head = h('div', { class: 'page-head' }, h('h1', null, 'Presensi Harian'));
  if (!classes.length) return mount(root, head, emptyState('Belum ada kelas yang dapat Anda akses.', 'Hubungi bagian kurikulum untuk penugasan kelas.'));

  let tab = 'isi', classId = '';
  const body = h('div', { class: 'stack' });
  const tabBar = h('div');
  const cp = classPicker(classes, (id) => { classId = id; load(); });
  classId = cp.sel.value;
  const date = h('input', { class: 'input', type: 'date', value: todayWIB(), max: todayWIB() });
  date.addEventListener('change', () => { if (tab === 'isi') load(); });
  const from = h('input', { class: 'input', type: 'date', value: firstOfMonth(), max: todayWIB() });
  const to = h('input', { class: 'input', type: 'date', value: todayWIB(), max: todayWIB() });
  [from, to].forEach(e => e.addEventListener('change', () => { if (tab === 'rekap') load(); }));
  const lbl = (t, c) => h('div', { class: 'field' }, h('label', null, t), c);

  function drawTabs() { mount(tabBar, tabs([['isi', 'Isi presensi'], ['rekap', 'Rekap']], tab, (k) => { tab = k; drawTabs(); drawFilters(); load(); })); }
  const filters = h('div', { class: 'form-grid two' });
  function drawFilters() { mount(filters, cp.el, tab === 'isi' ? lbl('Tanggal', date) : null, tab === 'rekap' ? lbl('Dari', from) : null, tab === 'rekap' ? lbl('Sampai', to) : null); }

  async function load() {
    mount(body, skeletons(4));
    try { await (tab === 'isi' ? drawEntry() : drawRekap()); }
    catch (e) { mount(body, h('div', { class: 'card err' }, e.message)); }
  }

  async function drawEntry() {
    const cls = classes.find(c => c.id === classId);
    const rows = await db.rpc('list_attendance', { p_class: classId, p_date: date.value });
    if (!rows.length) return mount(body, emptyState('Belum ada siswa aktif pada kelas ini.'));
    const recorded = rows.some(r => r.status);
    const state = new Map(rows.map(r => [r.student_id, { status: r.status || 'hadir', note: r.note || '' }]));
    const canEdit = cls && cls.can_attend;
    const summary = h('div', { class: 'att-summary', role: 'status' });
    const refreshSummary = () => {
      const c = Object.fromEntries(ATT.map(([k]) => [k, 0]));
      state.forEach(v => { c[v.status]++; });
      mount(summary, ATT.map(([k, , l]) => h('span', { class: 'badge att-' + k }, `${l} ${c[k]}`)));
    };
    const list = h('div', { class: 'list' }, rows.map(r => {
      const st = state.get(r.student_id);
      const btns = h('div', { class: 'seg', role: 'group', 'aria-label': 'Status ' + r.full_name });
      const noteIn = h('input', { class: 'input small-in', type: 'text', maxlength: 200, placeholder: 'Keterangan (opsional)', value: st.note, 'aria-label': 'Keterangan ' + r.full_name });
      noteIn.addEventListener('input', () => { st.note = noteIn.value; });
      const paint = () => {
        mount(btns, ATT.map(([k, short, label]) => h('button', {
          type: 'button', class: 'att-' + k, 'aria-pressed': st.status === k ? 'true' : 'false', 'aria-label': label, title: label, disabled: canEdit ? null : true,
          onclick: () => { st.status = k; paint(); refreshSummary(); } }, short)));
        noteIn.hidden = st.status === 'hadir';
      };
      paint();
      return h('div', { class: 'item att-row' }, h('div', { class: 'top' }, h('div', null, h('div', { class: 'name' }, r.full_name), h('div', { class: 'small muted' }, 'NIS ' + r.nis)), btns), noteIn);
    }));
    refreshSummary();
    const allPresent = h('button', { class: 'btn ghost small', type: 'button', onclick: () => { state.forEach(v => { v.status = 'hadir'; v.note = ''; }); render2(); } }, icon('check', 16), 'Semua hadir');
    const save = h('button', { class: 'btn', type: 'button', onclick: () => withBusy(save, async () => {
      try {
        await db.rpc('save_attendance', { p_class: classId, p_date: date.value, p_entries: rows.map(r => { const v = state.get(r.student_id); return { student_id: r.student_id, status: v.status, note: v.status === 'hadir' ? null : (v.note || null) }; }) });
        toast('Presensi tersimpan.'); load();
      } catch (e) { toast(e.message, 'err'); }
    }) }, icon('check', 18), 'Simpan presensi');
    const render2 = () => drawEntry();
    mount(body,
      !canEdit ? h('div', { class: 'notice' }, 'Anda hanya dapat melihat presensi kelas ini. Presensi harian diisi oleh wali kelas atau petugas kesiswaan.') : null,
      !recorded && canEdit ? h('div', { class: 'notice' }, 'Presensi tanggal ini belum diisi. Semua siswa diset "Hadir"; ubah yang tidak hadir lalu simpan.') : null,
      h('div', { class: 'row between wrap' }, summary, canEdit ? allPresent : null),
      list,
      canEdit ? h('div', { class: 'sticky-actions' }, save) : null);
  }

  async function drawRekap() {
    const rows = await db.rpc('attendance_summary', { p_class: classId, p_from: from.value || null, p_to: to.value || null });
    if (!rows.length) return mount(body, emptyState('Tidak ada data.'));
    const pct = (r) => (Number(r.hari) ? Math.round(((Number(r.hadir) + Number(r.terlambat)) / Number(r.hari)) * 100) + '%' : '–');
    const csv = () => csvDownload(`presensi-${school().code}-${from.value}-${to.value}.csv`,
      [['NIS', 'Nama', 'Hadir', 'Izin', 'Sakit', 'Alpa', 'Terlambat', 'Hari tercatat', '% hadir'], ...rows.map(r => [r.nis, r.full_name, r.hadir, r.izin, r.sakit, r.alpa, r.terlambat, r.hari, pct(r)])]);
    mount(body,
      h('div', { class: 'row between' }, h('p', { class: 'small muted' }, `${num(rows.length)} siswa`), h('button', { class: 'btn ghost small', type: 'button', onclick: csv }, icon('download', 16), 'CSV')),
      h('div', { class: 'table-wrap' }, h('table', { class: 'tbl' },
        h('thead', null, h('tr', null, h('th', null, 'Nama'), ...ATT.map(([k, s, l]) => h('th', { class: 'num', title: l }, s)), h('th', { class: 'num' }, '% hadir'))),
        h('tbody', null, rows.map(r => h('tr', null, h('td', null, h('b', null, r.full_name), h('div', { class: 'small muted' }, r.nis)),
          ...ATT.map(([k]) => h('td', { class: 'num' }, num(r[k]))), h('td', { class: 'num' }, pct(r))))))),
      h('p', { class: 'small muted' }, 'H = hadir, I = izin, S = sakit, A = alpa, T = terlambat. Persen hadir menghitung hadir + terlambat.'));
  }

  mount(root, head, tabBar, h('div', { class: 'card flat' }, filters), body);
  drawTabs(); drawFilters(); load();
}
