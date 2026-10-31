-- Data uji e2e Fase 4 (setelah seed-e2e.sql). Kata sandi: Passw0rd!
alter table auth.users add column if not exists password text;
insert into auth.users (id, email, password) values
  ('00000000-0000-0000-0000-0000000000b1', 'wali@test.id', 'Passw0rd!'),
  ('00000000-0000-0000-0000-0000000000b2', 'kurikulum@test.id', 'Passw0rd!');
insert into public.profiles (id, full_name, email) select id, initcap(split_part(email, '@', 1)) || ' Uji', email from auth.users where id in ('00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000b2');
insert into public.user_roles (user_id, role, school_id) values
  ('00000000-0000-0000-0000-0000000000b1', 'wali_kelas', (select id from public.schools where code = 'SD')),
  ('00000000-0000-0000-0000-0000000000b2', 'kurikulum', (select id from public.schools where code = 'SD'));
insert into public.class_teachers (school_id, class_id, user_id, role)
select c.school_id, c.id, '00000000-0000-0000-0000-0000000000b1', 'wali_kelas' from public.classes c where c.name = '1A' and c.school_id = (select id from public.schools where code = 'SD');
-- guru@ (a3) mengampu Matematika, guru2@ (a5) mengampu PAI di kelas 1A
insert into public.teaching_assignments (school_id, academic_year_id, class_id, subject_id, teacher_id)
select c.school_id, c.academic_year_id, c.id, sub.id, v.t
  from public.classes c join public.subjects sub on sub.school_id = c.school_id
  join (values ('MTK', '00000000-0000-0000-0000-0000000000a3'::uuid), ('PAI', '00000000-0000-0000-0000-0000000000a5'::uuid)) v(code, t) on v.code = sub.code
 where c.name = '1A' and c.school_id = (select id from public.schools where code = 'SD');
