<cfcomponent key="8659f978-4823-4f1f-bf23-3f9c864b503f" open_to="security">

    <cffunction name="read">
      <cfreturn application.lib.db.read(table_name='moo_route', id=id, field_list="*", returnFormat="cfml")/>
    </cffunction>

    <cffunction name="search">
      <cfquery name="q">
      SELECT COALESCE(jsonb_agg(data)::text, '[]') as data
      FROM (
          SELECT #application.lib.db.select(table_name="moo_route", field_list="id,key,url,mapping,app_name")#,
                 (SELECT count(*) FROM moo_route_roles WHERE primary_id = moo_route.id) AS role_count,
                 (SELECT count(*) FROM moo_route_profiles WHERE primary_id = moo_route.id) AS profile_count
          FROM moo_route
          WHERE app_name = <cfqueryparam cfsqltype="varchar" value="#application.app_name#" />
          ORDER BY url
      ) as data
      </cfquery>
      <cfreturn q.data/>
    </cffunction>

    <cffunction name="new">
      <cfreturn application.lib.db.getNewObject( "moo_route" )/>
    </cffunction>

    <cffunction name="save">
      <cfreturn application.lib.db.save( table_name = "moo_route", data = request.data )/>
    </cffunction>

    <cffunction name="delete">
      <cfargument name="id"/>
      <cfreturn application.lib.db.delete(table_name="moo_route", id="#arguments.id#")/>
    </cffunction>

    <cffunction name="search.current_record.roles">
      <cfreturn application.lib.db.search(table_name='moo_role', q="#url.q?:''#", exclude_ids="#url.exclude_ids?:''#")/>
    </cffunction>
    <cffunction name="search.current_record.profiles">
      <!--- Route grants only make sense for profiles that can log into this app,
            matching the app_name filter on the route list itself. --->
      <cfreturn application.lib.db.search(table_name='moo_profile', q="#url.q?:''#", exclude_ids="#url.exclude_ids?:''#", where={"app_name": application.app_name})/>
    </cffunction>

    <cffunction name="get">
      <cfmodule template="/moopa/tags/moopa_layout.cfm" title="Routes">

        <div x-data="routes_tree" x-cloak class="page">
          <div class="page-header">
            <div>
              <div class="eyebrow" x-text="routeSummary()"></div>
              <h1>Routes</h1>
              <p class="page-lede">Security for this app's routes and the shared ones, as a tree.</p>
            </div>
          </div>

          <div class="card">
            <div class="card-header">
              <div class="cluster">
                <div class="input-icon" style="width: 18rem; max-width: 100%">
                  <i class="fa-solid fa-magnifying-glass"></i>
                  <input class="input input-sm" type="search" aria-label="Search routes" placeholder="Search routes" x-model.debounce="filters.q">
                </div>
                <button type="button" class="btn btn-ghost btn-sm" @click="reset_filters()" :disabled="!hasActiveFilters()">Reset</button>
              </div>
              <button type="button" class="btn btn-sm" @click="toggle_all()" :disabled="stats.total === 0">
                <i class="fa-solid" :class="is_all_expanded() ? 'fa-compress' : 'fa-expand'"></i>
                <span x-text="is_all_expanded() ? 'Collapse all' : 'Expand all'"></span>
              </button>
            </div>

            <div class="grid-rows-hover" style="--cols: minmax(0, 1fr) 5rem 5rem 7rem; --cols-narrow: minmax(0, 1fr) auto">
              <div class="grid-row grid-row-head">
                <div>Route</div>
                <div class="wide-only text-right">Roles</div>
                <div class="wide-only text-right">People</div>
                <div class="text-right">Security</div>
              </div>

              <div class="empty" x-show="loading"><i class="fa-solid fa-spinner fa-spin"></i>Loading routes…</div>

              <template x-for="row in flat_tree()" :key="row.node.id">
                <div class="grid-row" :style="row.node.route ? '' : 'background: var(--canvas-cream)'">
                  <div class="row min0" :style="`padding-left: ${row.depth * 18}px`">
                    <button x-show="row.node.children.length" type="button" class="btn btn-ghost btn-icon btn-xs" @click="toggle(row.node.id)" :aria-label="`${is_expanded(row.node.id) ? 'Collapse' : 'Expand'} ${row.node.name}`" :aria-expanded="is_expanded(row.node.id)">
                      <i class="fa-solid" :class="is_expanded(row.node.id) ? 'fa-chevron-down' : 'fa-chevron-right'"></i>
                    </button>
                    <span x-show="!row.node.children.length" style="width: var(--control-h-xs); flex: 0 0 auto"></span>
                    <span class="tree-icon" :class="{ 'is-folder': !row.node.route }"><i class="fa-solid" :class="row.node.route ? 'fa-file' : (is_expanded(row.node.id) ? 'fa-folder-open' : 'fa-folder')"></i></span>
                    <div class="min0">
                      <div class="row">
                        <span class="truncate" :class="row.node.route ? 'cell-main' : 'secondary strong'" x-text="route_label(row.node)"></span>
                        <span x-show="row.node.route && is_shared_route(row.node.route)" class="badge badge-upper">Shared</span>
                      </div>
                      <button x-show="row.node.route" type="button" class="mono muted small truncate" style="display: block; max-width: 100%; text-align: left" :title="'Copy ' + (row.node.route?.url || '')" @click.stop="copy_url(row.node.route?.url)" x-text="row.node.route?.url"></button>
                    </div>
                  </div>
                  <div class="wide-only text-right"><template x-if="row.node.route"><span class="badge" title="Roles" x-text="row.node.route.role_count||0"></span></template></div>
                  <div class="wide-only text-right"><template x-if="row.node.route"><span class="badge badge-info" title="People" x-text="row.node.route.profile_count||0"></span></template></div>
                  <div class="text-right">
                    <template x-if="row.node.route">
                      <button type="button" class="btn btn-ghost btn-sm" @click="open_secure(row.node.route)"><i class="fa-solid fa-shield-halved text-signal"></i> Manage</button>
                    </template>
                  </div>
                </div>
              </template>
            </div>

            <div class="empty" x-show="!loading && flat_tree().length === 0">
              <i class="fa-solid fa-route"></i>
              <p class="strong secondary">No routes match this search.</p>
              <button type="button" class="btn btn-sm mt-2" @click="reset_filters()">Reset</button>
            </div>

            <div class="card-footer cluster cluster-between small muted" x-show="!loading && stats.total > 0">
              <span><strong class="secondary" x-text="stats.with_roles"></strong> with roles · <strong class="secondary" x-text="stats.people_total"></strong> people</span>
              <span><strong class="secondary" x-text="flat_tree().length"></strong> of <strong class="secondary" x-text="stats.total"></strong></span>
            </div>
          </div>

          <dialog x-ref="securityModal" class="modal modal-xl" aria-labelledby="route-security-title" @close="security_iframe_src = ''">
            <div class="modal-header">
              <h2 id="route-security-title" class="card-title"><i class="fa-solid fa-shield-halved text-signal"></i> Route security</h2>
              <button type="button" class="btn btn-ghost btn-icon btn-sm" aria-label="Close" @click="$refs.securityModal.close()"><i class="fa-solid fa-xmark"></i></button>
            </div>
            <div class="modal-body" style="padding: 0; display: flex">
              <iframe :src="security_iframe_src" title="Route security editor" style="flex: 1 1 auto; width: 100%; border: 0"></iframe>
            </div>
          </dialog>

          <script>
            document.addEventListener('alpine:init', () => {
              Alpine.data('routes_tree', () => ({
                routes: [],
                root_nodes: [],
                expanded_paths: new Set(),
                filters: { q: '' },
                loading: false,
                stats: { total: 0, with_roles: 0, people_total: 0 },
                security_iframe_src: '',
                async init() {
                  const saved = await loadFilters({ q: '' });
                  this.filters = saved || { q: '' };
                  await this.load();
                  this.$watch('filters.q', (value) => { saveFilters({ q: value }); });
                },
                async reset_filters() {
                  this.filters = { q: '' };
                  await clearFilters();
                  await this.load();
                },
                async load() {
                  this.loading = true;
                  this.routes = await req({ endpoint: 'search', limit: 1000 });
                  this.root_nodes = this.build_tree(this.routes);
                  this.compute_stats();
                  this.loading = false;
                },
                compute_stats() {
                  const total = this.routes.length || 0;
                  const with_roles = this.routes.filter(r => (r.role_count||0) > 0).length;
                  const people_total = this.routes.reduce((a, r) => a + (r.profile_count||0), 0);
                  this.stats = { total, with_roles, people_total };
                },
                hasActiveFilters() {
                  return Object.values(this.filters || {}).some(value => `${value || ''}`.trim().length);
                },
                routeSummary() {
                  const total = this.stats.total || 0;
                  if (!total) return 'No routes';
                  if (total === 1) return '1 route';
                  return `${total} routes`;
                },
                build_tree(routes) {
                  const root = [];
                  const path_map = new Map();
                  const get_or_create = (list, path, name) => {
                    if (!path_map.has(path)) {
                      const node = { id: path || '/', name: name || '/', children: [], route: null };
                      path_map.set(path, node);
                      list.push(node);
                    }
                    return path_map.get(path);
                  };
                  for (const r of routes) {
                    const url = (r.url || '').replace(/^\/+|\/+$/g, '');
                    const parts = url.length ? url.split('/') : ['/'];
                    let list = root;
                    let path = '';
                    for (let i = 0; i < parts.length; i++) {
                      const seg = parts[i] || '/';
                      path = path ? path + '/' + seg : seg;
                      const node = get_or_create(list, path, seg);
                      if (i === parts.length - 1) node.route = r;
                      list = node.children;
                    }
                  }
                  const sort_nodes = (nodes) => {
                    nodes.sort((a, b) => {
                      // Folders first, matching the icon: a node renders as a folder
                      // only when it has no route of its own. A routed node with
                      // children (e.g. /login with /login/logout) shows a file icon,
                      // so it must sort with the files or the grouping looks random.
                      const a_is_folder = !a.route;
                      const b_is_folder = !b.route;
                      if (a_is_folder !== b_is_folder) return a_is_folder ? -1 : 1; // folders first
                      return a.name.localeCompare(b.name);
                    });
                    nodes.forEach(n => sort_nodes(n.children));
                    return nodes;
                  };
                  return sort_nodes(root);
                },
                is_expanded(path) { return this.expanded_paths.has(path) },
                route_label(node) {
                  if (node.route && node.name === 'index') return 'Index route';
                  return node.name;
                },
                is_shared_route(route) {
                  return (route?.mapping || '').startsWith('/shared/routes/');
                },
                toggle(path) {
                  if (this.expanded_paths.has(path)) this.expanded_paths.delete(path); else this.expanded_paths.add(path);
                },
                expand_all() {
                  const collect = (nodes) => nodes.forEach(n => { this.expanded_paths.add(n.id); collect(n.children); });
                  collect(this.root_nodes);
                },
                collapse_all() {
                  this.expanded_paths = new Set();
                },
                is_all_expanded() {
                  let total = 0;
                  const count = (nodes) => nodes.forEach(n => { total += 1; count(n.children); });
                  count(this.root_nodes);
                  return this.expanded_paths.size >= total && total > 0;
                },
                toggle_all() {
                  if (this.is_all_expanded()) {
                    this.collapse_all();
                  } else {
                    this.expand_all();
                  }
                },
                flat_tree() {
                  const res = [];
                  const q = (this.filters.q || '').toLowerCase();
                  const matches = (node) => {
                    if (!q) return true;
                    const route_search = [node.route?.url, node.route?.app_name, node.route?.mapping].filter(Boolean).join(' ').toLowerCase();
                    const self_match = node.name.toLowerCase().includes(q) || route_search.includes(q);
                    if (self_match) return true;
                    return node.children.some(matches);
                  };
                  const walk = (node, depth) => {
                    if (!matches(node)) return;
                    res.push({ node, depth });
                    if (node.children.length && this.is_expanded(node.id)) {
                      node.children.forEach(child => walk(child, depth + 1));
                    }
                  };
                  this.root_nodes.forEach(n => walk(n, 0));
                  return res;
                },
                copy_url(url) {
                  if (!url) return;
                  navigator.clipboard.writeText(url).then(() => {
                    if (window.toast) {
                      window.toast({
                        type: 'success',
                        message: 'URL copied to clipboard',
                        duration: 1500,
                        ripple: false,
                        dismissible: true,
                        position: { x: 'right', y: 'top' }
                      });
                    }
                  });
                },
                open_secure(route) {
                  if (!route?.id) return;
                  this.security_iframe_src = `/sysadmin/routes/${route.id}`;
                  this.$refs.securityModal.showModal();
                }
              }));
            });
          </script>
        </div>
      </cfmodule>
  </cffunction>

  </cfcomponent>
