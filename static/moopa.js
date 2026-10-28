/*
  moopa.js — the behaviour behind moopa.css, loaded by <cf_moopa_layout> before Alpine:

    req({...})        call a route's endpoint (the same contract as the starter's app.js)
    loadFilters / saveFilters / clearFilters, getInitials, prettyDate, prettyDateTitle
    window.toast({})  a notification: { type: 'success'|'error'|'warning'|'info', title?, message|description, duration? }
    the shell         sidebar collapse (Ctrl+.), mobile drawer, profile menu, tooltips on the collapsed rail

  No dependencies. A project page on the Moopa layout may load its own scripts after this one;
  a later `function req()` of its own replaces this one.
*/

// ---------------------------------------------------------------------------------------------
// Toasts
// ---------------------------------------------------------------------------------------------
(function () {
  const ICONS = { success: 'fa-circle-check', error: 'fa-circle-exclamation', warning: 'fa-triangle-exclamation', info: 'fa-circle-info' };
  let host;

  function container() {
    if (!host) {
      host = document.createElement('div');
      host.className = 'toasts';
      host.setAttribute('role', 'status');
      host.setAttribute('aria-live', 'polite');
      document.body.appendChild(host);
    }
    return host;
  }

  function dismiss(el) {
    if (!el.isConnected || el.classList.contains('is-leaving')) return;
    el.classList.add('is-leaving');
    setTimeout(() => el.remove(), 180);
  }

  function toast(input, opts = {}) {
    const o = typeof input === 'string' ? { ...opts, message: input } : { ...(input || {}) };
    const type = ICONS[o.type] ? o.type : 'info';
    const el = document.createElement('div');
    el.className = 'toast toast-' + type;

    const icon = document.createElement('i');
    icon.className = o.icon ? (/\bfa-(solid|regular|brands)\b/.test(o.icon) ? o.icon : 'fa-solid ' + o.icon) : 'fa-solid ' + ICONS[type];
    icon.setAttribute('aria-hidden', 'true');
    el.appendChild(icon);

    // A title and a line under it: { title, message } or { message, description } give both
    let titleText = o.title || '';
    let lineText = o.message || o.description || '';
    if (!o.title && o.message && o.description) { titleText = o.message; lineText = o.description; }
    const body = document.createElement('div');
    body.className = 'grow';
    for (const [cls, value] of [['toast-title', titleText], [titleText ? 'toast-text' : 'toast-title', lineText]]) {
      if (!value) continue;
      const line = document.createElement('div');
      line.className = cls;
      line.textContent = value;
      body.appendChild(line);
    }
    el.appendChild(body);

    const close = document.createElement('button');
    close.type = 'button';
    close.className = 'toast-close';
    close.setAttribute('aria-label', 'Dismiss');
    close.innerHTML = '<i class="fa-solid fa-xmark"></i>';
    close.addEventListener('click', () => dismiss(el));
    el.appendChild(close);

    container().appendChild(el);
    const duration = o.duration ?? (type === 'error' ? 6000 : 3000);
    if (duration > 0 && duration !== Infinity) setTimeout(() => dismiss(el), duration);
    return el;
  }

  window.toast = toast;
  // The sonner-style shorthands the starter's toaster offered
  window.sonner = {
    toast,
    success: (message, opts) => toast({ ...opts, type: 'success', message }),
    error: (message, opts) => toast({ ...opts, type: 'error', message }),
    warning: (message, opts) => toast({ ...opts, type: 'warning', message }),
    info: (message, opts) => toast({ ...opts, type: 'info', message }),
  };
})();

