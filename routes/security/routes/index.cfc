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
      <cf_layout_default content_class="w-full max-w-7xl mx-auto">

        <div x-data="routes_tree" x-cloak class="flex flex-col gap-4">
          <!-- Header -->
          <div class="flex flex-col lg:flex-row lg:items-center gap-2">
            <div>
              <h1 class="m-0 text-2xl font-semibold">Routes</h1>
              <p class="text-base-content/60 text-sm">Manage security across all application routes with a clear, navigable tree.</p>
            </div>
          </div>

          <!-- Main Content -->
          <div class="flex flex-col md:flex-row md:items-start gap-4">
            <!-- Filters Card -->
            <div class="w-full md:w-80 shrink-0">
              <div class="card card-border bg-base-100">
                <!-- Filter Header -->
                <div class="px-5 py-4 border-b border-base-200">
                  <h3 class="text-lg font-semibold">Filters</h3>
                  <p class="text-sm text-base-content/60 mt-1">
                    <span class="font-semibold text-base-content" x-text="stats.total"></span>
                    <span x-text="stats.total === 1 ? 'route found' : 'routes found'"></span>
                  </p>
                </div>

                <!-- Filter Content -->
                <div class="px-5 py-4 space-y-4">
                  <!-- Search -->
                  <div>
                    <label class="block text-sm font-medium mb-2">Search</label>
                    <label class="input input-bordered w-full">
                      <span class="fal fa-search text-base-content/50"></span>
                      <input type="text" class="grow" placeholder="Search routes..." x-model.debounce="filters.q">
                      <button
                        x-show="filters.q"
                        x-transition
                        @click="filters.q = ''"
                        class="text-base-content/40 hover:text-base-content/70"
                      >
                        <span class="fal fa-times"></span>
                      </button>
                    </label>
                  </div>
                </div>

                <!-- Filter Footer -->
                <div class="px-5 py-4 border-t border-base-200 bg-base-200/30 rounded-b-2xl">
                  <button class="btn btn-outline btn-block" @click="reset_filters()" title="Reset filters">
                    <span class="fal fa-refresh"></span>
                    Reset Filters
                  </button>
                </div>
              </div>
            </div>

            <!-- Routes Tree Card -->
            <div class="flex-1 min-w-0">
              <div class="card card-border bg-base-100">
                <!-- Header Row -->
                <div class="border-b border-base-200 px-3 py-2.5">
                  <div class="grid items-center gap-2 text-sm font-semibold text-base-content/70" style="grid-template-columns: 1fr 80px 80px 100px;">
                    <div class="flex items-center gap-2">
                      <span>Route</span>
                      <button class="btn btn-ghost btn-xs" @click="toggle_all()">
                        <span class="fal" :class="is_all_expanded() ? 'fa-compress-alt' : 'fa-expand-alt'"></span>
                        <span x-text="is_all_expanded() ? 'Collapse' : 'Expand'"></span>
                      </button>
                    </div>
                    <div class="text-end">Roles</div>
                    <div class="text-end">People</div>
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

                <!-- Routes List -->
                <ul class="divide-y divide-base-200">
                  <template x-for="row in flat_tree()" :key="row.node.id">
                    <li class="hover:bg-base-200/50 transition-colors">
                      <div class="grid items-center gap-2 px-3 py-2" style="grid-template-columns: 1fr 80px 80px 100px;">
                        <!-- Route Name & Path -->
                        <div class="flex items-center min-w-0" :style="`padding-left: ${row.depth * 16}px`">
                          <template x-if="row.node.children.length">
                            <button class="btn btn-ghost btn-xs btn-square" @click="toggle(row.node.id)">
                              <span class="fal" :class="is_expanded(row.node.id) ? 'fa-angle-down' : 'fa-angle-right'"></span>
                            </button>
                          </template>
                          <template x-if="!row.node.children.length">
                            <span class="w-6 text-center text-base-content/40"><span class="fal fa-file"></span></span>
                          </template>
                          <template x-if="row.node.children.length">
                            <span class="ms-1 text-base-content/60"><span class="fal" :class="is_expanded(row.node.id) ? 'fa-folder-open' : 'fa-folder'"></span></span>
                          </template>
                          <span class="ms-2 font-medium truncate" x-text="row.node.name"></span>
                          <span class="ms-2 text-xs text-base-content/50 font-mono truncate cursor-pointer hover:text-primary"
                                :title="'Click to copy: ' + (row.node.route?.url || '')"
                                @click.stop="copy_url(row.node.route?.url)"
                                x-text="row.node.route?.url"></span>
                        </div>
                        <!-- Roles Count -->
                        <div class="flex items-center justify-end">
                          <template x-if="row.node.route">
                            <span class="badge badge-sm badge-ghost" :title="'Roles'" x-text="row.node.route.role_count||0"></span>
                          </template>
                        </div>
                        <!-- Profiles Count -->
                        <div class="flex items-center justify-end">
                          <template x-if="row.node.route">
                            <span class="badge badge-sm badge-soft badge-info" :title="'Profiles'" x-text="row.node.route.profile_count||0"></span>
                          </template>
                        </div>
                        <!-- Actions -->
                        <div class="flex items-center justify-end">
                          <template x-if="row.node.route">
                            <button class="btn btn-primary btn-soft btn-sm" @click="open_secure(row.node.route)">
                              <span class="fal fa-shield"></span>
                              Manage
                            </button>
                          </template>
                        </div>
                      </div>
                    </li>
                  </template>
                </ul>
              </div>
            </div>
          </div>

          <script>
            document.addEventListener('alpine:init', () => {
              Alpine.data('routes_tree', () => ({
                routes: [],
                root_nodes: [],
                expanded_paths: new Set(),
                filters: { q: '' },
                loading: false,
                stats: { total: 0, with_roles: 0, people_total: 0 },
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
                    if (window.notyf?.open) {
                      window.notyf.open({
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
                  window.location.href = `/security/routes/${route.id}`;
                }
              }));
            });
          </script>
        </div>
      </cf_layout_default>
  </cffunction>

  </cfcomponent>
