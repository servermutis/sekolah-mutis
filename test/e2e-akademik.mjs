// E2E Fase 4 (akademik). Jalankan setelah: scripts/e2e-env.sh && scripts/e2e-up.sh
import { chromium } from '/home/claude/.npm-global/lib/node_modules/playwright/index.mjs';
const BASE = process.env.BASE || 'http://localhost:3100';
const MOCK = process.env.MOCK || 'http://localhost:54400';
const SHOT = '/tmp/shots';
let failures = 0;
const ok = (c, msg) => { if (c) console.log('PASS ', msg); else { failures++; console.log('FAIL ', msg); } };
const problems = [];
const browser = await chromium.launch();
async function newCtx(opts = {}) {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, locale: 'id-ID', timezoneId: 'Asia/Jakarta', ...opts });
  ctx.on('page', (p) => {
    p.on('console', (m) => { if (['error', 'warning'].includes(m.type()) && !/Failed to load resource.*(40[0-9]|429)/.test(m.text())) problems.push(`[${m.type()}] ${m.text()}`); });
    p.on('pageerror', (e) => problems.push('[pageerror] ' + e.message));
  });
  return ctx;
}
async function login(page, email) {
  await page.goto(BASE + '/masuk');
  await page.fill('input[type=email]', email); await page.fill('input[type=password]', 'Passw0rd!');
  await page.click('button[type=submit]'); await page.waitForURL('**/dashboard'); await page.waitForSelector('.topbar');
}
const toast = (page, t) => page.waitForSelector(`.toast:has-text("${t}")`);

// ---------- A. wali kelas: presensi ----------
let ctx = await newCtx(); let page = await ctx.newPage();
await login(page, 'wali@test.id');
ok(await page.locator('.bottomnav a:has-text("Presensi")').count() === 1, 'A. wali kelas melihat menu Presensi');
await page.goto(BASE + '/presensi'); await page.waitForSelector('.att-row');
ok(await page.locator('.att-row').count() === 2, 'A. daftar siswa kelas 1A (2 siswa)');
await page.locator('.att-row', { hasText: 'Siti Aisyah' }).locator('button[aria-label="Sakit"]').click();
await page.locator('.att-row', { hasText: 'Siti Aisyah' }).locator('input[placeholder^="Keterangan"]').fill('Demam');
await page.screenshot({ path: `${SHOT}/20-presensi.png` });
await page.click('button:has-text("Simpan presensi")'); await toast(page, 'Presensi tersimpan'); ok(true, 'A. presensi tersimpan');
await page.reload(); await page.waitForSelector('.att-row');
ok(await page.locator('.att-row', { hasText: 'Siti Aisyah' }).locator('button[aria-label="Sakit"][aria-pressed="true"]').count() === 1, 'A. status sakit tersimpan setelah muat ulang');
await page.click('.tab:has-text("Rekap")'); await page.waitForSelector('tbody tr');
ok((await page.locator('tbody tr', { hasText: 'Siti Aisyah' }).innerText()).replace(/\s+/g, ' ').includes('0 0 1 0 0'), 'A. rekap: Siti 1 hari sakit');
await page.screenshot({ path: `${SHOT}/21-presensi-rekap.png` });

