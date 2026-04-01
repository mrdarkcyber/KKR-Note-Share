-- ============================================================
--  NIT KKR Notes & Textbooks – Supabase Schema 
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ── Profiles ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.profiles (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email       TEXT NOT NULL UNIQUE,
  roll_no     TEXT GENERATED ALWAYS AS (split_part(email, '@', 1)) STORED,
  full_name   TEXT,
  branch      TEXT,
  year        INT CHECK (year BETWEEN 1 AND 4),
  is_admin    BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view all profiles"       ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile"      ON public.profiles;
DROP POLICY IF EXISTS "Admins can update any profile"     ON public.profiles;
DROP POLICY IF EXISTS "Profiles inserted by trigger only" ON public.profiles;

CREATE POLICY "Users can view all profiles"
  ON public.profiles FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Users can update own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id);

-- FIX 1: Replaced recursive is_admin() call with a direct subquery.
-- Using is_admin() inside a policy on the profiles table itself causes
-- infinite recursion because is_admin() queries profiles under RLS.
CREATE POLICY "Admins can update any profile"
  ON public.profiles FOR UPDATE
  USING (
    (SELECT is_admin FROM public.profiles WHERE id = auth.uid())
  );

-- FIX 2: Allow the trigger function (SECURITY DEFINER) to insert.
-- WITH CHECK (FALSE) blocks ALL inserts including the trigger, which
-- causes "new row violates row-level security" on every signup.
-- The trigger runs as the function owner (superuser), so we allow
-- inserts when there is no authenticated session (auth.uid() IS NULL).
CREATE POLICY "Profiles inserted by trigger only"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() IS NULL);

-- Trigger: create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.profiles (id, email)
  VALUES (NEW.id, NEW.email);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ── Helper: check if current user is admin ───────────────────
-- FIX 3: SECURITY DEFINER lets this bypass RLS when called from
-- policies on OTHER tables (courses, notes, textbooks). Do NOT
-- call this from policies on profiles itself — use a direct
-- subquery there instead (see "Admins can update any profile" above).
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER AS $$
  SELECT COALESCE(
    (SELECT is_admin FROM public.profiles WHERE id = auth.uid()),
    FALSE
  );
$$;

-- Grant admin to roll 124302001 after they sign up:
--   UPDATE public.profiles SET is_admin = TRUE WHERE roll_no = '124302001';


