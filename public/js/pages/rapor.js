import { h, mount, icon, modal, field, toast, withBusy, emptyState, skeletons, badge, confirmDialog, num } from '../ui.js';
import { db } from '../api.js';
import { S, can, school } from '../state.js';
import { loadClasses, classPicker, semesterPicker, REPORT_STATUS, fmtScore } from './akademik-common.js';

const CURRICULUM = ['admin_sekolah', 'kurikulum'];
const PUBLISHERS = ['admin_sekolah', 'kurikulum', 'kepala_sekolah'];

export async function render(root) {
  const classes = await loadClasses();
  const head = h('div', { class: 'page-head' }, h('h1', null, 'Rapor'));
  if (!S.year || !S.semesters.length) return mount(root, head, h('div', { class: 'notice' }, 'Belum ada tahun ajaran/semester aktif untuk unit ini.'));
  const viewable = classes.filter(c => c.is_wali || can('kepala_sekolah', ...CURRICULUM));
  if (!viewable.length) return mount(root, head, emptyState('Rapor hanya dapat dilihat oleh wali kelas, bagian kurikulum, dan kepala sekolah.'));

  const out = h('div', { class: 'stack' });
  const cp = classPicker(viewable, () => load());
  const sem = semesterPicker(() => load());
  mount(root, head, h('div', { class: 'card flat' }, h('div', { class: 'form-grid two' }, cp.el, sem.el)), out);

  async function load() {
    mount(out, skeletons(3));
    try {
      const classId = cp.sel.value, semId = sem.sel.value;
      const rows = await db.rpc('list_reports', { p_class: classId, p_semester: semId });
      if (!rows.length) return mount(out, emptyState('Belum ada siswa aktif pada kelas ini.'));
      const cls = viewable.find(c => c.id === classId);
      const ready = rows.filter(r => r.ready).length, validated = rows.filter(r => r.status === 'divalidasi').length, published = rows.filter(r => r.status === 'dipublikasi').length;
      const curriculum = can(...CURRICULUM);

      const validateAll = h('button', { class: 'btn', type: 'button', onclick: () => withBusy(validateAll, async () => {
        try {
          const r = await db.rpc('validate_reports', { p_class: classId, p_semester: semId });
          toast(`${r.divalidasi} rapor divalidasi${r.belum_lengkap ? `, ${r.belum_lengkap} belum lengkap` : ''}.`, r.divalidasi ? 'ok' : 'err'); load();
        } catch (e) { toast(e.message, 'err'); }
      }) }, icon('check', 18), 'Validasi rapor kelas');
      const publishAll = h('button', { class: 'btn gold', type: 'button', onclick: async () => {
        if (!(await confirmDialog({ title: 'Terbitkan rapor', message: `Terbitkan ${validated} rapor yang sudah divalidasi? Siswa dapat melihatnya di portal dan nilai tidak dapat diubah lagi tanpa membuka kembali rapor.`, confirmText: 'Terbitkan' }))) return;
        try { const n = await db.rpc('publish_reports', { p_class: classId, p_semester: semId }); toast(`${n} rapor diterbitkan.`); load(); } catch (e) { toast(e.message, 'err'); }
      } }, icon('file', 18), 'Terbitkan rapor');

      const rowEl = (r) => {
        const [stLabel, stCls] = REPORT_STATUS[r.status] || REPORT_STATUS.draft;
        const actions = [h('button', { class: 'btn ghost small', type: 'button', onclick: () => openReport(r, sem.sel.value) }, icon('eye', 16), 'Lihat')];
        if ((cls?.is_wali || curriculum) && r.status === 'draft') actions.push(h('button', { class: 'btn ghost small', type: 'button', onclick: () => noteDialog(r, semId, load) }, icon('edit', 16), 'Catatan'));
        if (curriculum && r.status !== 'draft') actions.push(h('button', { class: 'btn ghost small', type: 'button', onclick: () => reopenDialog(r, semId, load) }, 'Buka kembali'));
        return h('div', { class: 'item' }, h('div', { class: 'top' }, h('div', { class: 'name' }, r.full_name), badge(stLabel, stCls)),
          h('div', { class: 'row wrap small muted' }, h('span', null, 'NIS ' + r.nis), h('span', null, `Mapel lengkap ${r.subjects_complete}/${r.subjects_total}`), h('span', null, 'Rata-rata ' + fmtScore(r.average)), r.status === 'draft' ? (r.ready ? badge('Siap divalidasi', 'ringan') : badge('Nilai belum lengkap', 'gold')) : null),
          h('div', { class: 'row wrap' }, actions));
      };
      mount(out,
        h('div', { class: 'card flat' }, h('div', { class: 'row wrap between' },
          h('div', { class: 'row wrap' }, badge(`${num(rows.length)} siswa`), badge(`${ready} siap`, 'ringan'), badge(`${validated} divalidasi`, 'gold'), badge(`${published} terbit`, 'ringan')),
          h('div', { class: 'row wrap' }, curriculum ? validateAll : null, can(...PUBLISHERS) && validated ? publishAll : null))),
        h('div', { class: 'list' }, rows.map(rowEl)),
        h('p', { class: 'small muted' }, 'Alur: nilai lengkap → wali kelas mengisi catatan → kurikulum memvalidasi → diterbitkan (kurikulum/kepala sekolah). Rapor yang terbit menjadi arsip yang tidak berubah dan tampil di portal siswa.'));
    } catch (e) { mount(out, h('div', { class: 'card err' }, e.message)); }
  }
  await load();
}