// ---------- B. guru mapel: nilai ----------
async function fillComponent(p, idx, score) {
  await p.waitForSelector('.dialog', { state: 'detached' }); await p.evaluate(() => document.querySelectorAll('.toast').forEach(t => t.remove()));
  await p.click('button:has-text("Tambah penilaian")'); await p.waitForSelector('.dialog select');
  await p.selectOption('.dialog select', { index: idx });
  await p.click('.dialog button:has-text("Lanjut isi nilai")'); await p.waitForSelector('.score-in');
  const nIn = await p.locator('.dialog .score-in').count(); for (let k = 0; k < nIn; k++) await p.locator('.dialog .score-in').nth(k).fill(String(score));
  await p.click('.dialog button:has-text("Simpan nilai")'); await toast(p, 'Nilai tersimpan');
  try { await p.waitForSelector('.dialog', { state: 'detached', timeout: 8000 }); } catch (e) { console.log('DIALOG ERR:', await p.locator('.dialog .err').allTextContents(), await p.locator('.score-in').evaluateAll(els => els.map(e => e.value)), 'idx', idx); throw e; }
}
const gctx = await newCtx(); const gp = await gctx.newPage();
await login(gp, 'guru@test.id');
await gp.goto(BASE + '/nilai'); await gp.waitForSelector('text=Tambah penilaian');
await gp.click('button:has-text("Tambah penilaian")'); await gp.waitForSelector('.dialog select');
await gp.screenshot({ path: `${SHOT}/22-nilai-tambah.png` }); await gp.keyboard.press('Escape');
for (let i = 0; i < 4; i++) await fillComponent(gp, i, 80);
await gp.waitForSelector('tbody tr');
const ahmad = (await gp.locator('tbody tr', { hasText: 'Ahmad Fauzi' }).innerText()).replace(/\s+/g, ' ');
ok(/80/.test(ahmad) && /Tuntas/.test(ahmad), 'B. nilai akhir 80 dan Tuntas setelah 4 komponen terisi');
await gp.screenshot({ path: `${SHOT}/23-nilai.png`, fullPage: true });
ok(await gp.locator('select option', { hasText: 'Pendidikan Agama Islam' }).count() === 0, 'B. guru Matematika tidak melihat penugasan PAI');
const bad = await gp.evaluate(async () => 1);
// nilai > 100 ditolak di sisi klien
await gp.click('.tab:has-text("TGS")'); await gp.waitForSelector('.score-in');
await gp.locator('.score-in').first().fill('150'); await gp.click('.dialog button:has-text("Simpan nilai")');
await gp.waitForSelector('.dialog .err:has-text("0–100")'); ok(true, 'B. nilai di atas 100 ditolak'); await gp.keyboard.press('Escape');

// guru PAI
const g2ctx = await newCtx(); const g2 = await g2ctx.newPage();
await login(g2, 'guru2@test.id'); await g2.goto(BASE + '/nilai'); await g2.waitForSelector('text=Tambah penilaian');
for (let i = 0; i < 4; i++) await fillComponent(g2, i, 90);
ok(true, 'B. guru PAI mengisi nilai mapelnya');

// ---------- C. wali kelas: catatan rapor ----------
await page.goto(BASE + '/rapor'); await page.waitForSelector('.item:has-text("Siti Aisyah")');
ok(await page.locator('.item:has-text("Siti Aisyah") .badge:has-text("Siap divalidasi")').count() === 1, 'C. rapor siap divalidasi setelah semua mapel lengkap');
await page.locator('.item:has-text("Siti Aisyah") button:has-text("Catatan")').click(); await page.waitForSelector('.dialog textarea');
await page.fill('.dialog textarea', 'Ananda rajin dan santun.'); await page.click('.dialog button:has-text("Simpan")'); await toast(page, 'Catatan tersimpan');
ok(await page.locator('button:has-text("Validasi rapor kelas")').count() === 0, 'C. wali kelas tidak melihat tombol validasi');
await page.screenshot({ path: `${SHOT}/24-rapor-wali.png` });

