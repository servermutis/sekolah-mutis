-- Pengujian Fase 4: penugasan, jadwal, presensi, nilai berbobot, rapor, isolasi unit, portal.
\set ON_ERROR_STOP on
set client_min_messages = notice;

create schema t;
grant usage on schema t to authenticated, anon, service_role;
create function t.ok(c boolean, label text) returns void language plpgsql as $$
begin if c then raise notice 'PASS  %', label; else raise exception 'FAIL  %', label; end if; end $$;
create function t.fails(q text) returns boolean language plpgsql as $$
begin execute q; return false; exception when others then return true; end $$;
create temp table ids (k text primary key, v uuid);
grant all on ids to public;
create function t.v(k text) returns uuid language sql as $$ select v from ids where ids.k = $1 $$;
create function t.as_user(k text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', (select v::text from ids where ids.k = 'u_'||as_user.k), true); end $$;
grant execute on all functions in schema t to authenticated, anon, service_role;

-- ---------- data uji ----------
insert into ids select 'u_'||n, gen_random_uuid() from unnest(array['kur_sd','kur_smp','guru_a','guru_b','guru_smp','wali_a','kes_sd','kepsek_sd','admin_sd']) n;
insert into auth.users (id, email) select v, k||'@x.id' from ids;
insert into public.profiles (id, full_name) select v, k from ids;
insert into ids select 'sd', id from public.schools where code='SD';
insert into ids select 'smp', id from public.schools where code='SMP';
insert into public.user_roles (user_id, role, school_id) values
  (t.v('u_kur_sd'), 'kurikulum', t.v('sd')), (t.v('u_kur_smp'), 'kurikulum', t.v('smp')),
  (t.v('u_guru_a'), 'guru', t.v('sd')), (t.v('u_guru_b'), 'guru', t.v('sd')), (t.v('u_guru_smp'), 'guru', t.v('smp')),
  (t.v('u_wali_a'), 'wali_kelas', t.v('sd')), (t.v('u_kes_sd'), 'kesiswaan', t.v('sd')),
  (t.v('u_kepsek_sd'), 'kepala_sekolah', t.v('sd')), (t.v('u_admin_sd'), 'admin_sekolah', t.v('sd'));

insert into public.classes (school_id, academic_year_id, name)
select ay.school_id, ay.id, n from public.academic_years ay
  join public.schools s on s.id = ay.school_id, unnest(array['1A','1B']) n where ay.is_active and s.code = 'SD';
insert into public.classes (school_id, academic_year_id, name)
select ay.school_id, ay.id, '7A' from public.academic_years ay join public.schools s on s.id = ay.school_id where ay.is_active and s.code = 'SMP';
insert into ids select 'c_1a', id from public.classes where name='1A';
insert into ids select 'c_1b', id from public.classes where name='1B';
insert into ids select 'c_7a', id from public.classes where name='7A';

insert into public.students (school_id, nis, full_name) values
  (t.v('sd'), '10001', 'Siswa A'), (t.v('sd'), '10002', 'Siswa B'), (t.v('sd'), '10003', 'Siswa C'), (t.v('smp'), '20001', 'Siswa D');
insert into ids select 's_'||lower(right(full_name,1)), id from public.students;
insert into public.student_enrollments (school_id, student_id, class_id, academic_year_id)
select c.school_id, s.id, c.id, c.academic_year_id from public.students s join public.classes c on c.school_id = s.school_id
 where (s.nis in ('10001','10002') and c.name = '1A') or (s.nis = '10003' and c.name = '1B') or (s.nis = '20001' and c.name = '7A');
insert into public.class_teachers (school_id, class_id, user_id, role) values (t.v('sd'), t.v('c_1a'), t.v('u_wali_a'), 'wali_kelas');

insert into ids select 'ay_smp', id from public.academic_years where school_id = t.v('smp') and is_active;
insert into ids select 'sem', sm.id from public.semesters sm join public.academic_years ay on ay.id = sm.academic_year_id and ay.is_active
  where ay.school_id = t.v('sd') and sm.name = 'Ganjil';
insert into ids select 'sem_smp', sm.id from public.semesters sm join public.academic_years ay on ay.id = sm.academic_year_id and ay.is_active
  where ay.school_id = t.v('smp') and sm.name = 'Ganjil';
insert into ids select 'cp_'||lower(ac.code), ac.id from public.assessment_components ac join public.academic_years ay on ay.id = ac.academic_year_id and ay.is_active where ac.school_id = t.v('sd');
insert into ids select 'sub_'||lower(code), id from public.subjects where school_id = t.v('sd') and code in ('MTK','PAI');
insert into ids select 'sub_smp', id from public.subjects where school_id = t.v('smp') and code = 'MTK';

-- ======================= SKENARIO =======================
begin;
select t.ok((select count(*) from public.assessment_components where school_id = t.v('sd')) = 4, '0. komponen awal Tugas/UH/UTS/UAS tersedia');
select t.ok((select sum(weight) from public.assessment_components where school_id = t.v('sd')) = 100, '0. bobot komponen awal berjumlah 100');

-- 1-3. penugasan guru
set local role authenticated; select t.as_user('guru_a');
select t.ok(t.fails(format($q$insert into public.teaching_assignments (school_id, academic_year_id, class_id, subject_id, teacher_id) select school_id, academic_year_id, id, %L, %L from public.classes where id = %L$q$, t.v('sub_mtk'), t.v('u_guru_a'), t.v('c_1a'))), '1. guru tidak dapat membuat penugasan');
select t.as_user('kur_sd');
insert into public.teaching_assignments (school_id, academic_year_id, class_id, subject_id, teacher_id)
  select school_id, academic_year_id, id, t.v('sub_mtk'), t.v('u_guru_a') from public.classes where id = t.v('c_1a');
insert into public.teaching_assignments (school_id, academic_year_id, class_id, subject_id, teacher_id)
  select school_id, academic_year_id, id, t.v('sub_pai'), t.v('u_guru_b') from public.classes where id = t.v('c_1a');
insert into public.teaching_assignments (school_id, academic_year_id, class_id, subject_id, teacher_id)
  select school_id, academic_year_id, id, t.v('sub_mtk'), t.v('u_guru_a') from public.classes where id = t.v('c_1b');
select t.ok((select count(*) from public.teaching_assignments) = 3, '1. kurikulum membuat penugasan');
select t.ok(t.fails(format($q$insert into public.teaching_assignments (school_id, academic_year_id, class_id, subject_id, teacher_id) select school_id, academic_year_id, id, %L, %L from public.classes where id = %L$q$, t.v('sub_mtk'), t.v('u_kes_sd'), t.v('c_1a'))), '2. pengampu harus berperan guru/wali kelas (dan satu mapel satu guru per kelas)');
select t.ok(t.fails(format($q$insert into public.teaching_assignments (school_id, academic_year_id, class_id, subject_id, teacher_id) values (%L, %L, %L, %L, %L)$q$, t.v('smp'), t.v('ay_smp'), t.v('c_7a'), t.v('sub_smp'), t.v('u_guru_smp'))), '3. kurikulum SD tidak dapat membuat penugasan di unit SMP');
select t.ok(t.fails(format($q$insert into public.teaching_assignments (school_id, academic_year_id, class_id, subject_id, teacher_id) select school_id, academic_year_id, id, %L, %L from public.classes where id = %L$q$, t.v('sub_smp'), t.v('u_guru_a'), t.v('c_1b'))), '3. mapel unit lain tidak dapat dipasang pada kelas SD');

reset role;
insert into ids select 'ta_mtk_1a', id from public.teaching_assignments where class_id = t.v('c_1a') and subject_id = t.v('sub_mtk');
insert into ids select 'ta_pai_1a', id from public.teaching_assignments where class_id = t.v('c_1a') and subject_id = t.v('sub_pai');
insert into ids select 'ta_mtk_1b', id from public.teaching_assignments where class_id = t.v('c_1b') and subject_id = t.v('sub_mtk');

-- 4. jadwal
set local role authenticated; select t.as_user('kur_sd');
select public.save_schedule_slot(t.v('c_1a'), 1, 1, t.v('ta_mtk_1a'));
select public.save_schedule_slot(t.v('c_1a'), 1, 2, t.v('ta_pai_1a'));
select t.ok((select count(*) from public.list_schedule(t.v('c_1a'))) = 2, '4. jadwal tersimpan');
select t.ok(t.fails(format($q$select public.save_schedule_slot(%L, 1, 1, %L)$q$, t.v('c_1b'), t.v('ta_mtk_1b'))), '4. guru yang sama tidak dapat mengajar dua kelas pada hari+jam yang sama');
select t.ok(t.fails(format($q$select public.save_schedule_slot(%L, 2, 1, %L)$q$, t.v('c_1b'), t.v('ta_mtk_1a'))), '4. penugasan kelas lain ditolak');
select public.save_schedule_slot(t.v('c_1b'), 2, 1, t.v('ta_mtk_1b'));
select public.save_schedule_slot(t.v('c_1a'), 1, 2, null);
select t.ok((select count(*) from public.list_schedule(t.v('c_1a'))) = 1, '4. slot dapat dikosongkan');
select t.ok((select start_time from public.list_schedule(t.v('c_1a')) limit 1) = time '07:00', '4. jam pelajaran terhubung ke jadwal');
select t.as_user('guru_a');
select t.ok(t.fails(format($q$select public.save_schedule_slot(%L, 3, 1, %L)$q$, t.v('c_1a'), t.v('ta_mtk_1a'))), '4. guru tidak dapat mengatur jadwal');
select t.ok((select count(*) from public.my_schedule(t.v('sd'))) = 2, '4. jadwal saya hanya milik guru yang login');
select t.as_user('guru_smp');
select t.ok(t.fails(format($q$select * from public.list_schedule(%L)$q$, t.v('c_1a'))), '4. guru SMP tidak melihat jadwal kelas SD');
reset role;

-- 5. presensi
set local role authenticated; select t.as_user('wali_a');
select t.ok(public.save_attendance(t.v('c_1a'), public.today_wib(), jsonb_build_array(
    jsonb_build_object('student_id', t.v('s_a'), 'status', 'hadir'), jsonb_build_object('student_id', t.v('s_b'), 'status', 'sakit', 'note', 'Demam'))) = 2, '5. wali kelas mengisi presensi');
select public.save_attendance(t.v('c_1a'), public.today_wib(), jsonb_build_array(
    jsonb_build_object('student_id', t.v('s_a'), 'status', 'hadir'), jsonb_build_object('student_id', t.v('s_b'), 'status', 'sakit', 'note', 'Demam')));
select t.ok((select count(*) from public.attendance_records) = 2, '5. kirim ulang tidak menggandakan catatan');
select public.save_attendance(t.v('c_1a'), public.today_wib(), jsonb_build_array(jsonb_build_object('student_id', t.v('s_b'), 'status', 'izin')));
select t.ok((select status from public.list_attendance(t.v('c_1a'), public.today_wib()) where nis = '10002') = 'izin', '5. perubahan status memperbarui catatan yang sama');
select t.ok((select count(*) from public.attendance_records) = 2, '5. perubahan tidak membuat catatan baru');
select t.ok(t.fails(format($q$select public.save_attendance(%L, public.today_wib(), jsonb_build_array(jsonb_build_object('student_id', %L, 'status', 'hadir')))$q$, t.v('c_1a'), t.v('s_c'))), '5. siswa kelas lain ditolak');
select t.ok(t.fails(format($q$select public.save_attendance(%L, public.today_wib(), jsonb_build_array(jsonb_build_object('student_id', %L, 'status', 'bolos')))$q$, t.v('c_1a'), t.v('s_a'))), '5. status tidak dikenal ditolak');
select t.ok(t.fails(format($q$select public.save_attendance(%L, public.today_wib() + 1, jsonb_build_array(jsonb_build_object('student_id', %L, 'status', 'hadir')))$q$, t.v('c_1a'), t.v('s_a'))), '5. tanggal masa depan ditolak');
select t.ok(t.fails(format($q$select public.save_attendance(%L, public.today_wib() - 10, jsonb_build_array(jsonb_build_object('student_id', %L, 'status', 'hadir')))$q$, t.v('c_1a'), t.v('s_a'))), '5. wali kelas tidak dapat mengubah presensi > 7 hari');
select t.as_user('kes_sd');
select public.save_attendance(t.v('c_1a'), public.today_wib() - 10, jsonb_build_array(jsonb_build_object('student_id', t.v('s_a'), 'status', 'alpa')));
select t.ok((select count(*) from public.attendance_records) = 3, '5. kesiswaan dapat mengoreksi presensi lampau');
select t.as_user('guru_b');
select t.ok(t.fails(format($q$select public.save_attendance(%L, public.today_wib(), jsonb_build_array(jsonb_build_object('student_id', %L, 'status', 'hadir')))$q$, t.v('c_1a'), t.v('s_a'))), '5. guru mapel (bukan wali) tidak dapat mengisi presensi harian');
select t.ok((select count(*) from public.list_attendance(t.v('c_1a'), public.today_wib())) = 2, '5. guru mapel dapat melihat presensi kelas ajarannya');
select t.as_user('guru_smp');
select t.ok(t.fails(format($q$select * from public.list_attendance(%L, public.today_wib())$q$, t.v('c_1a'))), '5. guru SMP tidak melihat presensi SD');
select t.ok((select count(*) from public.attendance_records) = 0, '5. RLS: guru SMP tidak melihat catatan presensi SD');
select t.ok(t.fails(format($q$insert into public.attendance_records (school_id, class_id, student_id, att_date, status) values (%L, %L, %L, public.today_wib(), 'hadir')$q$, t.v('sd'), t.v('c_1a'), t.v('s_a'))), '5. tulis langsung ke tabel presensi ditolak');
select t.as_user('kepsek_sd');
select t.ok((select (public.attendance_today(t.v('sd'))->>'total')::int) = 2, '5. dashboard presensi hari ini');
select t.ok((select hadir from public.attendance_summary(t.v('c_1a'), null, null) where nis = '10001') = 1
         and (select alpa from public.attendance_summary(t.v('c_1a'), null, null) where nis = '10001') = 1, '5. rekap presensi per siswa');
reset role;

-- 6. nilai
set local role authenticated; select t.as_user('guru_a');
select t.ok(public.save_grades(t.v('ta_mtk_1a'), t.v('sem'), t.v('cp_tgs'), 'T1', jsonb_build_array(
    jsonb_build_object('student_id', t.v('s_a'), 'score', 100), jsonb_build_object('student_id', t.v('s_b'), 'score', 50))) = 2, '6. guru mengisi nilai komponen');
select public.save_grades(t.v('ta_mtk_1a'), t.v('sem'), t.v('cp_uh'), 'UH 1', jsonb_build_array(
    jsonb_build_object('student_id', t.v('s_a'), 'score', 80), jsonb_build_object('student_id', t.v('s_b'), 'score', 90)));
select t.ok((select final_score from public.rekap_nilai(t.v('c_1a'), t.v('sem')) where nis = '10001') = 90.00, '6. nilai akhir sementara dibobot atas komponen terisi: (100*20+80*20)/40 = 90');
select t.ok(not (select lengkap from public.rekap_nilai(t.v('c_1a'), t.v('sem')) where nis = '10001'), '6. belum lengkap sebelum semua komponen terisi');
select public.save_grades(t.v('ta_mtk_1a'), t.v('sem'), t.v('cp_uts'), 'UTS', jsonb_build_array(
    jsonb_build_object('student_id', t.v('s_a'), 'score', 70), jsonb_build_object('student_id', t.v('s_b'), 'score', 60)));
select public.save_grades(t.v('ta_mtk_1a'), t.v('sem'), t.v('cp_uas'), 'UAS', jsonb_build_array(
    jsonb_build_object('student_id', t.v('s_a'), 'score', 90), jsonb_build_object('student_id', t.v('s_b'), 'score', 70)));
select t.ok((select final_score from public.rekap_nilai(t.v('c_1a'), t.v('sem')) where nis = '10001') = 85.00, '6. nilai akhir A = 85,00');
select t.ok((select final_score from public.rekap_nilai(t.v('c_1a'), t.v('sem')) where nis = '10002') = 67.50, '6. nilai akhir B = 67,50');
select t.ok((select lengkap from public.rekap_nilai(t.v('c_1a'), t.v('sem')) where nis = '10001'), '6. lengkap setelah semua komponen terisi');
select t.ok(not (select tuntas from public.rekap_nilai(t.v('c_1a'), t.v('sem')) where nis = '10002'), '6. B di bawah KKM 75: belum tuntas');
select t.ok((select predikat from public.rekap_nilai(t.v('c_1a'), t.v('sem')) where nis = '10001') = 'B', '6. predikat A = B');
select public.save_grades(t.v('ta_mtk_1a'), t.v('sem'), t.v('cp_tgs'), 'T2', jsonb_build_array(jsonb_build_object('student_id', t.v('s_a'), 'score', 80)));
select t.ok((select final_score from public.rekap_nilai(t.v('c_1a'), t.v('sem')) where nis = '10001') = 83.00, '6. beberapa nilai dalam satu komponen dirata-rata (T1 100, T2 80 -> 90)');
select public.save_grades(t.v('ta_mtk_1a'), t.v('sem'), t.v('cp_tgs'), 'T2', jsonb_build_array(jsonb_build_object('student_id', t.v('s_a'), 'score', null)));
select t.ok((select final_score from public.rekap_nilai(t.v('c_1a'), t.v('sem')) where nis = '10001') = 85.00, '6. nilai kosong menghapus nilai tersebut');
select t.ok((select count(*) from public.grades where student_id = t.v('s_a')) = 4, '6. tidak ada catatan nilai ganda');
select public.save_grades(t.v('ta_mtk_1a'), t.v('sem'), t.v('cp_uh'), 'UH 1', jsonb_build_array(jsonb_build_object('student_id', t.v('s_a'), 'score', 80)));
select t.ok((select count(*) from public.grades where student_id = t.v('s_a') and title = 'UH 1') = 1, '6. simpan ulang memperbarui, bukan menambah');
select t.ok(t.fails(format($q$select public.save_grades(%L, %L, %L, 'UH 2', jsonb_build_array(jsonb_build_object('student_id', %L, 'score', 101)))$q$, t.v('ta_mtk_1a'), t.v('sem'), t.v('cp_uh'), t.v('s_a'))), '6. nilai di atas 100 ditolak');
select t.ok(t.fails(format($q$select public.save_grades(%L, %L, %L, 'UH 2', jsonb_build_array(jsonb_build_object('student_id', %L, 'score', 80)))$q$, t.v('ta_mtk_1a'), t.v('sem'), t.v('cp_uh'), t.v('s_c'))), '6. siswa di luar kelas penugasan ditolak');
select t.ok(t.fails(format($q$select public.save_grades(%L, %L, %L, 'X', jsonb_build_array(jsonb_build_object('student_id', %L, 'score', 80)))$q$, t.v('ta_pai_1a'), t.v('sem'), t.v('cp_uh'), t.v('s_a'))), '6. guru tidak dapat mengisi nilai mapel milik guru lain');
select t.ok(t.fails(format($q$insert into public.grades (school_id, assignment_id, semester_id, component_id, student_id, title, score) values (%L, %L, %L, %L, %L, 'X', 99)$q$, t.v('sd'), t.v('ta_mtk_1a'), t.v('sem'), t.v('cp_uh'), t.v('s_a'))), '6. tulis langsung ke tabel nilai ditolak');
select t.ok((select count(distinct subject_name) from public.rekap_nilai(t.v('c_1a'), t.v('sem'))) = 1, '6. guru mapel hanya melihat rekap mapelnya');

select t.as_user('guru_b');
select t.ok(t.fails(format($q$select public.save_grades(%L, %L, %L, 'X', jsonb_build_array(jsonb_build_object('student_id', %L, 'score', 80)))$q$, t.v('ta_mtk_1a'), t.v('sem'), t.v('cp_uh'), t.v('s_a'))), '6. guru B tidak dapat mengisi nilai MTK');
select t.ok((select count(*) from public.grades) = 0, '6. RLS: guru B tidak melihat nilai MTK');
select public.save_grades(t.v('ta_pai_1a'), t.v('sem'), t.v('cp_tgs'), 'T1', jsonb_build_array(jsonb_build_object('student_id', t.v('s_a'), 'score', 90), jsonb_build_object('student_id', t.v('s_b'), 'score', 80)));
select public.save_grades(t.v('ta_pai_1a'), t.v('sem'), t.v('cp_uh'), 'UH 1', jsonb_build_array(jsonb_build_object('student_id', t.v('s_a'), 'score', 90), jsonb_build_object('student_id', t.v('s_b'), 'score', 80)));
select public.save_grades(t.v('ta_pai_1a'), t.v('sem'), t.v('cp_uts'), 'UTS', jsonb_build_array(jsonb_build_object('student_id', t.v('s_a'), 'score', 90), jsonb_build_object('student_id', t.v('s_b'), 'score', 80)));

select t.as_user('wali_a');
select t.ok((select count(distinct subject_name) from public.rekap_nilai(t.v('c_1a'), t.v('sem'))) = 2, '6. wali kelas melihat semua mapel kelasnya');
select t.ok(t.fails(format($q$select public.save_grades(%L, %L, %L, 'X', jsonb_build_array(jsonb_build_object('student_id', %L, 'score', 80)))$q$, t.v('ta_mtk_1a'), t.v('sem'), t.v('cp_uh'), t.v('s_a'))), '6. wali kelas (bukan pengampu) tidak dapat mengubah nilai');
select t.as_user('guru_smp');
select t.ok(t.fails(format($q$select * from public.rekap_nilai(%L, %L)$q$, t.v('c_1a'), t.v('sem'))), '6. guru SMP tidak melihat rekap nilai SD');

-- 7. rapor
select t.as_user('wali_a');
select t.ok((select count(*) from public.list_reports(t.v('c_1a'), t.v('sem'))) = 2, '7. wali kelas melihat daftar rapor kelasnya');
select t.ok(not (select ready from public.list_reports(t.v('c_1a'), t.v('sem')) where nis = '10001'), '7. rapor belum siap bila nilai mapel belum lengkap');
select public.save_homeroom_note(t.v('s_a'), t.v('sem'), 'Ananda rajin dan santun.');
select t.ok((select homeroom_note from public.list_reports(t.v('c_1a'), t.v('sem')) where nis = '10001') = 'Ananda rajin dan santun.', '7. wali kelas mengisi catatan');
select t.ok(t.fails(format($q$select public.validate_reports(%L, %L)$q$, t.v('c_1a'), t.v('sem'))), '7. wali kelas tidak dapat memvalidasi rapor');
select t.as_user('kur_smp');
select t.ok(t.fails(format($q$select public.validate_reports(%L, %L)$q$, t.v('c_1a'), t.v('sem'))), '7. kurikulum SMP tidak dapat memvalidasi rapor SD');
select t.ok(t.fails(format($q$select * from public.list_reports(%L, %L)$q$, t.v('c_1a'), t.v('sem'))), '7. kurikulum SMP tidak melihat rapor SD');
select t.as_user('kur_sd');
select t.ok((public.validate_reports(t.v('c_1a'), t.v('sem'))->>'divalidasi')::int = 0, '7. validasi menolak rapor dengan nilai belum lengkap');
select t.as_user('guru_b');
select public.save_grades(t.v('ta_pai_1a'), t.v('sem'), t.v('cp_uas'), 'UAS', jsonb_build_array(jsonb_build_object('student_id', t.v('s_a'), 'score', 90), jsonb_build_object('student_id', t.v('s_b'), 'score', 80)));
select t.as_user('kur_sd');
select t.ok((public.validate_reports(t.v('c_1a'), t.v('sem'))->>'divalidasi')::int = 2, '7. kurikulum memvalidasi 2 rapor lengkap');
select t.ok((select snapshot->'kehadiran'->>'hadir' from public.report_cards where student_id = t.v('s_a')) = '1', '7. snapshot memuat rekap kehadiran');
select t.ok(jsonb_array_length((select snapshot->'mapel' from public.report_cards where student_id = t.v('s_a'))) = 2, '7. snapshot memuat 2 mapel');
select t.as_user('guru_a');
select t.ok(t.fails(format($q$select public.save_grades(%L, %L, %L, 'UH 1', jsonb_build_array(jsonb_build_object('student_id', %L, 'score', 10)))$q$, t.v('ta_mtk_1a'), t.v('sem'), t.v('cp_uh'), t.v('s_a'))), '7. nilai terkunci setelah rapor divalidasi');
select t.as_user('wali_a');
select t.ok(t.fails(format($q$select public.save_homeroom_note(%L, %L, 'ubah')$q$, t.v('s_a'), t.v('sem'))), '7. catatan terkunci setelah validasi');
select t.as_user('kepsek_sd');
select t.ok(public.publish_reports(t.v('c_1a'), t.v('sem')) = 2, '7. kepala sekolah menerbitkan 2 rapor');
select t.ok(public.publish_reports(t.v('c_1a'), t.v('sem')) = 0, '7. terbit ulang tidak menggandakan');
select t.ok((public.get_report(t.v('s_a'), t.v('sem'))->>'status') = 'dipublikasi', '7. get_report menampilkan status');
select t.ok((public.get_report(t.v('s_a'), t.v('sem'))->>'catatan_wali') = 'Ananda rajin dan santun.', '7. get_report memuat catatan wali kelas');
select t.as_user('kur_sd');
select t.ok(t.fails(format($q$select public.reopen_report(%L, %L, 'x')$q$, t.v('s_a'), t.v('sem'))), '7. buka kembali rapor tanpa alasan memadai ditolak');
reset role;

-- 8. portal (service role)
set local role service_role;
select t.ok(jsonb_array_length(public.portal_rapor(t.v('s_a'))) = 1, '8. portal: siswa A melihat rapor terbit miliknya');
select t.ok(public.portal_rapor(t.v('s_a'))->0->>'nama' = 'Siswa A' and public.portal_rapor(t.v('s_a'))::text not like '%Siswa B%', '8. portal: data siswa lain tidak ikut');
select t.ok(jsonb_array_length(public.portal_rapor(t.v('s_c'))) = 0, '8. portal: siswa tanpa rapor terbit mendapat daftar kosong');
select t.ok((public.portal_kehadiran(t.v('s_a'))->'ringkasan'->>'hadir')::int = 1, '8. portal: kehadiran milik sendiri');
select t.ok((select count(*) from public.portal_jadwal(t.v('s_a'))) = 1, '8. portal: jadwal kelas siswa');
select t.ok((select count(*) from public.portal_jadwal(t.v('s_c'))) = 1 and (select subject_name from public.portal_jadwal(t.v('s_c'))) = 'Matematika', '8. portal: jadwal mengikuti kelas masing-masing');
reset role;

set local role authenticated; select t.as_user('kur_sd');
select t.ok(t.fails(format($q$select * from public.portal_rapor(%L)$q$, t.v('s_a'))), '8. pengguna terautentikasi tidak dapat memanggil fungsi portal');
select t.ok(t.fails(format($q$select * from public.calc_final_rows(%L, %L)$q$, t.v('c_1a'), t.v('sem'))), '8. fungsi hitung internal tidak dapat dipanggil langsung');
select public.reopen_report(t.v('s_a'), t.v('sem'), 'Koreksi nilai UH MTK');
select t.ok((select status from public.report_cards where student_id = t.v('s_a')) = 'draft' and (select snapshot from public.report_cards where student_id = t.v('s_a')) is null, '7. rapor dibuka kembali: kembali draft, snapshot dibuang');
reset role;
set local role service_role;
select t.ok(jsonb_array_length(public.portal_rapor(t.v('s_a'))) = 0, '8. portal: rapor yang dibuka kembali tidak tampil lagi');
reset role;
select t.ok((select count(*) from public.audit_logs where action = 'REOPEN' and detail->>'alasan' = 'Koreksi nilai UH MTK') = 1, '9. pembukaan kembali rapor tercatat di audit log beserta alasan');
select t.ok((select count(*) from public.audit_logs where entity = 'grades' and action = 'INSERT') > 0, '9. perubahan nilai tercatat di audit log');

-- 10. anon
set local role anon;
select t.ok(t.fails('select count(*) from public.grades'), '10. anon tidak dapat membaca nilai');
select t.ok(t.fails('select count(*) from public.report_cards'), '10. anon tidak dapat membaca rapor');
reset role;

-- 12. pratinjau rapor draf (belum ada baris report_cards)
set local role authenticated; select t.as_user('kur_sd');
select t.ok((public.get_report(t.v('s_c'), t.v('sem'))->>'status') = 'draft', '12. kurikulum melihat pratinjau rapor draf (tanpa baris rapor)');
select t.as_user('guru_b');
select t.ok(t.fails(format($q$select public.get_report(%L, %L)$q$, t.v('s_c'), t.v('sem'))), '12. guru mapel tidak dapat membuka rapor');
reset role;

-- 11. daftar bantu antarmuka
set local role authenticated; select t.as_user('guru_a');
select t.ok((select count(*) from public.visible_classes(t.v('sd'))) = 2, '11. guru hanya melihat kelas ajarannya (1A, 1B)');
select t.ok((select count(*) from public.my_assignments(t.v('sd'))) = 2, '11. guru hanya melihat penugasan miliknya');
select t.ok(t.fails(format($q$select * from public.list_teachers(%L)$q$, t.v('sd'))), '11. guru tidak dapat melihat daftar guru');
select t.as_user('wali_a');
select t.ok((select count(*) from public.visible_classes(t.v('sd'))) = 1 and (select is_wali from public.visible_classes(t.v('sd'))), '11. wali kelas melihat kelasnya sebagai wali');
select t.as_user('kur_sd');
select t.ok((select count(*) from public.visible_classes(t.v('sd'))) = 2, '11. kurikulum melihat semua kelas unit');
select t.ok((select count(*) from public.list_teachers(t.v('sd'))) = 3, '11. kurikulum melihat daftar guru unit (guru A, B, wali)');
select t.ok((select count(*) from public.list_assignments(t.v('c_1a'))) = 2, '11. daftar penugasan kelas');
select t.as_user('kur_smp');
select t.ok((select count(*) from public.visible_classes(t.v('sd'))) = 0, '11. kurikulum SMP tidak melihat kelas SD');
select t.ok(t.fails(format($q$select * from public.list_teachers(%L)$q$, t.v('sd'))), '11. kurikulum SMP tidak melihat guru SD');
reset role;

rollback;
select 'SEMUA SKENARIO AKADEMIK SELESAI' as hasil;