function noteDialog(r, semId, done) {
  const ta = h('textarea', { class: 'input', rows: 5, maxlength: 1000, placeholder: 'Catatan perkembangan siswa…' }, r.homeroom_note || '');
  const err = h('div', { class: 'err', role: 'alert' });
  const save = h('button', { class: 'btn', type: 'button', onclick: () => withBusy(save, async () => {
    try { await db.rpc('save_homeroom_note', { p_student: r.student_id, p_semester: semId, p_note: ta.value }); toast('Catatan tersimpan.'); m.close(); done(); } catch (e) { err.textContent = e.message; }
  }) }, 'Simpan');
  const m = modal({ title: 'Catatan wali kelas — ' + r.full_name, body: [field('Catatan', ta, 'Maksimal 1000 karakter.'), err], actions: [h('button', { class: 'btn ghost', type: 'button', onclick: () => m.close() }, 'Batal'), save] });
}

async function reopenDialog(r, semId, done) {
  const reason = await confirmDialog({ title: 'Buka kembali rapor', message: `Rapor ${r.full_name} akan kembali berstatus draf dan hilang dari portal siswa. Tindakan ini dicatat.`, confirmText: 'Buka kembali', danger: true, reason: { label: 'Alasan', min: 5, placeholder: 'Contoh: koreksi nilai UH Matematika' } });
  if (!reason) return;
  try { await db.rpc('reopen_report', { p_student: r.student_id, p_semester: semId, p_reason: reason }); toast('Rapor dibuka kembali.'); done(); } catch (e) { toast(e.message, 'err'); }
}

async function openReport(r, semId) {
  const body = h('div', { class: 'stack' }, skeletons(2));
  const m = modal({ title: 'Rapor — ' + r.full_name, wide: true, body: [body], actions: [h('button', { class: 'btn ghost', type: 'button', onclick: () => window.print() }, icon('print', 18), 'Cetak'), h('button', { class: 'btn', type: 'button', onclick: () => m.close() }, 'Tutup')] });
  try {
    const d = await db.rpc('get_report', { p_student: r.student_id, p_semester: semId });
    const k = d.kehadiran || {};
    const official = d.status === 'dipublikasi';
    mount(body, h('div', { class: 'rapor-sheet' },
      !official ? h('div', { class: 'notice' }, d.status === 'divalidasi' ? 'Rapor sudah divalidasi, belum diterbitkan.' : 'PRATINJAU — rapor masih draf dan belum resmi.') : null,
      h('div', { style: { textAlign: 'center' } }, h('h2', null, 'LAPORAN HASIL BELAJAR'), h('div', null, school() ? school().name : ''), h('div', { class: 'small' }, `Semester ${d.semester} • Tahun ajaran ${d.tahun_ajaran}`)),
      h('dl', { class: 'kv' }, h('dt', null, 'Nama'), h('dd', null, d.nama), h('dt', null, 'NIS'), h('dd', null, d.nis), h('dt', null, 'Kelas'), h('dd', null, d.kelas)),
      h('table', null, h('thead', null, h('tr', null, h('th', null, 'Mata pelajaran'), h('th', { class: 'num' }, 'KKM'), h('th', { class: 'num' }, 'Nilai'), h('th', null, 'Predikat'), h('th', null, 'Ket.'))),
        h('tbody', null, (d.mapel || []).map(x => h('tr', null, h('td', null, x.mapel), h('td', { class: 'num' }, x.kkm), h('td', { class: 'num' }, fmtScore(x.nilai) + (x.lengkap ? '' : '*')), h('td', null, x.predikat || '–'), h('td', null, x.nilai === null ? '–' : x.tuntas ? 'Tuntas' : 'Belum tuntas'))))),
      h('table', null, h('thead', null, h('tr', null, ['Hadir', 'Izin', 'Sakit', 'Alpa', 'Terlambat'].map(t => h('th', { class: 'num' }, t)))),
        h('tbody', null, h('tr', null, ['hadir', 'izin', 'sakit', 'alpa', 'terlambat'].map(t => h('td', { class: 'num' }, num(k[t])))))),
      h('div', null, h('b', null, 'Catatan wali kelas'), h('p', null, d.catatan_wali || '-')),
      (d.mapel || []).some(x => !x.lengkap) ? h('p', { class: 'small' }, '* nilai sementara (komponen penilaian belum lengkap).') : null));
  } catch (e) { mount(body, h('div', { class: 'err' }, e.message)); }
}
