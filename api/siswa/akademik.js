'use strict';
// Data akademik milik siswa yang sedang login (jadwal, kehadiran, rapor terbit).
// Identitas HANYA dari sesi bertanda tangan; parameter klien hanya memilih bagian.
const { send, handler, httpError } = require('../_lib/http');
const { rpcService } = require('../_lib/supabase');
const { requireStudent } = require('../_lib/siswa');

const BAGIAN = { jadwal: 'portal_jadwal', kehadiran: 'portal_kehadiran', rapor: 'portal_rapor' };

module.exports = handler(['GET'], async (req, res) => {
  const s = await requireStudent(req);
  if (s.mustChange) throw httpError(403, 'Ganti PIN terlebih dahulu.');
  const bagian = new URL(req.url, 'http://localhost').searchParams.get('bagian');
  if (!Object.prototype.hasOwnProperty.call(BAGIAN, bagian)) throw httpError(400, 'Permintaan tidak valid.');
  const data = await rpcService(BAGIAN[bagian], { p_student: s.studentId });
  send(res, 200, data === null ? [] : data);
});
