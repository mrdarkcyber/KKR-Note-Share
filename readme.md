# KKR Note-Share & Textbooks Portal
## Complete Setup Guide

---

## 📁 Project Files

```
kkr-note-share/
├── index.html          ← Login / Sign-up page
├── dashboard.html      ← Home dashboard (after login)
├── notes.html          ← Browse all notes
├── textbooks.html      ← Browse all textbooks
├── upload-note.html    ← Upload a note PDF
├── upload-book.html    ← Upload a textbook PDF
├── profile.html        ← User profile & my uploads
├── style.css           ← All styles
├── supabase.js         ← Supabase client + all DB/auth helpers
├── app.js              ← Shared shell (sidebar, toasts, utils)
└── supabase_schema.sql ← Run this once in Supabase SQL editor
```

---

## 🚀 Step-by-Step Setup

### 1. Create a Supabase Project

1. Go to [https://supabase.com](https://supabase.com) and sign in.
2. Click **"New Project"**, choose a name (e.g. `kkr-note-share`) and a strong DB password.
3. Wait for the project to be provisioned (~1–2 min).

---

### 2. Run the Database Schema

1. In your Supabase dashboard, go to **SQL Editor** (left sidebar).
2. Open `supabase_schema.sql` from this project.
3. Paste the entire content and click **Run**.
4. This creates: `profiles`, `courses`, `notes`, `textbooks` tables, RLS policies, and seeds 12 courses.

---

### 3. Create Storage Buckets

In the Supabase dashboard → **Storage** → **New bucket**:

| Bucket name | Public? | Max file size |
|-------------|---------|---------------|
| `notes`     | ❌ No   | 20 MB         |
| `textbooks` | ❌ No   | 100 MB        |

For each bucket, add **Storage Policies**:

**SELECT (download):**
```sql
-- Policy name: "Authenticated users can download"
-- Allowed operation: SELECT
(auth.role() = 'authenticated')
```

**INSERT (upload):**
```sql
-- Policy name: "Authenticated users can upload"
-- Allowed operation: INSERT
(auth.role() = 'authenticated')
```

**DELETE (own files):**
```sql
-- Policy name: "Users can delete own files"
-- Allowed operation: DELETE
(auth.uid()::text = (storage.foldername(name))[1])
```

---

### 4. Configure Auth Settings

In Supabase dashboard → **Authentication** → **Settings**:


- **Confirm email**: Enable (recommended) or disable for testing.
- **Site URL**: Set to your hosting URL (or `http://localhost:5500` for local dev).

To **restrict signups to @nitkkr.ac.in only** at the Supabase level:
- The frontend already validates this.
- For extra security, you can also add a database trigger or Supabase Edge Function.

---

### 5. Add Your Supabase Keys

Open `supabase.js` and replace:

```js
const SUPABASE_URL = 'https://YOUR_PROJECT_ID.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR_ANON_PUBLIC_KEY';
```

Find these in: Supabase Dashboard → **Settings** → **API** → Project URL & anon/public key.

---

### 6. Deploy / Run Locally

**Local (simplest):**
- Install the [Live Server](https://marketplace.visualstudio.com/items?itemName=ritwickdey.LiveServer) VS Code extension.
- Open the folder in VS Code → right-click `index.html` → **Open with Live Server**.

**Deploy (free options):**
- [Netlify Drop](https://app.netlify.com/drop) — drag and drop the folder.
- [Vercel](https://vercel.com) — import from GitHub.
- [GitHub Pages](https://pages.github.com) — push to a repo and enable Pages.

---

## 🔐 Security Summary

| Feature | Implementation |
|---------|---------------|
| Email validation | `^\d{9}@nitkkr\.ac\.in$` regex on frontend |
| Max password length | 8 chars enforced on frontend + HTML `maxlength` |
| Auth | Supabase Auth with JWT tokens |
| Data access | Row Level Security (RLS) on all tables |
| File access | Private buckets with signed URLs (60-min expiry) |
| Upload ownership | Files stored under `{userId}/filename` path |

---

## ➕ Adding More Courses

Run in Supabase SQL Editor:

```sql
INSERT INTO public.courses (code, name, branch, semester) VALUES
  ('CS501', 'Compiler Design', 'CSE', 6),
  ('EC401', 'VLSI Design',     'ECE', 7);
```

---

## 🛠 Common Issues

| Problem | Fix |
|---------|-----|
| "Invalid API key" | Double-check `SUPABASE_URL` and `SUPABASE_ANON_KEY` in `supabase.js` |
| Upload fails | Make sure the `notes` / `textbooks` buckets exist with correct policies |
| Email not confirmed | Disable email confirmation in Supabase Auth settings for testing |
| CORS errors | Make sure you're serving via a web server (Live Server), not opening HTML directly |
| Profile not created | Check if the `on_auth_user_created` trigger was created successfully |
