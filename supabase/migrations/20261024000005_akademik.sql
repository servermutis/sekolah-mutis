-- ======================================================================
-- FASE 4 — MODUL AKADEMIK
-- Mata pelajaran, penugasan guru, jadwal, presensi harian, nilai berbobot, rapor.
-- Prinsip yang sama dengan Fase 3: tulis hanya lewat fungsi (RPC) yang memeriksa
-- kewenangan & unit; RLS membatasi baca; semua perubahan tercatat di audit_logs.
-- ======================================================================

-- ---------- Tabel -------------------------------------------------------
create table public.subjects (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete restrict,
  code text not null check (code ~ '^[A-Z0-9._-]{2,20}$'),
  name text not null check (length(btrim(name)) between 2 and 80),
  kkm integer not null default 75 check (kkm between 0 and 100),
  status text not null default 'aktif' check (status in ('aktif','nonaktif')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (school_id, code),
  unique (id, school_id)
);

create table public.teaching_assignments (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  academic_year_id uuid not null,
  class_id uuid not null,
  subject_id uuid not null,
  teacher_id uuid not null references auth.users(id) on delete restrict,
  hours_per_week integer not null default 2 check (hours_per_week between 1 and 40),
  created_at timestamptz not null default now(),
  unique (class_id, subject_id),
  unique (id, school_id),
  unique (id, class_id),
  foreign key (class_id, school_id) references public.classes(id, school_id) on delete restrict,
  foreign key (class_id, academic_year_id) references public.classes(id, academic_year_id) on delete restrict,
  foreign key (subject_id, school_id) references public.subjects(id, school_id) on delete restrict
);
create index teaching_assignments_teacher_idx on public.teaching_assignments (teacher_id);

create table public.lesson_periods (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  period integer not null check (period between 1 and 15),
  start_time time not null,
  end_time time not null,
  check (end_time > start_time),
  unique (school_id, period)
);

create table public.schedule_slots (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  class_id uuid not null,
  assignment_id uuid not null,
  day integer not null check (day between 1 and 6),   -- 1 = Senin ... 6 = Sabtu
  period integer not null check (period between 1 and 15),
  unique (class_id, day, period),
  foreign key (class_id, school_id) references public.classes(id, school_id) on delete cascade,
  foreign key (assignment_id, class_id) references public.teaching_assignments(id, class_id) on delete cascade
);
create index schedule_slots_assignment_idx on public.schedule_slots (assignment_id);

create table public.attendance_records (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  class_id uuid not null,
  student_id uuid not null,
  att_date date not null,
  status text not null check (status in ('hadir','izin','sakit','alpa','terlambat')),
  note text check (note is null or length(note) <= 200),
  recorded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (student_id, att_date),
  foreign key (class_id, school_id) references public.classes(id, school_id) on delete restrict,
  foreign key (student_id, school_id) references public.students(id, school_id) on delete restrict
);
create index attendance_class_date_idx on public.attendance_records (class_id, att_date);

create table public.assessment_components (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  academic_year_id uuid not null,
  code text not null check (code ~ '^[A-Z0-9._-]{1,12}$'),
  name text not null check (length(btrim(name)) between 2 and 60),
  weight integer not null check (weight between 1 and 100),
  sort_order integer not null default 0,
  unique (academic_year_id, code),
  unique (id, school_id),
  foreign key (academic_year_id, school_id) references public.academic_years(id, school_id) on delete cascade
);

create table public.grades (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  assignment_id uuid not null,
  semester_id uuid not null references public.semesters(id) on delete restrict,
  component_id uuid not null,
  student_id uuid not null,
  title text not null check (length(btrim(title)) between 1 and 60),
  score numeric(5,2) not null check (score between 0 and 100),
  graded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (student_id, assignment_id, semester_id, component_id, title),
  foreign key (assignment_id, school_id) references public.teaching_assignments(id, school_id) on delete restrict,
  foreign key (component_id, school_id) references public.assessment_components(id, school_id) on delete restrict,
  foreign key (student_id, school_id) references public.students(id, school_id) on delete restrict
);
create index grades_assignment_sem_idx on public.grades (assignment_id, semester_id);
create index grades_student_idx on public.grades (student_id, semester_id);

create table public.report_cards (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  student_id uuid not null,
  class_id uuid not null,
  semester_id uuid not null references public.semesters(id) on delete restrict,
  status text not null default 'draft' check (status in ('draft','divalidasi','dipublikasi')),
  homeroom_note text check (homeroom_note is null or length(homeroom_note) <= 1000),
  snapshot jsonb,
  validated_by uuid references auth.users(id) on delete set null,
  validated_at timestamptz,
  published_by uuid references auth.users(id) on delete set null,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (student_id, semester_id),
  foreign key (student_id, school_id) references public.students(id, school_id) on delete restrict,
  foreign key (class_id, school_id) references public.classes(id, school_id) on delete restrict
);
create index report_cards_class_sem_idx on public.report_cards (class_id, semester_id);

create trigger subjects_touch before update on public.subjects for each row execute function public.touch_updated_at();
create trigger attendance_touch before update on public.attendance_records for each row execute function public.touch_updated_at();
create trigger grades_touch before update on public.grades for each row execute function public.touch_updated_at();
create trigger report_cards_touch before update on public.report_cards for each row execute function public.touch_updated_at();

-- Audit
create trigger audit_subjects after insert or update or delete on public.subjects for each row execute function public.audit_row();
create trigger audit_teaching_assignments after insert or update or delete on public.teaching_assignments for each row execute function public.audit_row();
create trigger audit_lesson_periods after insert or update or delete on public.lesson_periods for each row execute function public.audit_row();
create trigger audit_schedule_slots after insert or update or delete on public.schedule_slots for each row execute function public.audit_row();
create trigger audit_attendance after insert or update or delete on public.attendance_records for each row execute function public.audit_row();
create trigger audit_components after insert or update or delete on public.assessment_components for each row execute function public.audit_row();
create trigger audit_grades after insert or update or delete on public.grades for each row execute function public.audit_row();
create trigger audit_report_cards after insert or update or delete on public.report_cards for each row execute function public.audit_row();

-- ---------- Pemeriksaan data ---------------------------------------------
-- Guru pengampu harus memegang peran guru/wali_kelas pada unit yang sama.
create or replace function public.ta_check()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.user_roles ur
                  where ur.user_id = new.teacher_id and ur.school_id = new.school_id and ur.role in ('guru','wali_kelas')) then
    raise exception 'Guru pengampu harus memiliki peran Guru atau Wali Kelas pada unit ini' using errcode = '22023';
  end if;
  return new;