// ---------- D. kurikulum: akademik, jadwal, validasi, terbit ----------
const kctx = await newCtx(); const kp = await kctx.newPage();
await login(kp, 'kurikulum@test.id');
await kp.goto(BASE + '/akademik'); await kp.waitForSelector('.item');
ok(await kp.locator('.item:has-text("Matematika")').count() === 1, 'D. daftar mata pelajaran tampil');
await kp.click('.tab:has-text("Komponen nilai")'); await kp.waitForSelector('.badge:has-text("Total bobot 100%")'); ok(true, 'D. total bobot komponen 100%');
await kp.click('.tab:has-text("Penugasan guru")'); await kp.waitForSelector('.item:has-text("Pengampu")');
ok(await kp.locator('.item:has-text("Pengampu: Guru Uji")').count() >= 1, 'D. penugasan guru per kelas tampil');
await kp.screenshot({ path: `${SHOT}/25-akademik-penugasan.png` });
await kp.goto(BASE + '/jadwal'); await kp.waitForSelector('.sched-mobile .day-card');
const senin = kp.locator('.sched-mobile .day-card', { has: kp.locator('h2:text-is("Senin")') });
await senin.locator('.lesson', { hasText: 'Jam 1' }).locator('button.cell').click(); await kp.waitForSelector('.dialog select');
await kp.selectOption('.dialog select', { label: 'Matematika (Guru Uji)' }); await kp.click('.dialog button:has-text("Simpan")'); await toast(kp, 'Jadwal tersimpan');
await kp.waitForSelector('.sched-mobile .cell.filled:has-text("Matematika")'); ok(true, 'D. jadwal Senin jam 1 = Matematika');
await kp.screenshot({ path: `${SHOT}/26-jadwal.png`, fullPage: true });
await kp.goto(BASE + '/rapor'); await kp.waitForSelector('.item:has-text("Ahmad Fauzi")');
await kp.click('button:has-text("Validasi rapor kelas")'); await toast(kp, '2 rapor divalidasi'); ok(true, 'D. kurikulum memvalidasi 2 rapor');
await kp.waitForSelector('.badge:has-text("Divalidasi")');
// nilai terkunci setelah validasi
await gp.goto(BASE + '/nilai'); await gp.waitForSelector('.tab:has-text("TGS")'); await gp.click('.tab:has-text("TGS")'); await gp.waitForSelector('.score-in');
await gp.locator('.score-in').first().fill('10'); await gp.click('.dialog button:has-text("Simpan nilai")');
await gp.waitForSelector('.dialog .err:has-text("sudah divalidasi")'); ok(true, 'D. nilai terkunci setelah rapor divalidasi'); await gp.keyboard.press('Escape');
await kp.click('button:has-text("Terbitkan rapor")'); await kp.click('.dialog button:has-text("Terbitkan")'); await toast(kp, '2 rapor diterbitkan'); ok(true, 'D. rapor diterbitkan');
await kp.locator('.item:has-text("Siti Aisyah") button:has-text("Lihat")').click(); await kp.waitForSelector('.rapor-sheet');
const sheet = await kp.locator('.rapor-sheet').innerText();
ok(/Siti Aisyah/.test(sheet) && /Matematika/.test(sheet) && /Pendidikan Agama Islam/.test(sheet) && /Ananda rajin/.test(sheet), 'D. rapor memuat nilai mapel dan catatan wali kelas');
ok(/Sakit\s*\n?\s*Alpa/.test(sheet) || /Sakit/.test(sheet), 'D. rapor memuat rekap kehadiran');
await kp.screenshot({ path: `${SHOT}/27-rapor.png`, fullPage: true }); await kp.keyboard.press('Escape');

