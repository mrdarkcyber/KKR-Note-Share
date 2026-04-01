-- ============================================================
--  KKR Note-Share & Textbooks – Supabase Schema
--  Run this in your Supabase SQL Editor
-- ============================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ── Profiles ────────────────────────────────────────────────
-- Auto-created when a user signs up (via trigger)
CREATE TABLE IF NOT EXISTS public.profiles (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email       TEXT NOT NULL UNIQUE,
  roll_no     TEXT GENERATED ALWAYS AS (split_part(email, '@', 1)) STORED,
  full_name   TEXT,
  branch      TEXT,
  year        INT CHECK (year BETWEEN 1 AND 4),
  is_admin    BOOLEAN NOT NULL DEFAULT FALSE,   -- ← admin flag
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view all profiles"
  ON public.profiles FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Users can update own profile"
  ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Allow admins to update any profile (for granting/revoking admin)
CREATE POLICY "Admins can update any profile"
  ON public.profiles FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND is_admin = TRUE
    )
  );

CREATE POLICY "Profiles inserted by trigger only"
  ON public.profiles FOR INSERT WITH CHECK (FALSE);

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
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER AS $$
  SELECT COALESCE(
    (SELECT is_admin FROM public.profiles WHERE id = auth.uid()),
    FALSE
  );
$$;

-- ── Grant admin to roll 124302001 after they sign up ─────────
-- Run this ONCE after 124302001@nitkkr.ac.in has signed up:
--
--   UPDATE public.profiles
--   SET is_admin = TRUE
--   WHERE roll_no = '124302001';
--
-- (Uncomment and run the block above in the SQL Editor after first login)


-- ── Courses ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.courses (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  code        TEXT NOT NULL UNIQUE,   -- e.g. CS301
  name        TEXT NOT NULL,          -- e.g. Data Structures
  branch      TEXT NOT NULL,          -- e.g. CSE
  semester    INT  NOT NULL CHECK (semester BETWEEN 1 AND 8),
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.courses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone authenticated can view courses"
  ON public.courses FOR SELECT USING (auth.role() = 'authenticated');

-- Only admins can insert/update/delete courses
CREATE POLICY "Admins can manage courses"
  ON public.courses FOR ALL USING (public.is_admin());

-- Seed some courses
INSERT INTO public.courses (code, name, branch, semester) VALUES
  ('MA101', 'Mathematics I',               'Common',   1),
  ('PH101', 'Engineering Physics',          'Common',   1),
  ('CS101', 'Programming Fundamentals',     'CSE',      1),
  ('MA201', 'Mathematics II',               'Common',   2),
  ('EE201', 'Basic Electrical Engineering', 'Common',   2),
  ('CS201', 'Data Structures',              'CSE',      3),
  ('CS202', 'Discrete Mathematics',         'CSE',      3),
  ('CS301', 'Algorithm Design',             'CSE',      5),
  ('CS302', 'Operating Systems',            'CSE',      5),
  ('CS401', 'Computer Networks',            'CSE',      7),
  ('EC201', 'Electronic Devices',           'ECE',      3),
  ('ME201', 'Engineering Mechanics',        'ME',       3)
ON CONFLICT DO NOTHING;


-- ── Notes ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.notes (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  title         TEXT NOT NULL,
  description   TEXT,
  course_id     UUID REFERENCES public.courses(id) ON DELETE SET NULL,
  uploaded_by   UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  storage_path  TEXT NOT NULL,          -- path inside 'notes' bucket
  file_size     BIGINT,                 -- bytes
  unit          INT,                    -- unit/module number
  tags          TEXT[],
  downloads     INT DEFAULT 0,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.notes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view notes"
  ON public.notes FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can insert notes"
  ON public.notes FOR INSERT WITH CHECK (auth.uid() = uploaded_by);

CREATE POLICY "Uploader can delete own notes"
  ON public.notes FOR DELETE USING (auth.uid() = uploaded_by);

-- Admins can delete any note
CREATE POLICY "Admins can delete any note"
  ON public.notes FOR DELETE USING (public.is_admin());


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
  cover_url     TEXT,                   -- optional thumbnail URL
  downloads     INT DEFAULT 0,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.textbooks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view textbooks"
  ON public.textbooks FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can insert textbooks"
  ON public.textbooks FOR INSERT WITH CHECK (auth.uid() = uploaded_by);

CREATE POLICY "Uploader can delete own textbooks"
  ON public.textbooks FOR DELETE USING (auth.uid() = uploaded_by);

-- Admins can delete any textbook
CREATE POLICY "Admins can delete any textbook"
  ON public.textbooks FOR DELETE USING (public.is_admin());


-- ── Download-count increment function ────────────────────────
CREATE OR REPLACE FUNCTION public.increment_downloads(
  table_name TEXT,
  row_id     UUID
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF table_name = 'notes' THEN
    UPDATE public.notes SET downloads = downloads + 1 WHERE id = row_id;
  ELSIF table_name = 'textbooks' THEN
    UPDATE public.textbooks SET downloads = downloads + 1 WHERE id = row_id;
  END IF;
END;
$$;


-- ============================================================
--  Storage Buckets (run via Supabase dashboard or API)
--  Create two buckets:
--    • notes      (private, 20MB limit)
--    • textbooks  (private, 100MB limit)
--  Then add policies:
--    SELECT: authenticated users
--    INSERT: authenticated users (own folder)
-- ============================================================
