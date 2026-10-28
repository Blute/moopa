<cfcomponent key="0b348660-a526-4ad5-a807-fd7ec8d2d31c" open_to="security">


    <cffunction name="read">
        <cfreturn application.lib.db.read(table_name='moo_role', id=request.data.id, field_list="*", returnFormat="cfml") />
    </cffunction>


    <cffunction name="search">
        <cfquery name="q">
            SELECT COALESCE(jsonb_agg(data ORDER BY name)::text, '[]') as data
            FROM (
                SELECT moo_role.id
                    , moo_role.name
                    , (
                        SELECT COUNT(*)
                        FROM moo_profile_roles
                        WHERE moo_profile_roles.foreign_id = moo_role.id
                    ) as user_count
                    , (
                        SELECT COUNT(DISTINCT moo_route.id)
                        FROM moo_route
                        INNER JOIN moo_route_roles ON moo_route_roles.primary_id = moo_route.id
                        WHERE moo_route_roles.foreign_id = moo_role.id
                    ) as route_count
                FROM moo_role
                <cfif len(url.q?:'')>
                WHERE moo_role.name ILIKE <cfqueryparam value="%#url.q#%" cfsqltype="varchar" />
                </cfif>
            ) as data
        </cfquery>
        <cfreturn q.data />
    </cffunction>

    <cffunction name="users">
        <cfset var roleId = request.data.role_id ?: (url.role_id ?: "") />
        <cfif NOT len(roleId)>
            <cfthrow type="moopa.security.missingRoleId" message="Role id is required to load role users." />
        </cfif>
        <cfquery name="q">
            SELECT COALESCE(jsonb_agg(data ORDER BY full_name)::text, '[]') as data
            FROM (
                SELECT moo_profile.id
                    , moo_profile.full_name
                    , moo_profile.email
                    , profile_picture.thumbnail AS avatar_url
                FROM moo_profile
                INNER JOIN moo_profile_roles ON moo_profile_roles.primary_id = moo_profile.id
                LEFT JOIN moo_file profile_picture ON profile_picture.id = moo_profile.profile_picture_id
                WHERE moo_profile_roles.foreign_id = <cfqueryparam value="#roleId#" cfsqltype="other" />
            ) as data
        </cfquery>
        <cfreturn q.data />
    </cffunction>

    <cffunction name="routes">
        <cfset var roleId = request.data.role_id ?: (url.role_id ?: "") />
        <cfif NOT len(roleId)>
            <cfthrow type="moopa.security.missingRoleId" message="Role id is required to load role routes." />
        </cfif>
        <cfquery name="q">
            SELECT COALESCE(jsonb_agg(data ORDER BY url)::text, '[]') as data
            FROM (
                SELECT moo_route.id
                    , moo_route.url
                    , moo_route.mapping
                FROM moo_route
                INNER JOIN moo_route_roles ON moo_route_roles.primary_id = moo_route.id
                WHERE moo_route_roles.foreign_id = <cfqueryparam value="#roleId#" cfsqltype="other" />
            ) as data
        </cfquery>
        <cfreturn q.data />
    </cffunction>

    <cffunction name="new">
        <cfreturn application.lib.db.getNewObject( "moo_role"  ) />
    </cffunction>

    <cffunction name="save">
        <cfreturn application.lib.db.save(
            table_name = "moo_role",
            data = request.data
        ) />
    </cffunction>

    <cffunction name="delete">
        <cfreturn application.lib.db.delete(table_name="moo_role", id="#request.data.id#") />
    </cffunction>





    <cffunction name="get">
        <cfmodule template="/moopa/tags/moopa_layout.cfm" title="Roles">

            <div x-data="roles" x-cloak class="page">
                <div class="page-header">
                    <div>
                        <div class="eyebrow" x-text="roleSummary()"></div>
                        <h1>Roles</h1>
                        <p class="page-lede">Security roles, and the people and routes each one has.</p>
                    </div>
                    <div class="page-actions">
                        <button type="button" class="btn btn-primary btn-sm" @click="addNew"><i class="fa-solid fa-plus"></i> New role</button>
                    </div>
                </div>

                <div class="card">
                    <div class="card-header">
                        <div class="cluster">
                            <div class="input-icon" style="width: 18rem; max-width: 100%">
                                <i class="fa-solid fa-magnifying-glass"></i>
                                <input class="input input-sm" placeholder="Search roles" aria-label="Search roles" type="search" x-model="filters.search" @input.debounce.300ms="search()" />
                            </div>
                            <button type="button" class="btn btn-ghost btn-sm" @click="resetFilters()" :disabled="!hasActiveFilters()">Reset</button>
                        </div>
                    </div>

                    <div class="table-wrap" x-show="records.length > 0">
                        <table class="table table-sm table-hover table-clickable">
                            <thead>
                                <tr><th>Name</th><th>People</th><th>Routes</th><th class="actions">Actions</th></tr>
                            </thead>
                            <tbody>
                                <template x-for="item in visibleRecords()" :key="item.id">
                                    <tr tabindex="0" @click="select(item)" @keydown.enter.prevent="select(item)" :aria-label="`Edit role ${item.name}`">
                                        <td class="cell-main" x-text="item.name"></td>
                                        <td>
                                            <button type="button" class="badge" :class="item.user_count === 0 ? 'badge-outline' : 'badge-signal'" @click.stop="showUsersForRole(item)" :aria-label="`People with ${item.name}`">
                                                <i class="fa-solid fa-users"></i><span x-text="item.user_count"></span>
                                            </button>
                                        </td>
                                        <td>
                                            <button type="button" class="badge" :class="item.route_count === 0 ? 'badge-outline' : 'badge-info'" @click.stop="showRoutesForRole(item)" :aria-label="`Routes for ${item.name}`">
                                                <i class="fa-solid fa-route"></i><span x-text="item.route_count"></span>
                                            </button>
                                        </td>
                                        <td class="actions">
                                            <button type="button" @click.stop="select(item)" class="btn btn-ghost btn-icon btn-sm" aria-label="Edit"><i class="fa-solid fa-pen-to-square"></i></button>
                                            <button type="button" @click.stop="confirmDelete(item)" class="btn btn-ghost btn-icon btn-sm text-danger" aria-label="Delete"><i class="fa-solid fa-trash"></i></button>
                                        </td>
                                    </tr>
                                </template>
                            </tbody>
                        </table>
                    </div>

                    <div class="empty" x-show="records.length === 0">
                        <i class="fa-solid fa-shield-halved"></i>
                        <p class="strong secondary">No roles found</p>
                        <p class="small">Change the search, or create a role.</p>
                    </div>

                    <div class="card-footer cluster cluster-between small muted" x-show="records.length > 0">
                        <span><strong class="secondary" x-text="totalUsers()"></strong> <span x-text="totalUsers() === 1 ? 'person' : 'people'"></span> · <strong class="secondary" x-text="totalRoutes()"></strong> <span x-text="totalRoutes() === 1 ? 'route' : 'routes'"></span></span>
                        <div class="cluster">
                            <label class="row">
                                <span class="eyebrow">Rows</span>
                                <select class="select select-sm" style="width: 4.5rem" x-model.number="limit" aria-label="Roles per page">
                                    <option :value="20">20</option>
                                    <option :value="50">50</option>
                                    <option :value="100">100</option>
                                </select>
                            </label>
                            <span><strong class="secondary" x-text="visibleRecords().length ? 1 : 0"></strong>–<strong class="secondary" x-text="visibleRecords().length"></strong> of <strong class="secondary" x-text="records.length"></strong></span>
                            <button type="button" class="btn btn-ghost btn-xs" x-show="canShowMore()" @click="showMore()">More</button>
                        </div>
                    </div>
                </div>

                <dialog x-ref="editModal" class="modal modal-sm" aria-labelledby="role-edit-title" x-effect="showEditModal ? ($el.open || $el.showModal()) : ($el.open && $el.close())" @close="showEditModal = false">
                    <form class="contents" @submit.prevent="handleSave">
                        <div class="modal-header"><h2 id="role-edit-title" class="card-title">Role</h2></div>
                        <div class="modal-body">
                            <div class="field">
                                <label class="label" for="role-name">Name</label>
                                <input id="role-name" type="text" class="input" x-model="current_record.name" required>
                            </div>
                        </div>
                        <div class="modal-footer">
                            <button type="button" @click="showEditModal = false" class="btn btn-sm">Cancel</button>
                            <button type="submit" class="btn btn-primary btn-sm"><i class="fa-solid fa-floppy-disk"></i> Save</button>
                        </div>
                    </form>
                </dialog>

                <dialog x-ref="deleteModal" class="modal modal-sm" aria-labelledby="role-delete-title" x-effect="showDeleteModal ? ($el.open || $el.showModal()) : ($el.open && $el.close())" @close="showDeleteModal = false">
                    <div class="modal-body row row-top" style="gap: var(--sp-3)">
                        <span class="avatar" style="background: var(--danger-surface); border-color: var(--danger-border); color: var(--danger)"><i class="fa-solid fa-triangle-exclamation"></i></span>
                        <div class="stack stack-xs">
                            <h2 id="role-delete-title" class="card-title">Delete this role?</h2>
                            <p class="muted small">Everyone loses what it granted. This can't be undone.</p>
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button type="button" @click="showDeleteModal = false" class="btn btn-sm">Cancel</button>
                        <button type="button" @click="handleDelete" class="btn btn-danger-solid btn-sm"><i class="fa-solid fa-trash"></i> Delete</button>
                    </div>
                </dialog>

                <dialog class="modal" aria-labelledby="role-users-title" x-effect="showUsersModal ? ($el.open || $el.showModal()) : ($el.open && $el.close())" @close="showUsersModal = false">
                    <div class="modal-header">
                        <div>
                            <div class="eyebrow">People with this role</div>
                            <h2 id="role-users-title" class="card-title" x-text="usersModalRole?.name"></h2>
                        </div>
                        <button type="button" @click="showUsersModal = false" class="btn btn-ghost btn-icon btn-sm" aria-label="Close"><i class="fa-solid fa-xmark"></i></button>
                    </div>
                    <div class="modal-body" style="padding: 0">
                        <div class="empty" x-show="usersLoading"><i class="fa-solid fa-spinner fa-spin"></i>Loading…</div>
                        <div class="list-rows" x-show="!usersLoading && roleUsers.length > 0">
                            <template x-for="user in roleUsers" :key="user.id">
                                <div class="list-row" style="justify-content: flex-start">
                                    <span class="avatar">
                                        <template x-if="user.avatar_url"><img :src="user.avatar_url" :alt="user.full_name" /></template>
                                        <template x-if="!user.avatar_url"><span x-text="getInitials(user.full_name)"></span></template>
                                    </span>
                                    <div class="min0">
                                        <div class="cell-main truncate" x-text="user.full_name || 'Unknown'"></div>
                                        <div class="cell-sub truncate" x-text="user.email || '—'"></div>
                                    </div>
                                </div>
                            </template>
                        </div>
                        <div class="empty" x-show="!usersLoading && roleUsers.length === 0"><i class="fa-solid fa-user-slash"></i>No one has this role.</div>
                    </div>
                    <div class="modal-footer"><button type="button" @click="showUsersModal = false" class="btn btn-sm">Close</button></div>
                </dialog>

                <dialog class="modal" aria-labelledby="role-routes-title" x-effect="showRoutesModal ? ($el.open || $el.showModal()) : ($el.open && $el.close())" @close="showRoutesModal = false">
                    <div class="modal-header">
                        <div>
                            <div class="eyebrow">Routes for this role</div>
                            <h2 id="role-routes-title" class="card-title" x-text="routesModalRole?.name"></h2>
                        </div>
                        <button type="button" @click="showRoutesModal = false" class="btn btn-ghost btn-icon btn-sm" aria-label="Close"><i class="fa-solid fa-xmark"></i></button>
                    </div>
                    <div class="modal-body" style="padding: 0">
                        <div class="empty" x-show="routesLoading"><i class="fa-solid fa-spinner fa-spin"></i>Loading…</div>
                        <div class="list-rows" x-show="!routesLoading && roleRoutes.length > 0">
                            <template x-for="route in roleRoutes" :key="route.id">
                                <div class="list-row" style="justify-content: flex-start">
                                    <i class="fa-solid fa-route muted"></i>
                                    <div class="min0">
                                        <div class="cell-main mono truncate" x-text="route.url"></div>
                                        <div class="cell-sub truncate" x-text="route.mapping"></div>
                                    </div>
                                </div>
                            </template>
                        </div>
                        <div class="empty" x-show="!routesLoading && roleRoutes.length === 0"><i class="fa-solid fa-route"></i>No routes are granted to this role.</div>
                    </div>
                    <div class="modal-footer"><button type="button" @click="showRoutesModal = false" class="btn btn-sm">Close</button></div>
                </dialog>

            </div>

            <script>
                document.addEventListener("alpine:init", () => {
                    Alpine.data("roles", () => ({

                        filters: {
                            search: '',
                            sortBy: 'name'
                        },
                        records: [],
                        limit: 20,
                        current_record: {},
                        delete_record: null,
                        showEditModal: false,
                        showDeleteModal: false,
                        showUsersModal: false,
                        usersModalRole: null,
                        roleUsers: [],
                        usersLoading: false,
                        showRoutesModal: false,
                        routesModalRole: null,
                        roleRoutes: [],
                        routesLoading: false,

                        init() {
                            this.search();
                        },

                        getInitials(name) {
                            const cleaned = (name || '').trim();
                            if (!cleaned) return '?';
                            const parts = cleaned.split(/\s+/).filter(Boolean);
                            if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
                            return parts.slice(0, 2).map(p => (p[0] || '')).join('').toUpperCase();
                        },

                        async search() {
                            try {
                                const params = {};
                                if (this.filters.search) params.q = this.filters.search;

                                this.records = await req({
                                    endpoint: 'search',
                                    ...params
                                });
                            } catch (error) {
                                console.error('Search error:', error);
                                this.showNotification('Error searching records', 'error');
                            }
                        },

                        async resetFilters() {
                            this.filters = {
                                search: '',
                                sortBy: 'name'
                            };
                            await this.search();
                        },

                        async select(item) {
                            try {
                                this.current_record = await req({
                                    endpoint: 'read',
                                    body: { id: item.id }
                                });
                                this.showEditModal = true;
                            } catch (error) {
                                console.error('Error loading record:', error);
                                this.showNotification('Error loading record', 'error');
                            }
                        },

                        async addNew() {
                            try {
                                this.current_record = await req({
                                    endpoint: 'new'
                                });
                                this.showEditModal = true;
                            } catch (error) {
                                console.error('Error loading new record:', error);
                                this.showNotification('Error loading new record', 'error');
                            }
                        },

                        async handleSave() {
                            try {
                                await req({
                                    endpoint: 'save',
                                    body: this.current_record
                                });

                                this.showEditModal = false;
                                this.search();
                            } catch (error) {
                                console.error('Save error:', error);
                                this.showNotification('Error saving record', 'error');
                            }
                        },

                        confirmDelete(item) {
                            this.delete_record = item;
                            this.showDeleteModal = true;
                        },

                        async handleDelete() {
                            try {
                                await req({
                                    endpoint: 'delete',
                                    body: { id: this.delete_record.id }
                                });

                                this.showDeleteModal = false;
                                this.search();
                            } catch (error) {
                                console.error('Delete error:', error);
                                this.showNotification('Error deleting record', 'error');
                            }
                        },

                        async showUsersForRole(role) {
                            this.usersModalRole = role;
                            this.roleUsers = [];
                            this.showUsersModal = true;
                            this.usersLoading = true;

                            try {
                                this.roleUsers = await req({
                                    endpoint: 'users',
                                    body: { role_id: role.id }
                                });
                            } catch (error) {
                                console.error('Error loading users:', error);
                                this.showNotification('Error loading users', 'error');
                            } finally {
                                this.usersLoading = false;
                            }
                        },

                        async showRoutesForRole(role) {
                            this.routesModalRole = role;
                            this.roleRoutes = [];
                            this.showRoutesModal = true;
                            this.routesLoading = true;

                            try {
                                this.roleRoutes = await req({
                                    endpoint: 'routes',
                                    body: { role_id: role.id }
                                });
                            } catch (error) {
                                console.error('Error loading routes:', error);
                                this.showNotification('Error loading routes', 'error');
                            } finally {
                                this.routesLoading = false;
                            }
                        },

                        visibleRecords() {
                            return this.records.slice(0, this.limit);
                        },

                        canShowMore() {
                            return this.visibleRecords().length < this.records.length;
                        },

                        showMore() {
                            this.limit = Math.min(this.limit + 20, this.records.length);
                        },

                        hasActiveFilters() {
                            return Object.values(this.filters || {}).some(value => `${value || ''}`.trim().length && value !== 'name');
                        },

                        roleSummary() {
                            const total = this.records.length || 0;
                            if (!total) return 'No roles';
                            if (total === 1) return '1 role';
                            return `${total} roles`;
                        },

                        totalUsers() {
                            return this.records.reduce((total, role) => total + Number(role.user_count || 0), 0);
                        },

                        totalRoutes() {
                            return this.records.reduce((total, role) => total + Number(role.route_count || 0), 0);
                        },

                        showNotification(message, type = 'info') {
                            // Simple notification - you can replace with your preferred notification system
                            if (window.toast) {
                                window.toast({
                                    type: type,
                                    message: message,
                                    duration: 3000,
                                    ripple: false,
                                    dismissible: true,
                                    position: {
                                        x: 'right',
                                        y: 'top'
                                    }
                                });
                            } else {
                                alert(message);
                            }
                        }

                    }))
                })
            </script>

        </cfmodule>
    </cffunction>


</cfcomponent>