end $$;
create trigger teaching_assignments_check before insert or update on public.teaching_assignments
  for each row execute function public.ta_check();

-- Satu guru tidak boleh mengajar di dua kelas pada hari & jam yang sama.
create or replace function public.slot_conflict_check()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_teacher uuid; v_other text; v_name text;
begin
  select teacher_id into v_teacher from public.teaching_assignments where id = new.assignment_id;
  select c.name, p.full_name into v_other, v_name
    from public.schedule_slots s
    join public.teaching_assignments ta on ta.id = s.assignment_id
    join public.classes c on c.id = s.class_id
    left join public.profiles p on p.id = ta.teacher_id
   where ta.teacher_id = v_teacher and s.day = new.day and s.period = new.period and s.id <> new.id
   limit 1;
  if v_other is not null then
    raise exception 'Jadwal bentrok: % sudah mengajar di kelas % pada hari dan jam tersebut', coalesce(v_name, 'Guru'), v_other using errcode = '23505';
  end if;
  return new;
end $$;
create trigger schedule_slots_conflict before insert or update on public.schedule_slots
  for each row execute function public.slot_conflict_check();

-- ---------- Fungsi bantu kewenangan --------------------------------------
create or replace function public.is_curriculum(p_school uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.has_role(p_school, array['admin_sekolah','kurikulum'])
$$;

create or replace function public.can_view_class(p_class uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.classes c
    where c.id = p_class
      and (public.has_role(c.school_id, array['kepala_sekolah','admin_sekolah','kurikulum','kesiswaan','bk'])
           or exists (select 1 from public.class_teachers ct where ct.class_id = c.id and ct.user_id = auth.uid())
           or exists (select 1 from public.teaching_assignments ta where ta.class_id = c.id and ta.teacher_id = auth.uid()))
  )
$$;

create or replace function public.can_take_attendance(p_class uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.classes c
    where c.id = p_class
      and (public.has_role(c.school_id, array['admin_sekolah','kesiswaan'])
           or exists (select 1 from public.class_teachers ct where ct.class_id = c.id and ct.user_id = auth.uid()))
  )
$$;

create or replace function public.is_homeroom_of_class(p_class uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.class_teachers ct where ct.class_id = p_class and ct.user_id = auth.uid() and ct.role = 'wali_kelas')
$$;

create or replace function public.can_grade(p_assignment uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.teaching_assignments ta
    where ta.id = p_assignment
      and (public.has_role(ta.school_id, array['admin_sekolah','kurikulum'])
           or (ta.teacher_id = auth.uid() and public.has_role(ta.school_id, array['guru','wali_kelas'])))
  )
$$;

create or replace function public.grade_letter(p numeric)
returns text language sql immutable as $$
  select case when p is null then null when p >= 90 then 'A' when p >= 80 then 'B' when p >= 70 then 'C' else 'D' end
$$;

-- ---------- RLS ----------------------------------------------------------
alter table public.subjects enable row level security;
alter table public.teaching_assignments enable row level security;
alter table public.lesson_periods enable row level security;
alter table public.schedule_slots enable row level security;
alter table public.attendance_records enable row level security;
alter table public.assessment_components enable row level security;
alter table public.grades enable row level security;
alter table public.report_cards enable row level security;

create policy subjects_select on public.subjects for select to authenticated using (public.is_member(school_id));
create policy subjects_write on public.subjects for all to authenticated
  using (public.is_curriculum(school_id)) with check (public.is_curriculum(school_id));

create policy ta_select on public.teaching_assignments for select to authenticated using (public.can_view_class(class_id));
create policy ta_write on public.teaching_assignments for all to authenticated
  using (public.is_curriculum(school_id)) with check (public.is_curriculum(school_id));

create policy periods_select on public.lesson_periods for select to authenticated using (public.is_member(school_id));
create policy periods_write on public.lesson_periods for all to authenticated
  using (public.is_curriculum(school_id)) with check (public.is_curriculum(school_id));

create policy slots_select on public.schedule_slots for select to authenticated using (public.can_view_class(class_id));
create policy att_select on public.attendance_records for select to authenticated using (public.can_view_class(class_id));

create policy comps_select on public.assessment_components for select to authenticated using (public.is_member(school_id));
create policy comps_write on public.assessment_components for all to authenticated
  using (public.is_curriculum(school_id)) with check (public.is_curriculum(school_id));

create policy grades_select on public.grades for select to authenticated
  using (public.has_role(school_id, array['kepala_sekolah','admin_sekolah','kurikulum'])
         or exists (select 1 from public.teaching_assignments ta where ta.id = assignment_id and ta.teacher_id = auth.uid())
         or public.is_homeroom_of(student_id));
create policy rc_select on public.report_cards for select to authenticated
  using (public.has_role(school_id, array['kepala_sekolah','admin_sekolah','kurikulum']) or public.is_homeroom_of_class(class_id));

-- Hak tingkat tabel (tabel baru mewarisi grant bawaan Supabase, jadi cabut dulu)
revoke all on public.subjects, public.teaching_assignments, public.lesson_periods, public.schedule_slots,
  public.attendance_records, public.assessment_components, public.grades, public.report_cards from anon, authenticated;
grant select on public.subjects, public.teaching_assignments, public.lesson_periods, public.schedule_slots,
  public.attendance_records, public.assessment_components, public.grades, public.report_cards to authenticated;
grant insert, update, delete on public.subjects, public.teaching_assignments, public.lesson_periods,
  public.assessment_components to authenticated;

-- ---------- Presensi harian ----------------------------------------------
create or replace function public.list_attendance(p_class uuid, p_date date)
returns table (student_id uuid, nis text, full_name text, status text, note text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.can_view_class(p_class) then raise exception 'Anda tidak berwenang melihat kelas ini' using errcode = '42501'; end if;
  return query
    select s.id, s.nis, s.full_name, a.status, a.note
      from public.student_enrollments e
      join public.students s on s.id = e.student_id and s.status = 'aktif'
      left join public.attendance_records a on a.student_id = s.id and a.att_date = p_date
     where e.class_id = p_class
     order by s.full_name;
end $$;

create or replace function public.save_attendance(p_class uuid, p_date date, p_entries jsonb)
returns integer language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_cls public.classes; v_manager boolean; v_tot integer; v_dist integer; v_valid integer; v_n integer;
begin
  if v_uid is null then raise exception 'Sesi tidak valid' using errcode = '42501'; end if;
  select * into v_cls from public.classes where id = p_class;
  if not found or not public.can_take_attendance(p_class) then
    raise exception 'Anda tidak berwenang mengisi presensi kelas ini' using errcode = '42501';
  end if;
  v_manager := public.has_role(v_cls.school_id, array['admin_sekolah','kesiswaan']);
  if p_date is null or p_date > public.today_wib() then raise exception 'Tanggal presensi tidak valid' using errcode = '22023'; end if;
  if p_date < public.today_wib() - (case when v_manager then 366 else 7 end) then
    raise exception 'Presensi yang lebih dari 7 hari lalu hanya dapat diubah oleh kesiswaan atau admin sekolah' using errcode = '42501';
  end if;
  if p_entries is null or jsonb_typeof(p_entries) <> 'array' or jsonb_array_length(p_entries) not between 1 and 200 then
    raise exception 'Data presensi tidak valid' using errcode = '22023';
  end if;

  select count(*), count(distinct e.sid),
         count(*) filter (where e.st in ('hadir','izin','sakit','alpa','terlambat') and en.student_id is not null and s.status = 'aktif')
    into v_tot, v_dist, v_valid
    from (select (x->>'student_id')::uuid sid, x->>'status' st from jsonb_array_elements(p_entries) x) e
    left join public.student_enrollments en on en.student_id = e.sid and en.class_id = p_class
    left join public.students s on s.id = e.sid;
  if v_dist <> v_tot then raise exception 'Data presensi memuat siswa ganda' using errcode = '22023'; end if;
  if v_valid <> v_tot then raise exception 'Data presensi memuat siswa di luar kelas atau status tidak valid' using errcode = '22023'; end if;

  insert into public.attendance_records (school_id, class_id, student_id, att_date, status, note, recorded_by)
  select v_cls.school_id, p_class, (x->>'student_id')::uuid, p_date, x->>'status',
         nullif(left(btrim(coalesce(x->>'note','')), 200), ''), v_uid
    from jsonb_array_elements(p_entries) x
  on conflict (student_id, att_date) do update
    set class_id = excluded.class_id, status = excluded.status, note = excluded.note, recorded_by = excluded.recorded_by
    where (public.attendance_records.status, public.attendance_records.note) is distinct from (excluded.status, excluded.note);
  get diagnostics v_n = row_count;
  return v_n;
end $$;

create or replace function public.attendance_summary(p_class uuid, p_from date, p_to date)
returns table (student_id uuid, nis text, full_name text, hadir bigint, izin bigint, sakit bigint, alpa bigint, terlambat bigint, hari bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.can_view_class(p_class) then raise exception 'Anda tidak berwenang melihat kelas ini' using errcode = '42501'; end if;
  return query
    select s.id, s.nis, s.full_name,
           count(a.id) filter (where a.status = 'hadir'), count(a.id) filter (where a.status = 'izin'),
           count(a.id) filter (where a.status = 'sakit'), count(a.id) filter (where a.status = 'alpa'),
           count(a.id) filter (where a.status = 'terlambat'), count(a.id)
      from public.student_enrollments e
      join public.students s on s.id = e.student_id and s.status = 'aktif'
      left join public.attendance_records a on a.student_id = s.id and a.att_date between coalesce(p_from, date '1900-01-01') and coalesce(p_to, date '2999-12-31')
     where e.class_id = p_class
     group by s.id, s.nis, s.full_name
     order by s.full_name;
end $$;

-- Ringkasan hari ini untuk dashboard pimpinan
create or replace function public.attendance_today(p_school uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  if not public.has_role(p_school, array['kepala_sekolah','admin_sekolah','kurikulum','kesiswaan']) then
    raise exception 'Tidak berwenang' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'hadir', count(*) filter (where a.status = 'hadir'), 'izin', count(*) filter (where a.status = 'izin'),
    'sakit', count(*) filter (where a.status = 'sakit'), 'alpa', count(*) filter (where a.status = 'alpa'),
    'terlambat', count(*) filter (where a.status = 'terlambat'), 'total', count(*),
    'kelas_terisi', count(distinct a.class_id),
    'kelas_total', (select count(*) from public.classes c join public.academic_years ay on ay.id = c.academic_year_id and ay.is_active where c.school_id = p_school))
   into v
   from public.attendance_records a where a.school_id = p_school and a.att_date = public.today_wib();
  return v;
end $$;

-- ---------- Daftar kelas (roster) -----------------------------------------
create or replace function public.class_roster(p_class uuid)
returns table (student_id uuid, nis text, full_name text, gender text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.can_view_class(p_class) then raise exception 'Anda tidak berwenang melihat kelas ini' using errcode = '42501'; end if;
  return query
    select s.id, s.nis, s.full_name, s.gender from public.student_enrollments e
      join public.students s on s.id = e.student_id and s.status = 'aktif'
     where e.class_id = p_class order by s.full_name;
end $$;

-- ---------- Jadwal ---------------------------------------------------------
create or replace function public.save_schedule_slot(p_class uuid, p_day integer, p_period integer, p_assignment uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_cls public.classes;
begin
  select * into v_cls from public.classes where id = p_class;
  if not found or not public.is_curriculum(v_cls.school_id) then raise exception 'Anda tidak berwenang mengatur jadwal' using errcode = '42501'; end if;
  if p_day not between 1 and 6 or p_period not between 1 and 15 then raise exception 'Hari atau jam ke- tidak valid' using errcode = '22023'; end if;
  if p_assignment is null then
    delete from public.schedule_slots where class_id = p_class and day = p_day and period = p_period;
    return;
  end if;
  if not exists (select 1 from public.teaching_assignments where id = p_assignment and class_id = p_class) then
    raise exception 'Penugasan tidak sesuai dengan kelas' using errcode = '22023';
  end if;
  insert into public.schedule_slots (school_id, class_id, assignment_id, day, period)
  values (v_cls.school_id, p_class, p_assignment, p_day, p_period)
  on conflict (class_id, day, period) do update set assignment_id = excluded.assignment_id;
end $$;

create or replace function public.list_schedule(p_class uuid)
returns table (slot_id uuid, day integer, period integer, assignment_id uuid, subject_id uuid, subject_name text, teacher_name text, start_time time, end_time time)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.can_view_class(p_class) then raise exception 'Anda tidak berwenang melihat kelas ini' using errcode = '42501'; end if;
  return query
    select s.id, s.day, s.period, ta.id, sub.id, sub.name, p.full_name, lp.start_time, lp.end_time
      from public.schedule_slots s
      join public.teaching_assignments ta on ta.id = s.assignment_id
      join public.subjects sub on sub.id = ta.subject_id
      left join public.profiles p on p.id = ta.teacher_id
      left join public.lesson_periods lp on lp.school_id = s.school_id and lp.period = s.period
     where s.class_id = p_class
     order by s.day, s.period;
end $$;

create or replace function public.my_schedule(p_school uuid)
returns table (day integer, period integer, class_id uuid, class_name text, subject_name text, start_time time, end_time time)
language sql stable security definer set search_path = public as $$
  select s.day, s.period, c.id, c.name, sub.name, lp.start_time, lp.end_time
    from public.schedule_slots s
    join public.teaching_assignments ta on ta.id = s.assignment_id and ta.teacher_id = auth.uid()
    join public.classes c on c.id = s.class_id
    join public.academic_years ay on ay.id = c.academic_year_id and ay.is_active
    join public.subjects sub on sub.id = ta.subject_id
    left join public.lesson_periods lp on lp.school_id = s.school_id and lp.period = s.period
   where s.school_id = p_school
   order by s.day, s.period
$$;

-- ---------- Nilai ----------------------------------------------------------
create or replace function public.save_grades(p_assignment uuid, p_semester uuid, p_component uuid, p_title text, p_scores jsonb)
returns integer language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_ta public.teaching_assignments; v_title text := btrim(coalesce(p_title, ''));
        v_tot integer; v_dist integer; v_ok integer; v_locked integer; v_n integer;
begin
  if v_uid is null then raise exception 'Sesi tidak valid' using errcode = '42501'; end if;
  select * into v_ta from public.teaching_assignments where id = p_assignment;
  if not found or not public.can_grade(p_assignment) then raise exception 'Anda tidak berwenang mengisi nilai untuk mata pelajaran ini' using errcode = '42501'; end if;
  if not exists (select 1 from public.semesters where id = p_semester and academic_year_id = v_ta.academic_year_id) then
    raise exception 'Semester tidak sesuai dengan tahun ajaran kelas' using errcode = '22023';
  end if;
  if not exists (select 1 from public.assessment_components where id = p_component and academic_year_id = v_ta.academic_year_id) then
    raise exception 'Komponen penilaian tidak valid' using errcode = '22023';
  end if;
  if length(v_title) not between 1 and 60 then raise exception 'Judul penilaian harus 1-60 karakter' using errcode = '22023'; end if;
  if p_scores is null or jsonb_typeof(p_scores) <> 'array' or jsonb_array_length(p_scores) not between 1 and 200 then
    raise exception 'Data nilai tidak valid' using errcode = '22023';
  end if;

  select count(*), count(distinct q.sid),
         count(*) filter (where en.student_id is not null and (q.sc is null or (q.sc >= 0 and q.sc <= 100)))
    into v_tot, v_dist, v_ok
    from (select (x->>'student_id')::uuid sid, nullif(x->>'score', '')::numeric sc from jsonb_array_elements(p_scores) x) q
    left join public.student_enrollments en on en.student_id = q.sid and en.class_id = v_ta.class_id;
  if v_dist <> v_tot then raise exception 'Data nilai memuat siswa ganda' using errcode = '22023'; end if;
  if v_ok <> v_tot then raise exception 'Nilai harus 0-100 dan siswa harus berada di kelas ini' using errcode = '22023'; end if;

  select count(*) into v_locked from public.report_cards rc
   where rc.semester_id = p_semester and rc.status <> 'draft'
     and rc.student_id in (select (x->>'student_id')::uuid from jsonb_array_elements(p_scores) x);
  if v_locked > 0 then
    raise exception 'Rapor sudah divalidasi/dipublikasi untuk % siswa. Minta bagian kurikulum membuka kembali rapor sebelum mengubah nilai', v_locked using errcode = '42501';
  end if;

  delete from public.grades g
   using (select (x->>'student_id')::uuid sid from jsonb_array_elements(p_scores) x where nullif(x->>'score', '') is null) d
   where g.student_id = d.sid and g.assignment_id = p_assignment and g.semester_id = p_semester
     and g.component_id = p_component and g.title = v_title;

  insert into public.grades (school_id, assignment_id, semester_id, component_id, student_id, title, score, graded_by)
  select v_ta.school_id, p_assignment, p_semester, p_component, (x->>'student_id')::uuid, v_title, round((x->>'score')::numeric, 2), v_uid
    from jsonb_array_elements(p_scores) x where nullif(x->>'score', '') is not null
  on conflict (student_id, assignment_id, semester_id, component_id, title) do update
    set score = excluded.score, graded_by = excluded.graded_by
    where public.grades.score is distinct from excluded.score;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

create or replace function public.list_grades(p_assignment uuid, p_semester uuid)
returns table (student_id uuid, component_id uuid, title text, score numeric)
language plpgsql stable security definer set search_path = public as $$
declare v_ta public.teaching_assignments;
begin
  select * into v_ta from public.teaching_assignments where id = p_assignment;
  if not found or not (public.can_grade(p_assignment)
       or public.has_role(v_ta.school_id, array['kepala_sekolah'])
       or public.is_homeroom_of_class(v_ta.class_id)) then
    raise exception 'Anda tidak berwenang melihat nilai ini' using errcode = '42501';
  end if;
  return query select g.student_id, g.component_id, g.title, g.score from public.grades g
    where g.assignment_id = p_assignment and g.semester_id = p_semester order by g.component_id, g.title;
end $$;

-- Hitung nilai akhir (internal; tidak diberikan ke pengguna)
-- Rata-rata per komponen, lalu dibobot hanya atas komponen yang sudah terisi.
create or replace function public.calc_final_rows(p_class uuid, p_semester uuid)
returns table (student_id uuid, assignment_id uuid, subject_id uuid, final_score numeric, filled integer, total integer)
language sql stable security definer set search_path = public as $$
  with cls as (select c.academic_year_id from public.classes c where c.id = p_class),
  comps as (select ac.id, ac.weight from public.assessment_components ac join cls on ac.academic_year_id = cls.academic_year_id),
  tot as (select count(*)::integer n from comps),
  pc as (
    select g.student_id, g.assignment_id, g.component_id, avg(g.score) a
      from public.grades g join public.teaching_assignments ta on ta.id = g.assignment_id
     where ta.class_id = p_class and g.semester_id = p_semester
     group by g.student_id, g.assignment_id, g.component_id),
  agg as (
    select pc.student_id, pc.assignment_id,
           round(sum(pc.a * comps.weight) / nullif(sum(comps.weight), 0), 2) fin, count(*)::integer filled
      from pc join comps on comps.id = pc.component_id group by pc.student_id, pc.assignment_id)
  select en.student_id, ta.id, ta.subject_id, agg.fin, coalesce(agg.filled, 0), tot.n
    from public.student_enrollments en
    join public.students s on s.id = en.student_id and s.status = 'aktif'
    join public.teaching_assignments ta on ta.class_id = en.class_id
    left join agg on agg.student_id = en.student_id and agg.assignment_id = ta.id
    cross join tot
   where en.class_id = p_class
$$;

create or replace function public.rekap_nilai(p_class uuid, p_semester uuid)
returns table (student_id uuid, nis text, full_name text, assignment_id uuid, subject_id uuid, subject_name text, kkm integer,
               final_score numeric, predikat text, filled integer, total integer, lengkap boolean, tuntas boolean)
language plpgsql stable security definer set search_path = public as $$
declare v_cls public.classes; v_uid uuid := auth.uid(); v_all boolean;
begin
  select * into v_cls from public.classes where id = p_class;
  if not found then raise exception 'Kelas tidak ditemukan' using errcode = '22023'; end if;
  v_all := public.has_role(v_cls.school_id, array['kepala_sekolah','admin_sekolah','kurikulum']) or public.is_homeroom_of_class(p_class);
  if not (v_all or exists (select 1 from public.teaching_assignments ta where ta.class_id = p_class and ta.teacher_id = v_uid)) then
    raise exception 'Anda tidak berwenang melihat rekap nilai kelas ini' using errcode = '42501';
  end if;
  return query
    select f.student_id, s.nis, s.full_name, f.assignment_id, f.subject_id, sub.name, sub.kkm, f.final_score,
           public.grade_letter(f.final_score), f.filled, f.total, (f.total > 0 and f.filled = f.total),
           (f.final_score is not null and f.final_score >= sub.kkm)
      from public.calc_final_rows(p_class, p_semester) f
      join public.students s on s.id = f.student_id
      join public.subjects sub on sub.id = f.subject_id
      join public.teaching_assignments ta on ta.id = f.assignment_id
     where v_all or ta.teacher_id = v_uid
     order by s.full_name, sub.name;
end $$;

-- ---------- Rapor ----------------------------------------------------------
create or replace function public.build_snapshot(p_student uuid, p_semester uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_sem public.semesters; v_class uuid; v_st public.students; v_cname text; v_year text; v_subjects jsonb; v_att jsonb;
begin
  select * into v_sem from public.semesters where id = p_semester;
  select * into v_st from public.students where id = p_student;
  select e.class_id, c.name into v_class, v_cname
    from public.student_enrollments e join public.classes c on c.id = e.class_id
   where e.student_id = p_student and e.academic_year_id = v_sem.academic_year_id;
  select year_name into v_year from public.academic_years where id = v_sem.academic_year_id;
  select coalesce(jsonb_agg(jsonb_build_object('mapel', sub.name, 'kkm', sub.kkm, 'nilai', f.final_score,
           'predikat', public.grade_letter(f.final_score), 'tuntas', (f.final_score is not null and f.final_score >= sub.kkm),
           'lengkap', (f.total > 0 and f.filled = f.total)) order by sub.name), '[]'::jsonb)
    into v_subjects
    from public.calc_final_rows(v_class, p_semester) f join public.subjects sub on sub.id = f.subject_id
   where f.student_id = p_student;
  select jsonb_build_object('hadir', count(*) filter (where a.status = 'hadir'), 'izin', count(*) filter (where a.status = 'izin'),
           'sakit', count(*) filter (where a.status = 'sakit'), 'alpa', count(*) filter (where a.status = 'alpa'),
           'terlambat', count(*) filter (where a.status = 'terlambat'), 'hari', count(*))
    into v_att
    from public.attendance_records a where a.student_id = p_student and a.att_date between v_sem.start_date and v_sem.end_date;
  return jsonb_build_object('nis', v_st.nis, 'nama', v_st.full_name, 'kelas', v_cname, 'semester', v_sem.name,
                            'tahun_ajaran', v_year, 'mapel', v_subjects, 'kehadiran', v_att, 'dibuat', now());
end $$;

create or replace function public.list_reports(p_class uuid, p_semester uuid)
returns table (student_id uuid, nis text, full_name text, report_id uuid, status text, homeroom_note text,
               subjects_total integer, subjects_complete integer, average numeric, ready boolean)
language plpgsql stable security definer set search_path = public as $$
declare v_cls public.classes;
begin
  select * into v_cls from public.classes where id = p_class;
  if not found or not (public.has_role(v_cls.school_id, array['kepala_sekolah','admin_sekolah','kurikulum']) or public.is_homeroom_of_class(p_class)) then
    raise exception 'Anda tidak berwenang melihat rapor kelas ini' using errcode = '42501';
  end if;
  return query
    select s.id, s.nis, s.full_name, rc.id, coalesce(rc.status, 'draft'), rc.homeroom_note,
           count(f.assignment_id)::integer,
           (count(f.assignment_id) filter (where f.total > 0 and f.filled = f.total))::integer,
           round(avg(f.final_score), 2),
           (count(f.assignment_id) > 0 and count(f.assignment_id) = count(f.assignment_id) filter (where f.total > 0 and f.filled = f.total))
      from public.student_enrollments e
      join public.students s on s.id = e.student_id and s.status = 'aktif'
      left join public.calc_final_rows(p_class, p_semester) f on f.student_id = s.id
      left join public.report_cards rc on rc.student_id = s.id and rc.semester_id = p_semester
     where e.class_id = p_class
     group by s.id, s.nis, s.full_name, rc.id, rc.status, rc.homeroom_note
     order by s.full_name;
end $$;

create or replace function public.save_homeroom_note(p_student uuid, p_semester uuid, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare v_sem public.semesters; v_class uuid; v_school uuid; v_status text;
begin
  select * into v_sem from public.semesters where id = p_semester;
  select e.class_id, e.school_id into v_class, v_school from public.student_enrollments e
   where e.student_id = p_student and e.academic_year_id = v_sem.academic_year_id;
  if v_class is null then raise exception 'Siswa tidak terdaftar pada tahun ajaran semester ini' using errcode = '22023'; end if;
  if not (public.is_homeroom_of_class(v_class) or public.is_curriculum(v_school)) then
    raise exception 'Hanya wali kelas atau bagian kurikulum yang dapat mengisi catatan' using errcode = '42501';
  end if;
  if length(coalesce(p_note, '')) > 1000 then raise exception 'Catatan maksimal 1000 karakter' using errcode = '22023'; end if;
  select status into v_status from public.report_cards where student_id = p_student and semester_id = p_semester;
  if v_status is not null and v_status <> 'draft' then
    raise exception 'Rapor sudah divalidasi/dipublikasi; buka kembali rapor untuk mengubah catatan' using errcode = '42501';
  end if;
  insert into public.report_cards (school_id, student_id, class_id, semester_id, homeroom_note)
  values (v_school, p_student, v_class, p_semester, nullif(btrim(coalesce(p_note, '')), ''))
  on conflict (student_id, semester_id) do update set homeroom_note = excluded.homeroom_note, class_id = excluded.class_id;
end $$;

create or replace function public.validate_reports(p_class uuid, p_semester uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_cls public.classes; v_sem public.semesters; r record; v_ok integer := 0; v_skip integer := 0; v_pub integer := 0;
begin
  select * into v_cls from public.classes where id = p_class;
  if not found or not public.is_curriculum(v_cls.school_id) then raise exception 'Hanya bagian kurikulum yang dapat memvalidasi rapor' using errcode = '42501'; end if;
  select * into v_sem from public.semesters where id = p_semester and academic_year_id = v_cls.academic_year_id;
  if not found then raise exception 'Semester tidak sesuai dengan tahun ajaran kelas' using errcode = '22023'; end if;
  for r in
    select s.id sid, rc.status st,
           (count(f.assignment_id) > 0 and count(f.assignment_id) = count(f.assignment_id) filter (where f.total > 0 and f.filled = f.total)) ready
      from public.student_enrollments e
      join public.students s on s.id = e.student_id and s.status = 'aktif'
      left join public.calc_final_rows(p_class, p_semester) f on f.student_id = s.id
      left join public.report_cards rc on rc.student_id = s.id and rc.semester_id = p_semester
     where e.class_id = p_class
     group by s.id, rc.status
  loop
    if r.st = 'dipublikasi' then v_pub := v_pub + 1;
    elsif not r.ready then v_skip := v_skip + 1;
    else
      insert into public.report_cards (school_id, student_id, class_id, semester_id, status, snapshot, validated_by, validated_at)
      values (v_cls.school_id, r.sid, p_class, p_semester, 'divalidasi', public.build_snapshot(r.sid, p_semester), auth.uid(), now())
      on conflict (student_id, semester_id) do update
        set status = 'divalidasi', snapshot = excluded.snapshot, validated_by = excluded.validated_by, validated_at = excluded.validated_at, class_id = excluded.class_id;
      v_ok := v_ok + 1;
    end if;
  end loop;
  return jsonb_build_object('divalidasi', v_ok, 'belum_lengkap', v_skip, 'sudah_terbit', v_pub);
end $$;

create or replace function public.publish_reports(p_class uuid, p_semester uuid)
returns integer language plpgsql security definer set search_path = public as $$
declare v_cls public.classes; v_n integer;
begin
  select * into v_cls from public.classes where id = p_class;
  if not found or not public.has_role(v_cls.school_id, array['kepala_sekolah','admin_sekolah','kurikulum']) then
    raise exception 'Anda tidak berwenang menerbitkan rapor' using errcode = '42501';
  end if;
  update public.report_cards set status = 'dipublikasi', published_by = auth.uid(), published_at = now()
   where class_id = p_class and semester_id = p_semester and status = 'divalidasi';
  get diagnostics v_n = row_count;
  perform public.log_event(auth.uid(), 'PUBLISH', 'report_cards', p_class::text, v_cls.school_id, jsonb_build_object('semester_id', p_semester, 'jumlah', v_n));
  return v_n;
end $$;

create or replace function public.reopen_report(p_student uuid, p_semester uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_rc public.report_cards;
begin
  select * into v_rc from public.report_cards where student_id = p_student and semester_id = p_semester;
  if not found then raise exception 'Rapor belum dibuat' using errcode = '22023'; end if;
  if not public.is_curriculum(v_rc.school_id) then raise exception 'Hanya bagian kurikulum yang dapat membuka kembali rapor' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_reason, ''))) < 5 then raise exception 'Alasan membuka kembali rapor wajib diisi (min. 5 karakter)' using errcode = '22023'; end if;
  update public.report_cards set status = 'draft', snapshot = null, validated_by = null, validated_at = null, published_by = null, published_at = null
   where id = v_rc.id;
  perform public.log_event(auth.uid(), 'REOPEN', 'report_cards', v_rc.id::text, v_rc.school_id, jsonb_build_object('alasan', btrim(p_reason), 'status_sebelumnya', v_rc.status));
end $$;

create or replace function public.get_report(p_student uuid, p_semester uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_rc public.report_cards; v_school uuid; v_class uuid;
begin
  select * into v_rc from public.report_cards where student_id = p_student and semester_id = p_semester;
  if found then v_school := v_rc.school_id; v_class := v_rc.class_id;
  else
    select e.school_id, e.class_id into v_school, v_class
      from public.student_enrollments e join public.semesters sm on sm.academic_year_id = e.academic_year_id
     where e.student_id = p_student and sm.id = p_semester;
    if v_class is null then raise exception 'Rapor belum tersedia' using errcode = '22023'; end if;
  end if;
  if not (public.has_role(v_school, array['kepala_sekolah','admin_sekolah','kurikulum']) or public.is_homeroom_of_class(v_class)) then
    raise exception 'Anda tidak berwenang melihat rapor ini' using errcode = '42501';
  end if;
  return coalesce(v_rc.snapshot, public.build_snapshot(p_student, p_semester))
         || jsonb_build_object('status', coalesce(v_rc.status, 'draft'), 'catatan_wali', v_rc.homeroom_note);
end $$;

-- ---------- Portal siswa (hanya service role; identitas dari sesi server) ---
create or replace function public.portal_jadwal(p_student uuid)
returns table (day integer, period integer, subject_name text, teacher_name text, start_time time, end_time time)
language sql stable security definer set search_path = public as $$
  select s.day, s.period, sub.name, p.full_name, lp.start_time, lp.end_time
    from public.student_enrollments e
    join public.academic_years ay on ay.id = e.academic_year_id and ay.is_active
    join public.students st on st.id = e.student_id and st.status = 'aktif'
    join public.schedule_slots s on s.class_id = e.class_id
    join public.teaching_assignments ta on ta.id = s.assignment_id
    join public.subjects sub on sub.id = ta.subject_id
    left join public.profiles p on p.id = ta.teacher_id
    left join public.lesson_periods lp on lp.school_id = s.school_id and lp.period = s.period
   where e.student_id = p_student
   order by s.day, s.period
$$;

create or replace function public.portal_kehadiran(p_student uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  with yr as (
    select min(sm.start_date) d1 from public.semesters sm
      join public.academic_years ay on ay.id = sm.academic_year_id and ay.is_active
      join public.students st on st.school_id = ay.school_id and st.id = p_student),
  a as (select * from public.attendance_records r, yr where r.student_id = p_student and r.att_date >= yr.d1)
  select jsonb_build_object(
    'ringkasan', jsonb_build_object('hadir', count(*) filter (where status = 'hadir'), 'izin', count(*) filter (where status = 'izin'),
       'sakit', count(*) filter (where status = 'sakit'), 'alpa', count(*) filter (where status = 'alpa'),
       'terlambat', count(*) filter (where status = 'terlambat'), 'hari', count(*)),
    'terbaru', coalesce((select jsonb_agg(jsonb_build_object('tanggal', att_date, 'status', status, 'catatan', note) order by att_date desc)
                           from (select * from a order by att_date desc limit 30) x), '[]'::jsonb))
  from a
$$;

create or replace function public.portal_rapor(p_student uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(rc.snapshot || jsonb_build_object('catatan_wali', rc.homeroom_note, 'diterbitkan', rc.published_at)
                            order by rc.published_at desc), '[]'::jsonb)
    from public.report_cards rc
   where rc.student_id = p_student and rc.status = 'dipublikasi' and rc.snapshot is not null
$$;

-- ---------- Daftar bantu untuk antarmuka -------------------------------------
create or replace function public.visible_classes(p_school uuid)
returns table (id uuid, name text, is_wali boolean, can_attend boolean)
language sql stable security definer set search_path = public as $$
  select c.id, c.name,
         exists (select 1 from public.class_teachers ct where ct.class_id = c.id and ct.user_id = auth.uid() and ct.role = 'wali_kelas'),
         public.can_take_attendance(c.id)
    from public.classes c
    join public.academic_years ay on ay.id = c.academic_year_id and ay.is_active
   where c.school_id = p_school and public.can_view_class(c.id)
   order by c.name
$$;

create or replace function public.list_assignments(p_class uuid)
returns table (id uuid, class_id uuid, subject_id uuid, subject_name text, kkm integer, teacher_id uuid, teacher_name text, hours_per_week integer)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.can_view_class(p_class) then raise exception 'Anda tidak berwenang melihat kelas ini' using errcode = '42501'; end if;
  return query
    select ta.id, ta.class_id, sub.id, sub.name, sub.kkm, ta.teacher_id, p.full_name, ta.hours_per_week
      from public.teaching_assignments ta
      join public.subjects sub on sub.id = ta.subject_id
      left join public.profiles p on p.id = ta.teacher_id
     where ta.class_id = p_class order by sub.name;
end $$;

-- Penugasan yang boleh diisi nilainya oleh pengguna (guru: miliknya; kurikulum/admin: semua unit)
create or replace function public.my_assignments(p_school uuid)
returns table (id uuid, class_id uuid, class_name text, subject_id uuid, subject_name text, kkm integer)
language sql stable security definer set search_path = public as $$
  select ta.id, c.id, c.name, sub.id, sub.name, sub.kkm
    from public.teaching_assignments ta
    join public.classes c on c.id = ta.class_id
    join public.academic_years ay on ay.id = c.academic_year_id and ay.is_active
    join public.subjects sub on sub.id = ta.subject_id
   where ta.school_id = p_school and public.can_grade(ta.id)
   order by c.name, sub.name
$$;

create or replace function public.list_teachers(p_school uuid)
returns table (user_id uuid, full_name text, roles text[])
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_role(p_school, array['kepala_sekolah','admin_sekolah','kurikulum']) then
    raise exception 'Tidak berwenang' using errcode = '42501';
  end if;
  return query
    select ur.user_id, coalesce(p.full_name, 'Pengguna'), array_agg(distinct ur.role order by ur.role)
      from public.user_roles ur left join public.profiles p on p.id = ur.user_id
     where ur.school_id = p_school and ur.role in ('guru','wali_kelas')
     group by ur.user_id, p.full_name order by 2;
end $$;

-- ---------- Hak eksekusi ---------------------------------------------------
revoke execute on function
  public.ta_check(), public.slot_conflict_check(), public.is_curriculum(uuid), public.can_view_class(uuid),
  public.can_take_attendance(uuid), public.is_homeroom_of_class(uuid), public.can_grade(uuid), public.grade_letter(numeric),
  public.list_attendance(uuid, date), public.save_attendance(uuid, date, jsonb), public.attendance_summary(uuid, date, date),
  public.attendance_today(uuid), public.class_roster(uuid), public.save_schedule_slot(uuid, integer, integer, uuid),
  public.list_schedule(uuid), public.my_schedule(uuid), public.save_grades(uuid, uuid, uuid, text, jsonb),
  public.list_grades(uuid, uuid), public.calc_final_rows(uuid, uuid), public.rekap_nilai(uuid, uuid),
  public.build_snapshot(uuid, uuid), public.list_reports(uuid, uuid), public.save_homeroom_note(uuid, uuid, text),
  public.validate_reports(uuid, uuid), public.publish_reports(uuid, uuid), public.reopen_report(uuid, uuid, text),
  public.get_report(uuid, uuid), public.portal_jadwal(uuid), public.portal_kehadiran(uuid), public.portal_rapor(uuid),
  public.visible_classes(uuid), public.list_assignments(uuid), public.my_assignments(uuid), public.list_teachers(uuid)
  from public, anon, authenticated;

grant execute on function
  public.is_curriculum(uuid), public.can_view_class(uuid), public.can_take_attendance(uuid), public.is_homeroom_of_class(uuid),
  public.can_grade(uuid), public.grade_letter(numeric), public.list_attendance(uuid, date), public.save_attendance(uuid, date, jsonb),
  public.attendance_summary(uuid, date, date), public.attendance_today(uuid), public.class_roster(uuid),
  public.save_schedule_slot(uuid, integer, integer, uuid), public.list_schedule(uuid), public.my_schedule(uuid),
  public.save_grades(uuid, uuid, uuid, text, jsonb), public.list_grades(uuid, uuid), public.rekap_nilai(uuid, uuid),
  public.list_reports(uuid, uuid), public.save_homeroom_note(uuid, uuid, text), public.validate_reports(uuid, uuid),
  public.publish_reports(uuid, uuid), public.reopen_report(uuid, uuid, text), public.get_report(uuid, uuid),
  public.visible_classes(uuid), public.list_assignments(uuid), public.my_assignments(uuid), public.list_teachers(uuid)
  to authenticated;
grant execute on function
  public.ta_check(), public.slot_conflict_check(), public.calc_final_rows(uuid, uuid), public.build_snapshot(uuid, uuid),
  public.portal_jadwal(uuid), public.portal_kehadiran(uuid), public.portal_rapor(uuid)
  to service_role;

-- ---------- Data awal (CONTOH — sesuaikan dengan kurikulum sekolah) ----------
insert into public.subjects (school_id, code, name, kkm)
select s.id, v.code, v.name, 75
  from public.schools s
  cross join (values ('PAI','Pendidikan Agama Islam'), ('BIN','Bahasa Indonesia'), ('MTK','Matematika'), ('BIG','Bahasa Inggris'),
                     ('IPA','Ilmu Pengetahuan Alam'), ('IPS','Ilmu Pengetahuan Sosial'), ('PKN','Pendidikan Kewarganegaraan'),
                     ('PJOK','Pendidikan Jasmani dan Kesehatan'), ('SBK','Seni Budaya')) v(code, name);

insert into public.assessment_components (school_id, academic_year_id, code, name, weight, sort_order)
select ay.school_id, ay.id, v.code, v.name, v.weight, v.ord
  from public.academic_years ay
  cross join (values ('TGS','Tugas',20,1), ('UH','Ulangan Harian',20,2), ('UTS','Ujian Tengah Semester',25,3), ('UAS','Ujian Akhir Semester',35,4)) v(code, name, weight, ord)
 where ay.is_active;

insert into public.lesson_periods (school_id, period, start_time, end_time)
select s.id, n, time '07:00' + (n - 1) * interval '40 minutes', time '07:00' + n * interval '40 minutes'
  from public.schools s cross join generate_series(1, 8) n;