// ---------- E. portal siswa ----------
const tokRes = await (await fetch(MOCK + '/auth/v1/token?grant_type=password', { method: 'POST', headers: { apikey: 'sb_publishable_test_anon', 'content-type': 'application/json' }, body: JSON.stringify({ email: 'kesiswaan@test.id', password: 'Passw0rd!' }) })).json();
const tok = tokRes.access_token;
const sid = (await (await fetch(MOCK + '/rest/v1/students?nis=eq.10002&select=id', { headers: { apikey: 'sb_publishable_test_anon', Authorization: 'Bearer ' + tok } })).json())[0].id;
const pinRes = await (await fetch(BASE + '/api/admin/pin', { method: 'POST', headers: { Authorization: 'Bearer ' + tok, 'content-type': 'application/json' }, body: JSON.stringify({ student_id: sid }) })).json();
const pin = pinRes.pins[0].pin;
const sctx = await newCtx(); const sp = await sctx.newPage();
await sp.goto(BASE + '/cek-poin'); await sp.waitForSelector('input[placeholder^="Contoh"]');
await sp.fill('input[placeholder^="Contoh"]', '10002'); await sp.fill('input[type=password]', pin); await sp.click('button[type=submit]');
await sp.waitForSelector('h1:has-text("Buat PIN Baru")');
const inputs = sp.locator('input[type=password]'); await inputs.nth(0).fill(pin); await inputs.nth(1).fill('Mutiara26'); await inputs.nth(2).fill('Mutiara26');
await sp.click('button:has-text("Simpan PIN Baru")'); await sp.waitForSelector('.sis-head');
ok(await sp.locator('.tab').count() === 4, 'E. portal siswa memiliki 4 tab (Poin, Jadwal, Kehadiran, Rapor)');
await sp.click('.tab:has-text("Jadwal")'); await sp.waitForSelector('.day-card:has-text("Matematika")'); ok(true, 'E. jadwal kelas tampil di portal'); await sp.screenshot({ path: `${SHOT}/28-portal-jadwal.png` });
await sp.click('.tab:has-text("Kehadiran")'); await sp.waitForSelector('.badge.att-sakit:has-text("Sakit 1")'); ok(true, 'E. kehadiran milik sendiri (sakit 1)'); await sp.screenshot({ path: `${SHOT}/29-portal-kehadiran.png` });
await sp.click('.tab:has-text("Rapor")'); await sp.waitForSelector('.rapor-sheet');
const pr = await sp.locator('.rapor-sheet').innerText();
ok(/Matematika/.test(pr) && /Pendidikan Agama Islam/.test(pr) && /Ananda rajin/.test(pr) && !/Ahmad/.test(pr), 'E. rapor terbit tampil, tanpa data siswa lain');
await sp.screenshot({ path: `${SHOT}/30-portal-rapor.png`, fullPage: true });
const ownOnly = await sp.evaluate(async () => { const r = await (await fetch('/api/siswa/akademik?bagian=rapor')).json(); return JSON.stringify(r); });
ok(!/Ahmad/.test(ownOnly) && /Siti Aisyah/.test(ownOnly), 'E. API portal hanya mengembalikan data pemilik sesi');
const badArg = await sp.evaluate(async () => (await fetch('/api/siswa/akademik?bagian=../x')).status); ok(badArg === 400, 'E. parameter bagian tidak valid ditolak (400)');
await sp.click('.tab:has-text("Poin")'); await sp.click('button:has-text("Keluar")'); await sp.waitForSelector('input[placeholder^="Contoh"]');
const after = await sp.evaluate(async () => (await fetch('/api/siswa/akademik?bagian=jadwal')).status); ok(after === 401, 'E. setelah logout API akademik = 401');

// ---------- F. isolasi peran & desktop ----------
await page.goto(BASE + '/akademik'); await page.waitForURL('**/dashboard'); ok(true, 'F. wali kelas dialihkan dari /akademik');
await gp.goto(BASE + '/rapor'); await gp.waitForURL('**/dashboard'); ok(true, 'F. guru mapel dialihkan dari /rapor');
const dctx = await newCtx({ viewport: { width: 1280, height: 800 }, isMobile: false, hasTouch: false, deviceScaleFactor: 1 }); const dp = await dctx.newPage();
await login(dp, 'yayasan@test.id');
await dp.waitForSelector('.card:has-text("Kehadiran hari ini")'); await dp.screenshot({ path: `${SHOT}/31-desktop-dashboard.png` });
await dp.goto(BASE + '/jadwal'); await dp.waitForSelector('.sched-desktop .cell.filled'); await dp.screenshot({ path: `${SHOT}/32-desktop-jadwal.png` }); ok(true, 'F. grid jadwal desktop');
await dp.goto(BASE + '/rapor'); await dp.waitForSelector('.item'); await dp.screenshot({ path: `${SHOT}/33-desktop-rapor.png` });
await dp.goto(BASE + '/presensi'); await dp.waitForSelector('.att-row'); await dp.screenshot({ path: `${SHOT}/34-desktop-presensi.png` });

await browser.close();
const hasProblems = problems.length > 0;
if (hasProblems) { console.log('\nMASALAH KONSOL/CSP:'); problems.forEach(p => console.log(p)); }
console.log(failures || hasProblems ? '\nADA YANG GAGAL' : '\nSEMUA E2E AKADEMIK LULUS');
process.exit(failures || hasProblems ? 1 : 0);
