// ============================================================
//  supabase.js  –  Supabase client configuration
//  REPLACE the two constants below with your project's values
//  from: https://supabase.com/dashboard → Settings → API
// ============================================================

const SUPABASE_URL = "https://xbbxybwdsexwwmmdfaii.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhiYnh5Yndkc2V4d3dtbWRmYWlpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNjEwMTUsImV4cCI6MjA5MDYzNzAxNX0.Uk7ibuGUkv9a6zBLgRF5CbcyeYb0DyHdR0tpG-NrG60";

const { createClient } = supabase;   // loaded from CDN in HTML
const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// ── Auth helpers ─────────────────────────────────────────────

/** Validate NIT KKR email format: 9digits@nitkkr.ac.in */
function isValidCollegeEmail(email) {
  return /^\d{9}@nitkkr\.ac\.in$/.test(email.trim());
}

/** Sign up */
async function signUp(email, password, metadata = {}) {
  if (!isValidCollegeEmail(email))
    throw new Error('Use your NIT KKR email (9digits@nitkkr.ac.in).');
  if (password.length > 8)
    throw new Error('Password must be at most 8 characters.');

  const { data, error } = await sb.auth.signUp({
    email: email.trim(),
    password,
    options: { data: metadata }
  });
  if (error) throw error;
  return data;
}

/** Sign in */
async function signIn(email, password) {
  if (!isValidCollegeEmail(email))
    throw new Error('Use your NIT KKR email (9digits@nitkkr.ac.in).');

  const { data, error } = await sb.auth.signInWithPassword({
    email: email.trim(),
    password
  });
  if (error) throw error;
  return data;
}

/** Sign out */
async function signOut() {
  const { error } = await sb.auth.signOut();
  if (error) throw error;
  window.location.href = 'index.html';
}

/** Get current user (null if not logged in) */
async function getUser() {
  const { data: { user } } = await sb.auth.getUser();
  return user;
}

/** Redirect to login if not authenticated */
async function requireAuth() {
  const user = await getUser();
  if (!user) window.location.href = 'index.html';
  return user;
}

// ── Admin helpers ────────────────────────────────────────────

/** Returns true if the currently logged-in user is an admin */
async function isAdmin() {
  const user = await getUser();
  if (!user) return false;
  const { data, error } = await sb
    .from('profiles')
    .select('is_admin')
    .eq('id', user.id)
    .single();
  if (error) return false;
  return data?.is_admin === true;
}

/**
 * Redirect away if the current user is not an admin.
 * Call this at the top of any admin-only page.
 */
async function requireAdmin() {
  const user = await requireAuth();           // also handles unauthenticated
  const admin = await isAdmin();
  if (!admin) window.location.href = 'dashboard.html';
  return user;
}

/**
 * Grant admin rights to a user by roll number.
 * Only works when called by an existing admin (enforced by DB policy).
 * @param {string} rollNo  – 9-digit roll number, e.g. '124302001'
 */
async function grantAdmin(rollNo) {
  const { error } = await sb
    .from('profiles')
    .update({ is_admin: true })
    .eq('roll_no', rollNo);
  if (error) throw error;
}

/**
 * Revoke admin rights from a user by roll number.
 * Only works when called by an existing admin (enforced by DB policy).
 * @param {string} rollNo  – 9-digit roll number
 */
async function revokeAdmin(rollNo) {
  const { error } = await sb
    .from('profiles')
    .update({ is_admin: false })
    .eq('roll_no', rollNo);
  if (error) throw error;
}

/**
 * Fetch all users with admin status.
 * Returns array of profile rows ordered by roll_no.
 */
async function getAllProfiles() {
  const { data, error } = await sb
    .from('profiles')
    .select('id, roll_no, full_name, email, branch, year, is_admin, created_at')
    .order('roll_no');
  if (error) throw error;
  return data;
}

// ── Storage helpers ──────────────────────────────────────────

/** Upload a PDF to the given bucket. Returns storage path. */
async function uploadPDF(bucket, file, folder) {
  const path = `${folder}/${Date.now()}_${file.name.replace(/\s+/g, '_')}`;
  const { error } = await sb.storage.from(bucket).upload(path, file, {
    contentType: 'application/pdf',
    upsert: false
  });
  if (error) throw error;
  return path;
}

/** Get a signed URL (60-min expiry) for a stored PDF */
async function getSignedURL(bucket, path) {
  const { data, error } = await sb.storage
    .from(bucket)
    .createSignedUrl(path, 3600);
  if (error) throw error;
  return data.signedUrl;
}

// ── DB helpers ───────────────────────────────────────────────

async function getCourses() {
  const { data, error } = await sb
    .from('courses')
    .select('*')
    .order('branch').order('semester');
  if (error) throw error;
  return data;
}

async function getNotes(filters = {}) {
  let q = sb.from('notes').select(`
    *, courses(code, name, branch, semester),
    profiles(roll_no, full_name)
  `).order('created_at', { ascending: false });

  if (filters.course_id) q = q.eq('course_id', filters.course_id);
  if (filters.search)    q = q.ilike('title', `%${filters.search}%`);

  const { data, error } = await q;
  if (error) throw error;
  return data;
}

async function getTextbooks(filters = {}) {
  let q = sb.from('textbooks').select(`
    *, courses(code, name, branch, semester),
    profiles(roll_no, full_name)
  `).order('created_at', { ascending: false });

  if (filters.course_id) q = q.eq('course_id', filters.course_id);
  if (filters.search)    q = q.ilike('title', `%${filters.search}%`);

  const { data, error } = await q;
  if (error) throw error;
  return data;
}

async function insertNote(note) {
  const { data, error } = await sb.from('notes').insert(note).select().single();
  if (error) throw error;
  return data;
}

async function insertTextbook(tb) {
  const { data, error } = await sb.from('textbooks').insert(tb).select().single();
  if (error) throw error;
  return data;
}

async function incrementDownloads(table, id) {
  await sb.rpc('increment_downloads', { table_name: table, row_id: id });
}

async function getProfile(userId) {
  const { data, error } = await sb
    .from('profiles').select('*').eq('id', userId).single();
  if (error) throw error;
  return data;
}

async function updateProfile(userId, updates) {
  const { error } = await sb.from('profiles').update(updates).eq('id', userId);
  if (error) throw error;
}
