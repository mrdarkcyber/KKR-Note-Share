// app.js – Shared shell utilities loaded on every authenticated page

// ── Toast ────────────────────────────────────────────────────
function showToast(msg, type = '') {
  let c = document.getElementById('toast-container');
  if (!c) {
    c = document.createElement('div');
    c.id = 'toast-container';
    document.body.appendChild(c);
  }
  const t = document.createElement('div');
  t.className = `toast ${type}`;
  t.textContent = msg;
  c.appendChild(t);
  setTimeout(() => t.remove(), 3800);
}

// ── Loader ───────────────────────────────────────────────────
function showLoader() {
  const d = document.createElement('div');
  d.className = 'loader-overlay'; d.id = 'main-loader';
  d.innerHTML = '<div class="spinner"></div>';
  document.body.appendChild(d);
}
function hideLoader() {
  document.getElementById('main-loader')?.remove();
}

// ── Format bytes ─────────────────────────────────────────────
function fmtBytes(bytes) {
  if (!bytes) return '—';
  if (bytes < 1024)       return bytes + ' B';
  if (bytes < 1024**2)    return (bytes/1024).toFixed(1) + ' KB';
  return (bytes/(1024**2)).toFixed(1) + ' MB';
}

// ── Relative date ────────────────────────────────────────────
function timeAgo(dateStr) {
  const d = new Date(dateStr);
  const diff = Date.now() - d.getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  const days = Math.floor(hrs / 24);
  if (days < 30) return `${days}d ago`;
  return d.toLocaleDateString('en-IN', { day:'numeric', month:'short', year:'numeric' });
}

// ── Populate sidebar user info ───────────────────────────────
async function initShell(activeNav) {
  const user = await requireAuth();

  // Render sidebar user section
  const profile = await getProfile(user.id).catch(() => null);
  const roll = user.email.split('@')[0];
  const initials = (profile?.full_name || roll).slice(0, 2).toUpperCase();

  const avatarEl = document.getElementById('sidebar-avatar');
  const rollEl   = document.getElementById('sidebar-roll');
  const emailEl  = document.getElementById('sidebar-email');
  if (avatarEl) avatarEl.textContent = initials;
  if (rollEl)   rollEl.textContent   = profile?.full_name || roll;
  if (emailEl)  emailEl.textContent  = user.email;

  // Show admin nav section if user is admin
  if (profile?.is_admin) {
    const adminSection = document.getElementById('sidebar-admin-section');
    if (adminSection) adminSection.style.display = 'block';
  }

  // Highlight active nav
  document.querySelectorAll('.nav-link').forEach(l => {
    if (l.dataset.nav === activeNav) l.classList.add('active');
  });

  // Mobile hamburger
  const ham = document.getElementById('hamburger');
  const sidebar = document.getElementById('sidebar');
  if (ham && sidebar) {
    ham.addEventListener('click', () => sidebar.classList.toggle('open'));
    document.addEventListener('click', e => {
      if (!sidebar.contains(e.target) && !ham.contains(e.target))
        sidebar.classList.remove('open');
    });
  }

  // Sign-out button
  document.getElementById('signout-btn')?.addEventListener('click', async () => {
    await signOut();
  });

  return { user, profile };
}

// ── Build sidebar HTML (injected into pages) ─────────────────
function renderSidebar() {
  return `
  <nav class="sidebar" id="sidebar">
    <div class="sidebar-brand">
      <div class="brand-logo">
        <div class="brand-icon">📚</div>
        <div class="brand-name">KKR Note-Share <small>Academic Portal</small></div>
      </div>
    </div>

    <div class="sidebar-nav">
      <div class="nav-section-label">Menu</div>
      <a class="nav-link" data-nav="dashboard" href="dashboard.html">
        <span class="nav-icon">🏠</span> Dashboard
      </a>
      <a class="nav-link" data-nav="notes" href="notes.html">
        <span class="nav-icon">📄</span> Notes
      </a>
      <a class="nav-link" data-nav="textbooks" href="textbooks.html">
        <span class="nav-icon">📖</span> Textbooks
      </a>

      <div class="nav-section-label" style="margin-top:12px">Contribute</div>
      <a class="nav-link" data-nav="upload-note" href="upload-note.html">
        <span class="nav-icon">⬆️</span> Upload Notes
      </a>
      <a class="nav-link" data-nav="upload-book" href="upload-book.html">
        <span class="nav-icon">📤</span> Upload Textbook
      </a>

      <div class="nav-section-label" style="margin-top:12px">Account</div>
      <a class="nav-link" data-nav="profile" href="profile.html">
        <span class="nav-icon">👤</span> My Profile
      </a>

      <!-- Admin section: hidden by default, shown for admins in initShell() -->
      <div id="sidebar-admin-section" style="display:none">
        <div class="nav-section-label" style="margin-top:12px">Admin</div>
        <a class="nav-link" data-nav="admin" href="admin.html">
          <span class="nav-icon">🛡️</span> Admin Panel
        </a>
      </div>
    </div>

    <div class="sidebar-user">
      <div class="user-info">
        <div class="user-avatar" id="sidebar-avatar">??</div>
        <div>
          <div class="user-roll" id="sidebar-roll">Loading…</div>
          <div class="user-email" id="sidebar-email"></div>
        </div>
      </div>
      <button class="btn btn-outline btn-sm" id="signout-btn" style="width:100%">
        Sign Out
      </button>
    </div>
  </nav>`;
}

// ── Build mobile header ──────────────────────────────────────
function renderMobileHeader(title) {
  return `
  <div class="mobile-header">
    <button class="hamburger" id="hamburger">☰</button>
    <span style="font-family:var(--font-head);font-weight:700">${title}</span>
  </div>`;
}
