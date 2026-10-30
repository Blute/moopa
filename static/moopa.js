/*
  moopa.js — the behaviour behind moopa.css, loaded by <cf_moopa_layout> before Alpine:

    req({...})        call a route's endpoint (the same contract as the starter's app.js)
    loadFilters / saveFilters / clearFilters, getInitials, prettyDate, prettyDateTitle
    window.toast({})  a notification: { type: 'success'|'error'|'warning'|'info', title?, message|description, duration? }
    the shell         sidebar collapse (Ctrl+.), mobile drawer, profile menu, tooltips on the collapsed rail
    components        Alpine.data() behaviour for inline form markup: numberInput, comboSingle, fileUpload…
                      (the moopa-components skill; live on System > Components)

  No dependencies. The components register on Alpine's alpine:init, so this file loads before
  Alpine. A project page on the Moopa layout may load its own scripts after this one; a later
  `function req()` of its own replaces this one.
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

// A textarea as tall as its text: <textarea class="textarea textarea-auto" @input="autosize($el)">
function autosize(el) { el.style.height = 'auto'; el.style.height = el.scrollHeight + 'px'; }

// ---------------------------------------------------------------------------------------------
// Components: behaviour only. Each Alpine.data() component owns state and logic (search,
// formatting, selection, upload); the page writes the markup with moopa.css's classes and binds
// to it. Bind a component's value to the page's model with x-modelable + x-model. The markup
// contract for each one is in the moopa-components skill and live on System > Components.
//
// Server contracts (an `endpoint` is an endpoint name on the current route, or the object
// application.lib.auth.signedEndpoint() returns, for another route):
//   search        req({ endpoint, q, limit, exclude_ids })  ->  [{ id, label, disabled?, ...extra }]
//   address       req({ endpoint, q })                      ->  { suggestions: [{ formatted_address, ... }] }
//   file upload   presign, PUT, finalise (moo_file's uploadFileToServerWithProgress), see fileUpload
// ---------------------------------------------------------------------------------------------
document.addEventListener('alpine:init', () => {
  const LOCALE = 'en-AU';   // number and date formatting
  const target = endpoint => (typeof endpoint === 'string' ? { endpoint } : { ...endpoint });
  const number = raw => parseFloat(String(raw).replace(/[^0-9.\-]/g, ''));
  const reqMessage = (error, fallback) => { try { return JSON.parse(error.message).message || fallback; } catch { return error?.message || fallback; } };

  // --- numbers: show formatted, store a number, commit on change --------------------------------
  Alpine.data('numberInput', ({ min = null, max = null, places = 0 } = {}) => ({
    value: null,
    display() { return this.value === null || this.value === '' ? '' : Number(this.value).toLocaleString(LOCALE, { minimumFractionDigits: 0, maximumFractionDigits: places }); },
    commit(raw) {
      let n = number(raw);
      if (Number.isNaN(n)) { this.value = null; return; }
      if (min !== null) n = Math.max(min, n);
      if (max !== null) n = Math.min(max, n);
      this.value = Number(n.toFixed(places));
    },
  }));

  Alpine.data('currencyInput', ({ places = 2 } = {}) => ({
    value: null,
    display() { return this.value === null || this.value === '' ? '' : Number(this.value).toLocaleString(LOCALE, { minimumFractionDigits: places, maximumFractionDigits: places }); },
    commit(raw) { const n = number(raw); this.value = Number.isNaN(n) ? null : Number(n.toFixed(places)); },
  }));

  // Shows 22.5, stores the fraction 0.225
  Alpine.data('percentInput', ({ places = 2 } = {}) => ({
    value: null,
    display() { return this.value === null || this.value === '' ? '' : (Number(this.value) * 100).toLocaleString(LOCALE, { maximumFractionDigits: places }); },
    commit(raw) { const n = number(raw); this.value = Number.isNaN(n) ? null : Number((n / 100).toFixed(places + 2)); },
  }));

  // --- checkbox group: options [[value, text], ...]; the model is a comma-joined string ---------
  Alpine.data('checkboxList', (options = []) => ({
    options, value: '',
    list() { return this.value ? String(this.value).split(',') : []; },
    has(v) { return this.list().includes(v); },
    toggle(v) { const l = this.list(); const i = l.indexOf(v); if (i >= 0) l.splice(i, 1); else l.push(v); this.value = l.join(','); },
  }));

  // --- dates ------------------------------------------------------------------------------------
  // dateQuick: a date input with quick picks; the model is a local calendar date, yyyy-mm-dd
  Alpine.data('dateQuick', () => ({
    value: '',
    set(n, unit = 'day') {
      const d = new Date();
      if (unit === 'month') d.setMonth(d.getMonth() + n); else d.setDate(d.getDate() + n);
      const p = x => String(x).padStart(2, '0');
      this.value = d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate());
    },
  }));
  // datetimeUtc: shows local time in a datetime-local input, stores an ISO UTC string
  Alpine.data('datetimeUtc', () => ({
    value: '',
    toLocal() {
      if (!this.value) return '';
      const d = new Date(this.value);
      const p = n => String(n).padStart(2, '0');
      return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) + 'T' + p(d.getHours()) + ':' + p(d.getMinutes());
    },
    fromLocal(v) { this.value = v ? new Date(v).toISOString() : ''; },
  }));

  // --- comboboxes: server search, keyboard navigation -----------------------------------------
  // `request: () => ({ ... })` adds parameters to every search, read when the search runs.
  // Stale replies never replace newer results; close() and destroy() cancel a pending search.
  const comboBase = ({ endpoint, placeholder = 'Select…', limit = 20, request = () => ({}) }) => ({
    placeholder, limit,
    open: false, loading: false, query: '', options: [], active: 0, _t: null, _version: 0,
    async openList() { if (this.open) return; this.open = true; await this.fetch(); },
    close() { this.open = false; this.query = ''; this.loading = false; clearTimeout(this._t); this._version++; },
    destroy() { clearTimeout(this._t); this._version++; },
    move(d) { if (!this.options.length) return; this.active = (this.active + d + this.options.length) % this.options.length; },
    extra() { return {}; },
    async fetch() {
      const version = ++this._version;
      this.loading = true;
      try {
        const options = await req({ ...target(endpoint), q: this.query, limit: this.limit, ...this.extra(), ...request() });
        if (version === this._version) { this.options = options || []; this.active = 0; }
      } finally { if (version === this._version) this.loading = false; }
    },
    // loading turns on at once, so the debounce never reads as "No matches"
    search() { clearTimeout(this._t); this._version++; this.open = true; this.loading = true; this._t = setTimeout(() => this.fetch(), 250); },
  });

  // One record: the model is the chosen option ({ id, label, ... }) or null. groupBy ('industry.name')
  // heads runs of options; choosing dispatches model-change with detail.selected_option.
  Alpine.data('comboSingle', ({ groupBy = null, ...opts }) => ({
    ...comboBase(opts), selected: null,
    choose(item) { if (!item || item.disabled) return; this.selected = item; this.close(); this.$dispatch('model-change', { selected_option: item }); },
    clear() { this.selected = null; this.$refs.input.focus(); },
    grouped() {
      const get = (o, path) => path.split('.').reduce((a, k) => a?.[k], o);
      let last;
      return this.options.map((item, index) => {
        const g = groupBy ? (get(item, groupBy) ?? '') : undefined;
        const row = { key: item.id, item, index, group: g !== undefined && g !== last ? g : undefined };
        last = g;
        return row;
      });
    },
  }));

  // Many records as chips: the model is an array of options; the search excludes those chosen
  Alpine.data('comboMany', (opts) => ({
    ...comboBase(opts), selected: [],
    extra() { return { exclude_ids: this.selected.map(s => s.id) }; },
    choose(item) { if (!item || item.disabled || this.selected.some(s => s.id === item.id)) return; this.selected.push(item); this.query = ''; this.search(); },
    remove(item) { this.selected = this.selected.filter(s => s.id !== item.id); if (this.open) this.search(); },
  }));

  // --- ordered many: drag to reorder (native drag and drop), search to add ---------------------
  Alpine.data('sortList', ({ endpoint, limit = 10 }) => ({
    items: [], dragging: null, open: false, loading: false, query: '', options: [], _t: null, _version: 0,
    dropOn(i) { if (this.dragging === null || this.dragging === i) return; const [m] = this.items.splice(this.dragging, 1); this.items.splice(i, 0, m); this.dragging = null; },
    add(o) { if (o.disabled || this.items.some(x => x.id === o.id)) return; this.items.push({ id: o.id, label: o.label }); this.query = ''; this.open = false; },
    remove(i) { this.items.splice(i, 1); },
    search() {
      clearTimeout(this._t);
      this._t = setTimeout(async () => {
        const version = ++this._version;
        this.loading = true;
        try {
          const options = await req({ ...target(endpoint), q: this.query, limit, exclude_ids: this.items.map(x => x.id) });
          if (version === this._version) { this.options = options || []; this.open = true; }
        } finally { if (version === this._version) this.loading = false; }
      }, 250);
    },
    destroy() { clearTimeout(this._t); this._version++; },
  }));

  // --- address, from the project's own lookup endpoint -----------------------------------------
  // The model is the picked suggestion ({ formatted_address, ... }) or null
  Alpine.data('addressSearch', ({ endpoint }) => ({
    value: null, query: '', options: [], open: false, loading: false, _t: null, _req: 0,
    search() { this.cancel(); if (!this.query) { this.options = []; return; } this.loading = true; this._t = setTimeout(() => this.fetch(), 300); },
    async fetch() {
      const id = ++this._req;
      try { const r = await req({ ...target(endpoint), q: this.query }); if (id === this._req) this.options = r?.suggestions || []; }
      finally { if (id === this._req) this.loading = false; }
    },
    pick(s) { this.value = s; this.close(); this.$dispatch('model-change', { selected_option: s }); },
    clear() { this.value = null; this.options = []; this.$refs.input.focus(); },
    close() { this.cancel(); this.open = false; this.query = ''; this.options = []; },
    // a pending or in-flight lookup may no longer touch the list
    cancel() { clearTimeout(this._t); this._req++; this.loading = false; },
    destroy() { this.cancel(); },
  }));

  // --- address, from Google Places in the browser ----------------------------------------------
  // With the project's Maps key, so the key's referrer restrictions apply. The model:
  // { place_id, name, formatted_address, geometry: { location: { lat, lng } }, state, postcode, suburb }.
  // country limits results (ISO code); bias = { lat, lng, radius } ranks results near it first.
  // Google's bootstrap loader: defines google.maps.importLibrary and fetches the API on first use.
  function loadGoogleMaps(key) {
    if (window.google?.maps?.importLibrary) return;
    if (!key) throw new Error('addressGoogle needs the project\'s Google Maps key');
    (g => { var h, a, k, p = "The Google Maps JavaScript API", c = "google", l = "importLibrary", q = "__ib__", m = document, b = window; b = b[c] || (b[c] = {}); var d = b.maps || (b.maps = {}), r = new Set, e = new URLSearchParams, u = () => h || (h = new Promise(async (f, n) => { await (a = m.createElement("script")); e.set("libraries", [...r] + ""); for (k in g) e.set(k.replace(/[A-Z]/g, t => "_" + t[0].toLowerCase()), g[k]); e.set("callback", c + ".maps." + q); a.src = `https://maps.${c}apis.com/maps/api/js?` + e; d[q] = f; a.onerror = () => h = n(Error(p + " could not load.")); a.nonce = m.querySelector("script[nonce]")?.nonce || ""; m.head.append(a) })); d[l] ? console.warn(p + " only loads once. Ignoring:", g) : d[l] = (f, ...n) => r.add(f) && u().then(() => d[l](f, ...n)) })({ key, v: "weekly" });
  }
  Alpine.data('addressGoogle', ({ key, country = 'au', language = LOCALE, bias = null } = {}) => ({
    value: null, query: '', options: [], open: false, loading: false, _t: null, _session: null, _req: 0,
    async places() { loadGoogleMaps(key); return await google.maps.importLibrary('places'); },
    search() { this.cancel(); if (!this.query) { this.options = []; return; } this.loading = true; this._t = setTimeout(() => this.fetch(), 250); },
    async fetch() {
      const q = this.query;
      const id = ++this._req;
      try {
        const lib = await this.places();
        this._session ||= new lib.AutocompleteSessionToken();
        const request = { input: q, sessionToken: this._session, includedRegionCodes: [country], language };
        if (bias?.lat != null) request.locationBias = { center: { lat: bias.lat, lng: bias.lng }, radius: Math.min(bias.radius || 50000, 50000) };   // Google caps the circle at 50 km
        const { suggestions } = await lib.AutocompleteSuggestion.fetchAutocompleteSuggestions(request);
        if (id !== this._req) return;
        this.options = suggestions.filter(s => s.placePrediction).map(s => ({ place_id: s.placePrediction.placeId, formatted_address: s.placePrediction.text.text, _prediction: s.placePrediction }));
      } catch (error) {
        console.error('Address search failed:', error);
        if (id === this._req) { this.options = []; window.toast({ type: 'error', message: 'Address search is not available' }); }
      } finally { if (id === this._req) this.loading = false; }
    },
    async pick(s) {
      this.loading = true;
      try {
        const place = s._prediction.toPlace();
        await place.fetchFields({ fields: ['displayName', 'formattedAddress', 'location', 'addressComponents'] });
        const part = type => place.addressComponents?.find(c => c.types.includes(type));
        this.value = {
          place_id: place.id,
          name: place.displayName || '',
          formatted_address: place.formattedAddress || s.formatted_address,
          geometry: { location: { lat: place.location?.lat() ?? null, lng: place.location?.lng() ?? null } },
          state: part('administrative_area_level_1')?.shortText || '',
          postcode: part('postal_code')?.longText || '',
          suburb: part('locality')?.longText || '',
        };
      } catch (error) {
        console.error('Place details failed:', error);
        this.value = { place_id: s.place_id, formatted_address: s.formatted_address };
      } finally {
        this._session = null;   // a pick ends the billing session
        this.loading = false;
        this.close();
        this.$dispatch('model-change', { selected_option: this.value });
      }
    },
    clear() { this.value = null; this.options = []; this.$refs.input.focus(); },
    close() { this.cancel(); this.open = false; this.query = ''; this.options = []; },
    // a pending or in-flight lookup may no longer touch the list
    cancel() { clearTimeout(this._t); this._req++; this.loading = false; },
    destroy() { this.cancel(); },
  }));

  // --- rich text: Trix, loaded by the page. Refs: input (hidden), editor (trix-editor) ----------
  // Loading a value never emits model-change, so an autosave sees only the user's edits.
  Alpine.data('richText', () => ({
    value: '', syncing: false,
    init() {
      if (!window.customElements?.get('trix-editor')) throw new Error('richText needs Trix loaded on the page');
      this.$watch('value', () => this.sync());
      this.$nextTick(() => this.sync());
    },
    sync() {
      const editor = this.$refs.editor;
      if (!editor?.editor || editor.value === (this.value || '')) return;
      this.syncing = true;
      try { editor.editor.loadHTML(this.value || ''); } finally { this.syncing = false; }
    },
    change() {
      if (this.syncing || !this.$refs.editor?.editor) return;
      const value = this.$refs.editor.value;
      if (value === this.value) return;
      this.value = value;
      this.$dispatch('model-change', { value });
    },
  }));

  // --- email addresses as chips: the model is a comma-joined string -----------------------------
  Alpine.data('emailRecipients', () => ({
    value: '', query: '',
    addresses() { return (this.value || '').split(',').map(v => v.trim()).filter(Boolean); },
    valid(email) { return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email); },
    // Takes pasted lists split by commas, semicolons or spaces; invalid entries stay in the input
    add(raw = this.query) {
      const list = this.addresses();
      const invalid = [];
      String(raw).split(/[,;\s]+/).filter(Boolean).forEach(email => {
        if (!this.valid(email)) invalid.push(email);
        else if (!list.includes(email)) list.push(email);
      });
      this.value = list.join(',');
      this.query = invalid.join(', ');
    },
    remove(email) { this.value = this.addresses().filter(v => v !== email).join(','); },
  }));

  // --- sortable rows: SortableJS, loaded by the page --------------------------------------------
  // On the rows' parent; each row has data-id. With `endpoint`, a drop posts { ids: 'a,b,c' } and
  // leaves the DOM as dragged. With `onMove(oldIndex, newIndex)` instead, the DOM is put back and the
  // page moves the item in its own array, so an x-for list stays the one source of the order.
  Alpine.data('sortableRows', ({ endpoint = null, handle, row, enabled = () => true, onMove = null }) => ({
    sortable: null,
    init() {
      if (typeof Sortable !== 'function') throw new Error('sortableRows needs SortableJS loaded on the page');
      if (!endpoint && !onMove) throw new Error('sortableRows needs an endpoint or onMove');
      let startOrder = null;
      this.sortable = new Sortable(this.$el, {
        animation: 150, handle, draggable: row, dataIdAttr: 'data-id',
        disabled: !enabled(),
        onStart: () => { startOrder = this.sortable.toArray(); },
        onEnd: async (evt) => {
          if (onMove) {
            if (evt.oldIndex === evt.newIndex) return;
            this.sortable.sort(startOrder, true);
            onMove(evt.oldIndex, evt.newIndex);
            return;
          }
          await req({ ...target(endpoint), body: { ids: this.sortable.toArray().join(',') } });
        },
      });
      this.$watch(() => enabled(), value => this.sortable.option('disabled', !value));
    },
    destroy() { this.sortable?.destroy(); },
  }));

  // --- admin list: filtered records, an edit dialog and a delete dialog --------------------------
  // The page supplies the table, the form and two <dialog>s, x-ref="editDialog" and x-ref="deleteDialog".
  //   load    req({ endpoint, body: { filters } })  ->  [records]
  //   new     req({ endpoint })                     ->  a blank record (or `blank: () => ({...})` builds it here)
  //   read    req({ endpoint, id })                 ->  the full record (optional: endpoints.read)
  //   save    req({ endpoint, body: record })
  //   delete  req({ endpoint, id })
  // `persist: 'key'` keeps the filters in sessionStorage. A page with more behaviour spreads it:
  // Alpine.data('people', () => ({ ...adminList({ ... }), extra() {} })).
  const adminList = ({ endpoints = {}, filters: defaultFilters = () => ({ term: '' }), blank = null, persist = null } = {}) => {
    const ep = { load: 'load', new: 'new', read: null, save: 'save', delete: 'delete', ...endpoints };
    const storageKey = persist ? 'moopa:admin:' + persist : null;
    const saved = () => { try { return JSON.parse(sessionStorage.getItem(storageKey) || 'null'); } catch { return null; } };
    return {
      records: [], current_record: {}, action_status: '', error: '', _load: 0,
      filters: { ...defaultFilters(), ...(storageKey ? saved() || {} : {}) },
      init() {
        this.load();
        this.$watch('filters', value => {
          if (storageKey) { try { sessionStorage.setItem(storageKey, JSON.stringify(value)); } catch {} }
          this.load();
        });
      },
      resetFilters() { this.filters = defaultFilters(); },
      // Only the latest load may set the records: a slower reply for older filters is dropped
      async load() {
        const version = ++this._load;
        this.action_status = 'Loading…';
        try {
          const records = await req({ endpoint: ep.load, body: { filters: this.filters } });
          if (version === this._load) this.records = records || [];
        } finally { if (version === this._load && this.action_status === 'Loading…') this.action_status = ''; }
      },
      async openNew() {
        this.error = '';
        this.current_record = blank ? blank() : await req({ endpoint: ep.new });
        this.$refs.editDialog.showModal();
      },
      async openEdit(record) {
        this.error = '';
        this.current_record = ep.read ? await req({ endpoint: ep.read, id: record.id }) : JSON.parse(JSON.stringify(record));
        this.$refs.editDialog.showModal();
      },
      closeEdit() { this.$refs.editDialog.close(); },
      async save() {
        this.action_status = 'Saving…'; this.error = '';
        try {
          await req({ endpoint: ep.save, body: this.current_record });
          this.$refs.editDialog.close();
          await this.load();
        } catch (error) { this.error = reqMessage(error, 'Save failed'); }
        finally { this.action_status = ''; }
      },
      openDelete(record) { this.error = ''; this.current_record = record; this.$refs.deleteDialog.showModal(); },
      async confirmDelete() {
        this.action_status = 'Deleting…'; this.error = '';
        try {
          await req({ endpoint: ep.delete, id: this.current_record.id });
          this.$refs.deleteDialog.close();
          this.current_record = {};
          await this.load();
        } catch (error) { this.error = reqMessage(error, 'Delete failed'); }
        finally { this.action_status = ''; }
      },
    };
  };
  Alpine.data('adminList', adminList);
  window.adminList = adminList;

  // --- file upload: drop zone, progress per file -------------------------------------------------
  // 1) presign: req({ endpoint, body: { file_name, file_size, parent_table_name, parent_field, parent_id } }) -> { presignedURL, file }
  // 2) PUT the bytes to presignedURL (XHR, for progress)
  // 3) finalise: req({ endpoint, body: { file_id } }) -> the file record
  // moo_file's uploadFileToServerWithProgress(request.data) does 1 and 3. The model (`files`) holds
  // completed uploads only; uploads in progress (`pending`) and removed files (`removed`) stay here.
  const FILE_ICONS = [
    [/^pdf$/, 'fa-file-pdf'],
    [/^(jpe?g|png|gif|webp|svg|heic|heif|bmp|tiff?)$/, 'fa-file-image'],
    [/^(xlsx?|xlsm|csv)$/, 'fa-file-excel'],
    [/^docx?$/, 'fa-file-word'],
    [/^pptx?$/, 'fa-file-powerpoint'],
    [/^(zip|rar|7z|gz|tar)$/, 'fa-file-zipper'],
    [/^(mp4|mov|avi|mkv|webm)$/, 'fa-file-video'],
    [/^(dxf|dwg|dwf|stp|step|igs|iges|stl)$/, 'fa-compass-drafting'],
    [/^(eml|msg)$/, 'fa-envelope'],
    [/^(txt|md|rtf)$/, 'fa-file-lines'],
  ];
  const fileName = f => f?.name || f?.file_name || '';
  const fileIcon = f => { const ext = fileName(f).split('.').pop().toLowerCase(); return (FILE_ICONS.find(([re]) => re.test(ext)) || [null, 'fa-file'])[1]; };
  const fileSize = bytes => {
    const n = parseInt(bytes, 10);
    if (!n || n < 0) return '';
    if (n >= 1024 * 1024) return (n / 1024 / 1024).toFixed(1) + ' MB';
    if (n >= 1024) return Math.round(n / 1024) + ' KB';
    return n + ' B';
  };
  const fileDate = value => {
    const t = value ? Date.parse(value) : NaN;
    return Number.isNaN(t) ? '' : new Date(t).toLocaleDateString(LOCALE, { day: 'numeric', month: 'short', year: 'numeric' });
  };
  Alpine.data('fileUpload', ({ endpoint, table, field, parentId }) => {
    const sources = new Map();   // pending row id -> File, outside reactive state so retry re-sends the real Blob
    return {
      files: [], pending: [], removed: [], over: false, uploading: false, depth: 0, batch: { done: 0, total: 0 },
      rows() { return [...(this.files || []), ...this.pending, ...this.removed]; },
      label: fileName,
      icon: fileIcon,
      meta(f) { return [fileSize(f.size ?? f.file_size), fileDate(f.doc_date || f.created_at)].filter(Boolean).join(' · '); },
      canPreview(f) { return f.status !== 'uploading' && f.status !== 'error'; },
      busyText() { return this.uploading ? `Uploading ${Math.min(this.batch.done + 1, this.batch.total)} of ${this.batch.total}…` : ''; },
      // A depth count, so moving over the zone's children never flickers the highlight
      dragEnter() { this.depth++; this.over = true; },
      dragLeave() { this.depth = Math.max(0, this.depth - 1); if (!this.depth) this.over = false; },
      drop(event) { this.depth = 0; this.over = false; this.add(event.dataTransfer.files); },
      remove(file) { this.files = this.files.filter(f => f.id !== file.id); this.removed.push({ ...file, removed: true }); },
      restore(file) { this.removed = this.removed.filter(f => f.id !== file.id); const { removed, ...restored } = file; this.files = [...(this.files || []), restored]; },
      dismiss(row) { this.pending = this.pending.filter(p => p.id !== row.id); sources.delete(row.id); },
      retry(row) { const source = sources.get(row.id); this.dismiss(row); return source ? this.add([source]) : Promise.resolve(); },
      async add(list) {
        if (this.uploading) return;
        const items = Array.from(list || []);
        if (!items.length) return;
        this.uploading = true;
        this.batch = { done: 0, total: items.length };
        this.$dispatch('files-uploading');
        const failed = [];
        for (const f of items) {
          try { await this.upload(f); } catch { failed.push(f.name); }
          this.batch.done++;
        }
        this.uploading = false;
        if (failed.length) window.toast({ type: 'error', message: failed.length === 1 ? `${failed[0]} could not be uploaded` : `${failed.length} files could not be uploaded` });
        this.$dispatch('files-uploaded');
      },
      async upload(f) {
        const pre = await req({ ...target(endpoint), body: { file_name: f.name, file_size: f.size, parent_table_name: table, parent_field: field, parent_id: parentId } });
        this.pending.push({ ...pre.file, status: 'uploading', progress: 0 });
        const row = this.pending[this.pending.length - 1];
        sources.set(row.id, f);
        try {
          if (!pre.presignedURL) throw new Error('The server gave no upload URL');
          await new Promise((resolve, reject) => {
            const x = new XMLHttpRequest();
            x.open('PUT', pre.presignedURL);
            x.upload.onprogress = e => { if (e.lengthComputable) row.progress = Math.round(e.loaded / e.total * 100); };
            x.onload = () => (x.status < 300 ? resolve() : reject(new Error('Upload failed: ' + x.status)));
            x.onerror = () => reject(new Error('Upload failed'));
            x.send(f);
          });
          const done = await req({ ...target(endpoint), body: { file_id: row.id } });
          this.files = [...(this.files || []), { ...pre.file, ...done, status: 'uploaded' }];
          this.pending = this.pending.filter(p => p.id !== row.id);
          sources.delete(row.id);
          this.$dispatch('file-uploaded', { file: done });
        } catch (error) { row.status = 'error'; throw error; }
      },
    };
  });
});

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
    // The sidebar's own size, and its rows' (a submenu opening or closing changes how far it can scroll)
    const resized = new ResizeObserver(updateMask);
    resized.observe(nav);
    nav.querySelectorAll(':scope > *').forEach(child => resized.observe(child));
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