// ---------------------------------------------------------------------------------------------
// req(): call an endpoint of a route. GET without a body, POST with one. The endpoint goes in
// the X-Endpoint query parameter so it shows in the network tab. JSON or HTML comes back; an
// error shows a toast (401 sends the browser to sign in) and is re-thrown for the caller.
// ---------------------------------------------------------------------------------------------
async function req({ method, route, endpoint, x_signed_route, x_signature, q, exclude_ids, limit, id, url_params, body, data, callback } = {}) {
  try {
    let payload = body || data || null;
    if (!method) method = payload ? 'POST' : 'GET';

    const params = new URLSearchParams(window.location.search);
    if (!route || route.trim() === '') route = window.location.origin + window.location.pathname;
    if (id) params.append('id', id);
    if (q) params.append('q', q);
    if (exclude_ids) {
      const value = Array.isArray(exclude_ids)
        ? exclude_ids.map(item => (typeof item === 'object' ? item.id : item)).join(',')
        : (exclude_ids?.id || '');
      params.append('exclude_ids', value);
    }
    if (limit) params.append('limit', limit);
    if (url_params) Object.entries(url_params).forEach(([key, value]) => params.append(key, value));
    if (endpoint) params.append('X-Endpoint', endpoint);
    if (params.toString()) route += (route.includes('?') ? '&' : '?') + params.toString();

    const headers = {
      'Cache-Control': 'no-cache, no-store, must-revalidate',
      'Pragma': 'no-cache',
      'Expires': '0',
      'X-Fetch-Request': 'true',
      'X-Login-Redirect-Route': window.location.pathname + window.location.search,
    };
    if (x_signature && x_signed_route) {
      headers['X-Signature'] = x_signature;
      headers['X-Signed-Route'] = x_signed_route;
    }
    if (payload && !(payload instanceof FormData) && typeof payload !== 'string') {
      headers['Content-Type'] = 'application/json';
      payload = JSON.stringify(payload);
    }

    const response = await fetch(route, { method, headers, body: payload || undefined });
    const contentType = response.headers.get('content-type') || '';

    if (response.ok) {
      let res;
      if (contentType.includes('application/json')) res = await response.json();
      else if (contentType.includes('text/html')) res = await response.text();
      else throw new Error('Unsupported content type');
      return callback ? callback(res) : res;
    }

    let message = response.statusText;
    let loginRoute = null;
    if (contentType.includes('application/json')) {
      const errorBody = await response.json();
      message = errorBody.error || errorBody.message || response.statusText;
      loginRoute = errorBody.login_route || null;
    }
    throw new Error(JSON.stringify({ status: response.status, message: message || 'An unexpected error occurred', login_route: loginRoute }));
  } catch (error) {
    let parsed;
    try { parsed = JSON.parse(error.message); } catch { parsed = { status: 500, message: error.message }; }

    if (parsed.status === 401) {
      window.toast({ type: 'error', message: 'You are not signed in. Taking you to sign in…', duration: 5000 });
      setTimeout(() => { window.location.href = parsed.login_route || '/login'; }, 2500);
    } else {
      window.toast({ type: 'error', title: 'Something went wrong', description: parsed.message || 'Contact an administrator if this continues.', duration: 6000 });
    }
    throw error;
  }
}

// ---------------------------------------------------------------------------------------------
// Page helpers (the same names as the starter's app.js)
// ---------------------------------------------------------------------------------------------

// A page's filters, remembered for this tab per route: loadFilters(defaults) / saveFilters(f) / clearFilters()
function filterStorageKey() { return 'moopa:filters:v1:' + window.location.pathname; }
async function loadFilters(defaults = {}) {
  try {
    const saved = JSON.parse(window.sessionStorage.getItem(filterStorageKey()) || 'null');
    return Object.assign({}, defaults, saved && typeof saved === 'object' && !Array.isArray(saved) ? saved : {});
  } catch {
    try { window.sessionStorage.removeItem(filterStorageKey()); } catch {}
    return Object.assign({}, defaults);
  }
}
async function saveFilters(filters) {
  try { window.sessionStorage.setItem(filterStorageKey(), JSON.stringify(Object.assign({}, filters))); } catch {}
}
async function clearFilters() {
  try { window.sessionStorage.removeItem(filterStorageKey()); } catch {}
}

