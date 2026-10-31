import { h, mount, icon, modal, field, toast, withBusy, emptyState, skeletons } from '../ui.js';
import { db, eq } from '../api.js';
import { S, can } from '../state.js';
import { DAYS, loadClasses, classPicker, tabs, hhmm } from './akademik-common.js';

const EDITORS = ['admin_sekolah', 'kurikulum'];

export async function render(root) {
  const [classes, mine] = await Promise.all([loadClasses(), db.rpc('my_schedule', { p_school: S.schoolId })]);
  const head = h('div', { class: 'page-head' }, h('h1', null, 'Jadwal Pelajaran'));
  if (!classes.length && !mine.length) return mount(root, head, emptyState('Belum ada jadwal atau kelas yang dapat Anda akses.'));
  const periodsRaw = await db.select('lesson_periods', { select: 'period,start_time,end_time', school_id: eq(S.schoolId), order: 'period.asc' });
  const periods = periodsRaw.length ? periodsRaw : Array.from({ length: 8 }, (_, i) => ({ period: i + 1, start_time: null, end_time: null }));

  let tab = mine.length ? 'saya' : 'kelas';
  const body = h('div', { class: 'stack' }), tabBar = h('div');
  const drawTabs = () => mount(tabBar, mine.length && classes.length ? tabs([['saya', 'Jadwal saya'], ['kelas', 'Per kelas']], tab, (k) => { tab = k; drawTabs(); draw(); }) : null);
  const draw = () => (tab === 'saya' ? mySchedule(body, mine, periods) : classView(body, classes, periods));
  mount(root, head, tabBar, body); drawTabs(); await draw();
}

function periodTime(p) { return p && p.start_time ? `${hhmm(p.start_time)}–${hhmm(p.end_time)}` : ''; }

function mySchedule(body, rows, periods) {
  const pmap = new Map(periods.map(p => [p.period, p]));
  const days = [1, 2, 3, 4, 5, 6].filter(d => rows.some(r => r.day === d));
  mount(body, days.map(d => h('div', { class: 'day-card' }, h('h2', null, DAYS[d]),
    rows.filter(r => r.day === d).map(r => h('div', { class: 'lesson' },
      h('div', { class: 't' }, `Jam ${r.period}`, h('div', null, periodTime(pmap.get(r.period)))),
      h('div', null, h('div', { style: { fontWeight: 700 } }, r.subject_name), h('div', { class: 'small muted' }, 'Kelas ' + r.class_name)))))));
}

async function classView(body, classes, periods) {
  const edit = can(...EDITORS);
  const out = h('div', { class: 'stack' });
  const cp = classPicker(classes, () => load());
  mount(body, h('div', { class: 'card flat' }, cp.el), out);
  async function load() {
    mount(out, skeletons(3));
    try {
      const classId = cp.sel.value;
      const [slots, asgs] = await Promise.all([db.rpc('list_schedule', { p_class: classId }), db.rpc('list_assignments', { p_class: classId })]);
      const at = (d, p) => slots.find(s => s.day === d && s.period === p);
      const chooser = (d, p) => {
        const cur = at(d, p);
        const sel = h('select', { class: 'input' }, h('option', { value: '' }, '— Kosong —'), asgs.map(a => h('option', { value: a.id }, `${a.subject_name} (${a.teacher_name || 'guru?'})`)));
        sel.value = cur ? cur.assignment_id : '';
        const err = h('div', { class: 'err', role: 'alert' });
        const save = h('button', { class: 'btn', type: 'button', onclick: () => withBusy(save, async () => {
          try { await db.rpc('save_schedule_slot', { p_class: classId, p_day: d, p_period: p, p_assignment: sel.value || null }); toast('Jadwal tersimpan.'); m.close(); load(); }
          catch (e) { err.textContent = e.message; }
        }) }, 'Simpan');
        const m = modal({ title: `${DAYS[d]} • Jam ${p}`, body: [asgs.length ? field('Mata pelajaran', sel) : h('div', { class: 'notice' }, 'Belum ada penugasan guru untuk kelas ini. Atur di menu Akademik > Penugasan.'), err], actions: [h('button', { class: 'btn ghost', type: 'button', onclick: () => m.close() }, 'Batal'), asgs.length ? save : null] });
      };
      const cell = (d, p) => {
        const s = at(d, p);
        const inner = s ? [h('div', { class: 'sub' }, s.subject_name), h('div', { class: 'who' }, s.teacher_name || '')] : [h('span', { class: 'small muted' }, edit ? '+ isi' : '')];
        return edit ? h('button', { class: 'cell' + (s ? ' filled' : ''), type: 'button', onclick: () => chooser(d, p), 'aria-label': `${DAYS[d]} jam ${p}` }, inner) : h('div', { class: 'cell' + (s ? ' filled' : '') }, inner);
      };
      const desktop = h('div', { class: 'table-wrap sched-desktop' }, h('table', { class: 'sched' },
        h('thead', null, h('tr', null, h('th', null, 'Jam'), [1, 2, 3, 4, 5, 6].map(d => h('th', null, DAYS[d])))),
        h('tbody', null, periods.map(pr => h('tr', null, h('td', { class: 'time' }, `${pr.period}`, h('div', null, periodTime(pr))), [1, 2, 3, 4, 5, 6].map(d => h('td', null, cell(d, pr.period))))))));
      const mobile = h('div', { class: 'stack sched-mobile' }, [1, 2, 3, 4, 5, 6].map(d => h('div', { class: 'day-card' }, h('h2', null, DAYS[d]),
        periods.filter(pr => edit || at(d, pr.period)).map(pr => h('div', { class: 'lesson' }, h('div', { class: 't' }, `Jam ${pr.period}`, h('div', null, periodTime(pr))), h('div', { class: 'grow' }, cell(d, pr.period)))),
        !edit && !slots.some(s => s.day === d) ? h('p', { class: 'small muted' }, 'Tidak ada jadwal.') : null)));
      mount(out, edit ? h('p', { class: 'small muted' }, 'Ketuk kotak untuk mengisi atau mengubah jadwal. Sistem menolak jadwal yang membuat guru mengajar di dua kelas pada jam yang sama.') : null, desktop, mobile);
    } catch (e) { mount(out, h('div', { class: 'card err' }, e.message)); }
  }
  await load();
}