-- ── Courses ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.courses (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  code        TEXT NOT NULL UNIQUE,
  name        TEXT NOT NULL,
  branch      TEXT NOT NULL,
  semester    INT  NOT NULL CHECK (semester BETWEEN 1 AND 8),
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.courses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone authenticated can view courses" ON public.courses;
DROP POLICY IF EXISTS "Admins can manage courses"            ON public.courses;

CREATE POLICY "Anyone authenticated can view courses"
  ON public.courses FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Admins can manage courses"
  ON public.courses FOR ALL
  USING (public.is_admin());

-- FIX 4: Removed stray "." before INSERT and fixed closing "]" → ")"
INSERT INTO public.courses (code, name, branch, semester) VALUES
  ('MA101', 'Mathematics I',               'Common', 1),
  ('PH101', 'Engineering Physics',          'Common', 1),
  ('CS101', 'Programming Fundamentals',     'CSE',    1),
  ('MA201', 'Mathematics II',               'Common', 2),
  ('EE201', 'Basic Electrical Engineering', 'Common', 2),
  ('CS201', 'Data Structures',              'CSE',    3),
  ('CS202', 'Discrete Mathematics',         'CSE',    3),
  ('CS301', 'Algorithm Design',             'CSE',    5),
  ('CS401', 'Operating Systems',            'CSE',    4),
  ('CS402', 'Database Systems',             'CSE',    4),
  ('CS403', 'Computer Networks',            'CSE',    4),
  ('CS404', 'Scripting Languages',          'CSE',    4),
  ('CS405', 'AISC',                         'CSE',    4),
  ('EC201', 'Electronic Devices',           'ECE',    3),
  ('ME201', 'Engineering Mechanics',        'ME',     3)
ON CONFLICT DO NOTHING;


-- ── Notes ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.notes (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  title         TEXT NOT NULL,
  description   TEXT,
  course_id     UUID REFERENCES public.courses(id) ON DELETE SET NULL,
  uploaded_by   UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  storage_path  TEXT NOT NULL,
  file_size     BIGINT,
  unit          INT,
  tags          TEXT[],
  downloads     INT DEFAULT 0,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.notes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can view notes"   ON public.notes;
DROP POLICY IF EXISTS "Authenticated users can insert notes" ON public.notes;
DROP POLICY IF EXISTS "Authenticated users can update notes" ON public.notes;
DROP POLICY IF EXISTS "Uploader can delete own notes"        ON public.notes;
DROP POLICY IF EXISTS "Admins can delete any note"           ON public.notes;

CREATE POLICY "Authenticated users can view notes"
  ON public.notes FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can insert notes"
  ON public.notes FOR INSERT
  WITH CHECK (auth.uid() = uploaded_by);

-- FIX 5: Added UPDATE policy so increment_downloads() can update
-- the downloads counter. Without this, the SECURITY DEFINER function
-- still hits RLS on UPDATE and throws a permission error.
CREATE POLICY "Authenticated users can update notes"
  ON public.notes FOR UPDATE
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Uploader can delete own notes"
  ON public.notes FOR DELETE
  USING (auth.uid() = uploaded_by);

CREATE POLICY "Admins can delete any note"
  ON public.notes FOR DELETE
  USING (public.is_admin());


-- ── Textbooks ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.textbooks (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  title         TEXT NOT NULL,
  author        TEXT,
  edition       TEXT,
  course_id     UUID REFERENCES public.courses(id) ON DELETE SET NULL,
  uploaded_by   UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  storage_path  TEXT NOT NULL,
  file_size     BIGINT,
  cover_url     TEXT,
  downloads     INT DEFAULT 0,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.textbooks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can view textbooks"   ON public.textbooks;
DROP POLICY IF EXISTS "Authenticated users can insert textbooks" ON public.textbooks;
DROP POLICY IF EXISTS "Authenticated users can update textbooks" ON public.textbooks;
DROP POLICY IF EXISTS "Uploader can delete own textbooks"        ON public.textbooks;
DROP POLICY IF EXISTS "Admins can delete any textbook"           ON public.textbooks;

CREATE POLICY "Authenticated users can view textbooks"
  ON public.textbooks FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can insert textbooks"
  ON public.textbooks FOR INSERT
  WITH CHECK (auth.uid() = uploaded_by);

-- FIX 5 (same as notes): UPDATE policy needed for increment_downloads()
CREATE POLICY "Authenticated users can update textbooks"
  ON public.textbooks FOR UPDATE
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Uploader can delete own textbooks"
  ON public.textbooks FOR DELETE
  USING (auth.uid() = uploaded_by);

CREATE POLICY "Admins can delete any textbook"
  ON public.textbooks FOR DELETE
  USING (public.is_admin());


-- ── Download-count increment function ────────────────────────
CREATE OR REPLACE FUNCTION public.increment_downloads(
  table_name TEXT,
  row_id     UUID
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF table_name = 'notes' THEN
    UPDATE public.notes     SET downloads = downloads + 1 WHERE id = row_id;
  ELSIF table_name = 'textbooks' THEN
    UPDATE public.textbooks SET downloads = downloads + 1 WHERE id = row_id;
  END IF;
END;
$$;


-- ============================================================
--  Storage Buckets (configure via Supabase dashboard or API)
--  Create two buckets:
--    • notes      (private, 20 MB limit)
--    • textbooks  (private, 100 MB limit)
--  Policies:
--    SELECT: authenticated users
--    INSERT: authenticated users (own folder)
-- ============================================================
