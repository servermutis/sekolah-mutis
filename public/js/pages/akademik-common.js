// Pembantu bersama halaman akademik (presensi, nilai, jadwal, rapor).
import { h, field, todayWIB } from '../ui.js';
import { db } from '../api.js';
import { S } from '../state.js';

export const DAYS = ['', 'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu'];
export const ATT = [
  ['hadir', 'H', 'Hadir'], ['izin', 'I', 'Izin'], ['sakit', 'S', 'Sakit'], ['alpa', 'A', 'Alpa'], ['terlambat', 'T', 'Terlambat'],
];
export const ATT_LABEL = Object.fromEntries(ATT.map(([k, , l]) => [k, l]));
export const REPORT_STATUS = { draft: ['Draf', 'gray'], divalidasi: ['Divalidasi', 'gold'], dipublikasi: ['Terbit', 'ringan'] };

const KEY = 'ymic.class';
export const loadClasses = () => db.rpc('visible_classes', { p_school: S.schoolId });

export function pickRemembered(list) {
  let id = null; try { id = localStorage.getItem(KEY); } catch { /* */ }
  return list.find(c => c.id === id)?.id || list[0]?.id || '';
}
export function remember(id) { try { localStorage.setItem(KEY, id); } catch { /* */ } }

// <select> kelas; onChange(id) dipanggil setelah pilihan berubah
export function classPicker(list, onChange, label = 'Kelas') {
  const sel = h('select', { class: 'input' }, list.map(c => h('option', { value: c.id }, c.name)));
  sel.value = pickRemembered(list);
  sel.addEventListener('change', () => { remember(sel.value); onChange(sel.value); });
  return { el: field(label, sel), sel };
}

export function currentSemesterId() {
  const t = todayWIB();
  const cur = S.semesters.find(s => String(s.start_date) <= t && t <= String(s.end_date));
  return (cur || S.semesters[0] || {}).id || '';
}
export function semesterPicker(onChange, label = 'Semester') {
  const sel = h('select', { class: 'input' }, S.semesters.map(s => h('option', { value: s.id }, `${s.name}${S.year ? ' ' + S.year.year_name : ''}`)));
  sel.value = currentSemesterId();
  sel.addEventListener('change', () => onChange(sel.value));
  return { el: field(label, sel), sel };
}

export const hhmm = (t) => (t ? String(t).slice(0, 5) : '');
export const fmtScore = (n) => (n === null || n === undefined ? '–' : new Intl.NumberFormat('id-ID', { maximumFractionDigits: 2 }).format(Number(n)));

export function tabs(items, current, onSelect) {
  return h('div', { class: 'tabs', role: 'tablist' }, items.map(([k, label]) =>
    h('button', { class: 'tab', type: 'button', role: 'tab', 'aria-selected': k === current ? 'true' : 'false', onclick: () => onSelect(k) }, label)));
}

export function firstOfMonth() { return todayWIB().slice(0, 8) + '01'; }