// "Jane Q Citizen" -> "JC"; one word -> its first two letters
function getInitials(name) {
  const parts = String(name || '').trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return '?';
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

// "3 hours ago", "yesterday", "2 weeks ago"; prettyDateTitle gives the full date for a title attribute
function prettyDate(date) {
  if (!date) return 'Never';
  const d = date instanceof Date ? date : new Date(date);
  if (Number.isNaN(d.getTime())) return '';
  const seconds = (Date.now() - d.getTime()) / 1000;
  if (seconds < 0) return 'in the future';
  if (seconds < 60) return 'just now';
  if (seconds < 3600) { const m = Math.floor(seconds / 60); return m === 1 ? '1 minute ago' : m + ' minutes ago'; }
  if (seconds < 86400) { const h = Math.floor(seconds / 3600); return h === 1 ? '1 hour ago' : h + ' hours ago'; }
  const days = Math.floor(seconds / 86400);
  if (days === 1) return 'yesterday';
  if (days < 7) return days + ' days ago';
  if (days < 30) { const w = Math.ceil(days / 7); return w === 1 ? '1 week ago' : w + ' weeks ago'; }
  const months = Math.floor(days / 30);
  if (months < 24) return months === 1 ? '1 month ago' : months + ' months ago';
  return 'over ' + Math.floor(months / 12) + ' years ago';
}
function prettyDateTitle(date) {
  if (!date) return 'Never';
  const d = date instanceof Date ? date : new Date(date);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleString(undefined, { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric', hour: '2-digit', minute: '2-digit' });
}

// ---------------------------------------------------------------------------------------------
// The shell: sidebar collapse (desktop) / drawer (mobile), profile menu, collapsed-rail tooltips
// ---------------------------------------------------------------------------------------------
document.addEventListener('DOMContentLoaded', function () {
  'use strict';

  const KEY = 'moo-shell-collapsed';
  const body = document.body;
  const root = document.documentElement;
  const mq = window.matchMedia('(max-width: 767.98px)');
  const sidebar = document.getElementById('moo-shell-sidebar');
  if (!sidebar) return;

  function stored() { try { return localStorage.getItem(KEY) === '1'; } catch { return false; } }
  function store(collapsed) { try { localStorage.setItem(KEY, collapsed ? '1' : '0'); } catch {} }

  root.classList.toggle('moo-shell-collapsed', stored() && !mq.matches);

  const sidebarToggle = document.getElementById('moo-shell-sidebar-toggle');
  const mobileToggle = document.getElementById('moo-shell-mobile-toggle');

  function syncA11y() {
    const collapsed = root.classList.contains('moo-shell-collapsed');
    const mobileOpen = body.classList.contains('moo-shell-mobile-open');
    sidebarToggle?.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
    sidebarToggle?.setAttribute('aria-label', collapsed ? 'Open sidebar' : 'Collapse sidebar');
    mobileToggle?.setAttribute('aria-expanded', mobileOpen ? 'true' : 'false');
    sidebar.setAttribute('aria-hidden', mq.matches && !mobileOpen ? 'true' : 'false');
  }

  function toggle() {
    if (mq.matches) {
      body.classList.toggle('moo-shell-mobile-open');
    } else {
      root.classList.toggle('moo-shell-collapsed');
      store(root.classList.contains('moo-shell-collapsed'));
    }
    syncA11y();
  }
  function closeMobile() { body.classList.remove('moo-shell-mobile-open'); syncA11y(); }
  syncA11y();

  sidebarToggle?.addEventListener('click', toggle);
  mobileToggle?.addEventListener('click', toggle);
  document.getElementById('moo-shell-backdrop')?.addEventListener('click', closeMobile);
  sidebar.querySelectorAll('a').forEach(a => a.addEventListener('click', () => { if (mq.matches) closeMobile(); }));

  // Bring the current page's row into view: on a short window it can sit below the fold of the
  // sidebar (the System group comes after the app's menus). Only the sidebar scrolls, and only if it must.
  const nav = sidebar.querySelector('.moo-shell-nav');
  const currentRow = nav?.querySelector('[aria-current="page"]');
  if (nav && currentRow) {
    const navBox = nav.getBoundingClientRect();
    const rowBox = currentRow.getBoundingClientRect();
    if (rowBox.top < navBox.top || rowBox.bottom > navBox.bottom) {
      nav.scrollTop += rowBox.top - navBox.top - (navBox.height - rowBox.height) / 2;
    }
  }

  // Scroll-edge fade: the edge the sidebar can still scroll towards fades out (moopa.css masks on
  // .moo-shell-has-top / -has-bottom), and the scrollbar shows briefly while it scrolls.
  if (nav) {
    const updateMask = () => {
      nav.classList.toggle('moo-shell-has-top', nav.scrollTop > 2);
      nav.classList.toggle('moo-shell-has-bottom', nav.scrollTop + nav.clientHeight < nav.scrollHeight - 2);
    };
    let scrollFlash;
    updateMask();
    nav.addEventListener('scroll', () => {
      updateMask();
      nav.classList.add('moo-shell-scrolling');
      clearTimeout(scrollFlash);
      scrollFlash = setTimeout(() => nav.classList.remove('moo-shell-scrolling'), 700);
    }, { passive: true });
    new ResizeObserver(updateMask).observe(nav);
  }

  // Submenus: a parent row flips [data-open] on its wrap. On the collapsed rail it opens the sidebar first.
  sidebar.querySelectorAll('[data-moo-shell-toggle-submenu]').forEach(btn => {
    btn.addEventListener('click', e => {
      e.preventDefault();
      const wrap = btn.closest('[data-moo-shell-submenu]');
      if (!wrap) return;
      if (root.classList.contains('moo-shell-collapsed') && !mq.matches) {
        root.classList.remove('moo-shell-collapsed');
        store(false);
        syncA11y();
        requestAnimationFrame(() => { wrap.setAttribute('data-open', 'true'); btn.setAttribute('aria-expanded', 'true'); });
        return;
      }
      const open = wrap.getAttribute('data-open') === 'true';
      wrap.setAttribute('data-open', open ? 'false' : 'true');
      btn.setAttribute('aria-expanded', open ? 'false' : 'true');
    });
  });

  // Profile menu: the button toggles it; outside clicks, Esc and picking an item close it.
  const profileBtn = document.getElementById('moo-shell-profile-btn');
  const profileMenu = document.getElementById('moo-shell-profile-dropdown');
  function setProfile(open) {
    if (!profileBtn || !profileMenu) return;
    profileMenu.classList.toggle('moo-shell-open', open);
    profileBtn.setAttribute('aria-expanded', open ? 'true' : 'false');
    profileMenu.setAttribute('aria-hidden', open ? 'false' : 'true');
    if (open) profileMenu.querySelector('a, button')?.focus({ preventScroll: true });
  }
  profileBtn?.addEventListener('click', e => { e.stopPropagation(); setProfile(!profileMenu.classList.contains('moo-shell-open')); });
  profileMenu?.addEventListener('click', e => { if (e.target.closest('a')) setProfile(false); });
  document.addEventListener('click', e => { if (profileMenu && !profileMenu.contains(e.target)) setProfile(false); });

  document.addEventListener('keydown', e => {
    if (e.key === 'Escape') {
      if (profileMenu?.classList.contains('moo-shell-open')) { setProfile(false); profileBtn?.focus(); }
      else if (body.classList.contains('moo-shell-mobile-open')) closeMobile();
    } else if (e.ctrlKey && e.key === '.' && !e.target.matches('input, textarea, select, [contenteditable]')) {
      e.preventDefault();
      toggle();
    }
  });

  // Tooltips for the collapsed rail: one floating label outside the sidebar's overflow.
  const portal = document.createElement('div');
  portal.className = 'moo-shell-nav-tooltip-portal';
  portal.setAttribute('aria-hidden', 'true');
  body.appendChild(portal);
  let showTimer;
  function hideTip() { clearTimeout(showTimer); portal.classList.remove('show'); }
  function showTip(wrap) {
    const text = wrap.querySelector('.moo-shell-nav-tooltip')?.textContent?.trim();
    if (!text || mq.matches || !root.classList.contains('moo-shell-collapsed')) return;
    portal.textContent = text;
    showTimer = setTimeout(() => {
      const r = wrap.getBoundingClientRect();
      portal.style.top = (r.top + r.height / 2) + 'px';
      portal.style.left = (sidebar.getBoundingClientRect().right + 10) + 'px';
      portal.classList.add('show');
    }, 80);
  }
  sidebar.querySelectorAll('.moo-shell-nav-row-wrap, .moo-shell-profile-menu').forEach(wrap => {
    wrap.addEventListener('mouseenter', () => showTip(wrap));
    wrap.addEventListener('mouseleave', hideTip);
  });
  document.addEventListener('click', hideTip, true);
  window.addEventListener('resize', hideTip);

  mq.addEventListener('change', e => {
    if (e.matches) root.classList.remove('moo-shell-collapsed');
    else { body.classList.remove('moo-shell-mobile-open'); root.classList.toggle('moo-shell-collapsed', stored()); }
    syncA11y();
  });
});
