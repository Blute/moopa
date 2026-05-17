<cfcomponent key="8659f978-4823-4f1f-bf23-3f9c864b503f">

    <cffunction name="read">
      <cfreturn application.lib.db.read(table_name='moo_route', id=id, field_list="*", returnAsCFML=true)/>
    </cffunction>

    <cffunction name="search">
      <cfquery name="q">
      SELECT COALESCE(jsonb_agg(data)::text, '[]') as data
      FROM (
          SELECT #application.lib.db.select(table_name="moo_route", field_list="id,key,url,mapping")#,
                 (SELECT count(*) FROM moo_route_roles WHERE primary_id = moo_route.id) AS role_count,
                 (SELECT count(*) FROM moo_route_profiles WHERE primary_id = moo_route.id) AS profile_count
          FROM moo_route
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
      <cfreturn application.lib.db.search(table_name='moo_profile', q="#url.q?:''#", exclude_ids="#url.exclude_ids?:''#")/>
    </cffunction>

    <cffunction name="get">
      <cf_layout_default>

        <div x-data="routes_tree" x-cloak class="flex flex-col gap-4 lg:gap-5">
          <!-- Header -->
          <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
            <div class="min-w-0">
              <div class="flex items-center gap-3">
                <div class="flex h-9 w-9 shrink-0 items-center justify-center rounded-box border border-base-300 bg-base-100 text-primary">
                  <i class="hgi-stroke hgi-route-01 text-base"></i>
                </div>
                <div class="min-w-0">
                  <div class="flex flex-wrap items-baseline gap-x-2.5 gap-y-1">
                    <h1 class="text-[1.625rem] font-semibold leading-none tracking-[-0.03em]">Routes</h1>
                    <span class="text-[0.6875rem] font-medium uppercase tracking-[0.11em] text-base-content/42" x-text="routeSummary()"></span>
                  </div>
                  <p class="mt-1 max-w-[58ch] text-sm leading-5 text-base-content/62">Manage security across all application routes with a clear, navigable tree.</p>
                </div>
              </div>
            </div>
          </div>

          <!-- Routes Tree Card -->
          <div class="min-w-0 overflow-hidden rounded-lg border border-base-300 bg-base-100 md:flex md:max-h-[calc(100vh-9rem)] md:flex-col">
            <!-- Toolbar -->
            <div class="border-b border-base-300 px-4 py-3">
              <div class="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
                <div class="flex min-w-0 flex-col gap-2 sm:flex-row sm:items-center">
                  <label class="input input-sm w-full focus-within:outline-primary/55 focus-within:outline-offset-2 sm:w-72 lg:w-80">
                    <i class="hgi-stroke hgi-search-01 text-base-content/40"></i>
                    <input type="search" aria-label="Search routes" placeholder="Search routes" x-model.debounce="filters.q">
                  </label>
                  <button type="button" class="btn btn-ghost btn-sm justify-start" @click="reset_filters()" :disabled="!hasActiveFilters()">
                    Reset
                  </button>
                </div>
                <button class="btn btn-ghost btn-sm gap-2" @click="toggle_all()" :disabled="stats.total === 0">
                  <i class="hgi-stroke" :class="is_all_expanded() ? 'hgi-arrow-shrink' : 'hgi-arrow-expand'"></i>
                  <span x-text="is_all_expanded() ? 'Collapse all' : 'Expand all'"></span>
                </button>
              </div>
            </div>

            <!-- Header Row -->
            <div class="border-b border-base-300 px-4 py-2.5">
              <div class="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-3 text-[0.8125rem] font-medium text-base-content/58 lg:grid-cols-[minmax(0,1fr)_5rem_5rem_6.25rem]">
                <div>Route structure</div>
                <div class="hidden text-end lg:block">Roles</div>
                <div class="hidden text-end lg:block">People</div>
                <div class="text-end">Actions</div>
              </div>
            </div>

            <!-- Loading State -->
            <template x-if="loading">
              <div class="p-6 text-center text-base-content/60">
                <span class="loading loading-spinner loading-md"></span>
                <p class="mt-2">Loading routes…</p>
              </div>
            </template>

            <div class="overflow-visible md:min-h-0 md:flex-1 md:overflow-auto">
            <!-- Routes List -->
            <ul class="divide-y divide-base-300">
                  <template x-for="row in flat_tree()" :key="row.node.id">
                    <li class="transition-colors hover:bg-base-200/35">
                      <div class="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-3 px-4 py-2.5 lg:grid-cols-[minmax(0,1fr)_5rem_5rem_6.25rem]" :class="row.node.route ? 'bg-base-100' : 'bg-base-200/20'">
                        <!-- Route Name & Path -->
                        <div class="flex min-w-0 items-center" :style="`padding-left: ${row.depth * 18}px`">
                          <button x-show="row.node.children.length" type="button" class="btn btn-ghost btn-xs btn-square shrink-0 text-base-content/55" @click="toggle(row.node.id)" :aria-label="`${is_expanded(row.node.id) ? 'Collapse' : 'Expand'} ${row.node.name}`">
                            <i class="hgi-stroke" :class="is_expanded(row.node.id) ? 'hgi-arrow-down-01' : 'hgi-arrow-right-01'"></i>
                          </button>
                          <span x-show="!row.node.children.length" class="w-6 shrink-0"></span>
                          <span class="mx-2 flex h-6 w-6 shrink-0 items-center justify-center rounded-field border border-base-300 bg-base-100 text-base-content/55" :class="row.node.route ? 'text-base-content/45' : 'text-primary'">
                            <i class="hgi-stroke text-sm" :class="row.node.route ? 'hgi-file-01' : (is_expanded(row.node.id) ? 'hgi-folder-open' : 'hgi-folder-01')"></i>
                          </span>
                          <div class="min-w-0">
                            <div class="flex min-w-0 items-baseline gap-2">
                              <span class="truncate font-medium tracking-[-0.01em]" :class="row.node.route ? 'text-base-content' : 'text-base-content/82'" x-text="route_label(row.node)"></span>
                              <span class="hidden rounded-full bg-base-200 px-1.5 py-0.5 text-[0.625rem] font-medium uppercase tracking-[0.08em] text-base-content/45 sm:inline" x-text="row.node.route ? 'Route' : 'Group'"></span>
                            </div>
                            <button x-show="row.node.route" type="button" class="block max-w-full truncate pt-0.5 text-left font-mono text-xs text-base-content/50 hover:text-primary focus:outline-primary/55 focus:outline-offset-2" :title="'Copy ' + (row.node.route?.url || '')" @click.stop="copy_url(row.node.route?.url)" x-text="row.node.route?.url"></button>
                          </div>
                        </div>
                        <!-- Roles Count -->
                        <div class="hidden items-center justify-end lg:flex">
                          <template x-if="row.node.route">
                            <span class="badge badge-sm badge-ghost" :title="'Roles'" x-text="row.node.route.role_count||0"></span>
                          </template>
                        </div>
                        <!-- Profiles Count -->
                        <div class="hidden items-center justify-end lg:flex">
                          <template x-if="row.node.route">
                            <span class="badge badge-sm badge-soft badge-info" :title="'Profiles'" x-text="row.node.route.profile_count||0"></span>
                          </template>
                        </div>
                        <!-- Actions -->
                        <div class="flex items-center justify-end">
                          <template x-if="row.node.route">
                            <button class="btn btn-ghost btn-sm gap-2" @click="open_secure(row.node.route)">
                              <i class="hgi-stroke hgi-shield-01 text-primary"></i>
                              <span class="hidden sm:inline">Manage</span>
                            </button>
                          </template>
                        </div>
                      </div>
                    </li>
                  </template>
            </ul>

            <template x-if="!loading && flat_tree().length === 0">
              <div class="px-6 py-12 text-center">
                <div class="mx-auto flex max-w-md flex-col items-center gap-3 text-base-content/65">
                  <i class="hgi-stroke hgi-route-01 text-3xl text-base-content/35"></i>
                  <div>
                    <p class="font-medium text-base-content">No routes match these filters.</p>
                    <p class="mt-1 text-sm">Clear filters or search for a different route.</p>
                  </div>
                  <button type="button" class="btn btn-sm" @click="reset_filters()">Reset filters</button>
                </div>
              </div>
            </template>

            </div>

            <div class="flex flex-col gap-2 border-t border-base-300 bg-base-100/95 px-4 py-1.5 text-[0.6875rem] leading-5 text-base-content/50 sm:flex-row sm:items-center sm:justify-between" x-show="!loading && stats.total > 0">
              <span><strong class="font-semibold text-base-content" x-text="stats.with_roles"></strong> roles · <strong class="font-semibold text-base-content" x-text="stats.people_total"></strong> people</span>
              <span><strong class="font-semibold text-base-content" x-text="flat_tree().length"></strong> of <strong class="font-semibold text-base-content" x-text="stats.total"></strong></span>
            </div>
          </div>

          <!--- Security Modal --->
          <dialog x-ref="securityModal" class="modal" @close="security_iframe_src = ''">
            <div class="modal-box max-w-6xl w-11/12 h-[85vh] p-0 flex flex-col">
              <div class="flex items-center justify-between px-5 py-3 border-b border-base-200 bg-base-200/30">
                <h3 class="font-semibold text-lg flex items-center gap-2">
                  <i class="hgi-stroke hgi-security-check text-primary"></i>
                  Route Security
                </h3>
                <form method="dialog">
                  <button class="btn btn-sm btn-circle btn-ghost" aria-label="Close">
                    <i class="hgi-stroke hgi-cancel-01"></i>
                  </button>
                </form>
              </div>
              <div class="flex-1 overflow-hidden">
                <iframe :src="security_iframe_src" class="w-full h-full border-0"></iframe>
              </div>
            </div>
            <form method="dialog" class="modal-backdrop">
              <button>close</button>
            </form>
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
                  await saveFilters({ q: '' });
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
                      const a_is_folder = (a.children?.length || 0) > 0;
                      const b_is_folder = (b.children?.length || 0) > 0;
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
                    const self_match = node.name.toLowerCase().includes(q) || (node.route?.url || '').toLowerCase().includes(q);
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
      </cf_layout_default>
  </cffunction>

  </cfcomponent>
