<cfcomponent key="0b348660-a526-4ad5-a807-fd7ec8d2d31c">


    <cffunction name="read">
        <cfreturn application.lib.db.read(table_name='moo_role', id=request.data.id, field_list="*", returnAsCFML=true) />
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
                FROM moo_profile
                INNER JOIN moo_profile_roles ON moo_profile_roles.primary_id = moo_profile.id
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
        <cf_layout_default>

            <div x-data="roles" x-cloak class="flex flex-col gap-4 lg:gap-5">
                <!-- Header -->
                <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                    <div class="min-w-0">
                        <div class="flex items-center gap-3">
                            <div class="flex h-9 w-9 shrink-0 items-center justify-center rounded-box border border-base-300 bg-base-100 text-primary">
                                <i class="hgi-stroke hgi-shield-01 text-base"></i>
                            </div>
                            <div class="min-w-0">
                                <div class="flex flex-wrap items-baseline gap-x-2.5 gap-y-1">
                                    <h1 class="text-[1.625rem] font-semibold leading-none tracking-[-0.03em]">Roles</h1>
                                    <span class="text-[0.6875rem] font-medium uppercase tracking-[0.11em] text-base-content/42" x-text="roleSummary()"></span>
                                </div>
                                <p class="mt-1 max-w-[58ch] text-sm leading-5 text-base-content/62">Create security roles and review their assigned users and routes.</p>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- Results -->
                <div class="overflow-hidden rounded-lg border border-base-300 bg-base-100 md:flex md:max-h-[calc(100vh-9rem)] md:flex-col">
                    <div class="border-b border-base-300 px-4 py-3">
                        <div class="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
                            <div class="flex min-w-0 flex-col gap-2 sm:flex-row sm:items-center">
                                <label class="input input-sm w-full focus-within:outline-primary/55 focus-within:outline-offset-2 sm:w-72 lg:w-80">
                                    <i class="hgi-stroke hgi-search-01 text-base-content/40"></i>
                                    <input placeholder="Search roles" aria-label="Search roles" type="search" x-model="filters.search" @input.debounce.300ms="search()" />
                                </label>
                                <button type="button" class="btn btn-ghost btn-sm justify-start" @click="resetFilters()" :disabled="!hasActiveFilters()">
                                    Reset
                                </button>
                            </div>
                            <button class="btn btn-sm btn-primary gap-2" @click="addNew">
                                <i class="hgi-stroke hgi-plus-sign"></i>
                                New Role
                            </button>
                        </div>
                    </div>

                    <div class="overflow-visible md:min-h-0 md:flex-1 md:overflow-auto">
                        <!-- Table -->
                        <div class="overflow-auto">
                            <table class="table table-sm w-full">
                                <thead>
                                    <tr>
                                        <th>Name</th>
                                        <th>Users</th>
                                        <th>Routes</th>
                                        <th class="text-end">Actions</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <template x-for="item in visibleRecords()" :key="item.id">
                                        <tr class="hover:bg-base-200/35 *:text-nowrap cursor-pointer outline-none focus-visible:bg-base-200/45 focus-visible:ring-2 focus-visible:ring-primary/45 focus-visible:ring-inset" role="button" tabindex="0" @click="select(item)" @keydown.enter.prevent="select(item)" @keydown.space.prevent="select(item)" :aria-label="`Edit role ${item.name}`">
                                            <td class="font-medium" x-text="item.name"></td>
                                            <td>
                                                <button
                                                    @click.stop="showUsersForRole(item)"
                                                    class="badge badge-ghost hover:badge-primary cursor-pointer gap-1.5 transition-colors"
                                                    :class="{ 'badge-outline': item.user_count === 0 }"
                                                >
                                                    <i class="hgi-stroke hgi-user-group text-xs"></i>
                                                    <span x-text="item.user_count"></span>
                                                </button>
                                            </td>
                                            <td>
                                                <button
                                                    @click.stop="showRoutesForRole(item)"
                                                    class="badge badge-ghost hover:badge-secondary cursor-pointer gap-1.5 transition-colors"
                                                    :class="{ 'badge-outline': item.route_count === 0 }"
                                                >
                                                    <i class="hgi-stroke hgi-route-01 text-xs"></i>
                                                    <span x-text="item.route_count"></span>
                                                </button>
                                            </td>
                                            <td>
                                                <div class="flex items-center justify-end gap-1">
                                                    <button @click.stop="select(item)" class="btn btn-square btn-ghost btn-sm" aria-label="Edit">
                                                        <i class="hgi-stroke hgi-pencil-edit-02 text-base-content/80"></i>
                                                    </button>
                                                    <button @click.stop="confirmDelete(item)" class="btn btn-square btn-ghost btn-sm" aria-label="Delete">
                                                        <i class="hgi-stroke hgi-delete-02 text-error/80"></i>
                                                    </button>
                                                </div>
                                            </td>
                                        </tr>
                                    </template>
                                </tbody>
                            </table>
                        </div>

                        <!-- Empty State -->
                        <div x-show="records.length === 0" class="text-center py-16">
                            <i class="hgi-stroke hgi-user-group text-base-content/30 text-5xl"></i>
                            <h3 class="mt-2 text-sm font-medium">No roles found</h3>
                            <p class="mt-1 text-sm text-base-content/60">Try adjusting your search or create a new role</p>
                            <div class="mt-6">
                                <button @click="addNew" class="btn btn-primary">
                                    <i class="hgi-stroke hgi-plus-sign"></i>
                                    New Role
                                </button>
                            </div>
                        </div>

                    </div>

                        <div class="flex flex-col gap-2 border-t border-base-300 bg-base-100/95 px-4 py-1.5 text-[0.6875rem] leading-5 text-base-content/50 shadow-[0_-8px_20px_oklch(19.5%_0.02_41_/_0.035)] sm:flex-row sm:items-center sm:justify-between" x-show="records.length > 0">
                            <span>
                                <strong class="font-semibold text-base-content" x-text="totalUsers()"></strong> users ·
                                <strong class="font-semibold text-base-content" x-text="totalRoutes()"></strong> routes
                            </span>
                            <div class="flex flex-wrap items-center gap-x-2.5 gap-y-1 sm:justify-end">
                                <label class="flex items-center gap-1.5">
                                    <span class="font-medium uppercase tracking-[0.08em] text-base-content/42">Rows</span>
                                    <select class="select h-7 min-h-7 w-14 rounded-md border-base-300 bg-base-100 px-2 text-xs focus:outline-primary/55 focus:outline-offset-2" x-model.number="limit" aria-label="Roles per page">
                                        <option :value="20">20</option>
                                        <option :value="50">50</option>
                                        <option :value="100">100</option>
                                    </select>
                                </label>
                                <span class="tabular-nums">
                                    <strong class="font-semibold text-base-content" x-text="visibleRecords().length ? 1 : 0"></strong>–<strong class="font-semibold text-base-content" x-text="visibleRecords().length"></strong> of <strong class="font-semibold text-base-content" x-text="records.length"></strong>
                                </span>
                                <button type="button" class="btn btn-ghost btn-xs h-6 min-h-6 px-2" x-show="canShowMore()" @click="showMore()">
                                    More
                                </button>
                            </div>
                        </div>
                </div>

                <!-- Edit Modal -->
                <dialog x-ref="editModal" class="modal" :class="{ 'modal-open': showEditModal }">
                    <div class="modal-box">
                        <h3 class="text-lg font-semibold mb-4">Role</h3>

                        <div class="space-y-4">
                            <div class="form-control">
                                <label class="label">
                                    <span class="label-text font-medium">Name *</span>
                                </label>
                                <input type="text" class="input input-bordered w-full" x-model="current_record.name" required>
                            </div>
                        </div>

                        <div class="modal-action">
                            <button type="button" @click="showEditModal = false" class="btn btn-ghost">
                                Cancel
                            </button>
                            <button type="button" @click="handleSave" class="btn btn-primary">
                                <i class="hgi-stroke hgi-save"></i>
                                Save
                            </button>
                        </div>
                    </div>
                    <form method="dialog" class="modal-backdrop">
                        <button @click="showEditModal = false">close</button>
                    </form>
                </dialog>

                <!-- Delete Confirmation Modal -->
                <dialog x-ref="deleteModal" class="modal" :class="{ 'modal-open': showDeleteModal }">
                    <div class="modal-box">
                        <div class="flex items-start gap-4">
                            <div class="flex-shrink-0 w-10 h-10 rounded-full bg-error/10 flex items-center justify-center">
                                <i class="hgi-stroke hgi-alert-02 text-error"></i>
                            </div>
                            <div>
                                <h3 class="text-lg font-semibold">Delete Role</h3>
                                <p class="mt-2 text-sm text-base-content/60">Are you sure you want to delete this role? This action cannot be undone.</p>
                            </div>
                        </div>

                        <div class="modal-action">
                            <button type="button" @click="showDeleteModal = false" class="btn btn-ghost">
                                Cancel
                            </button>
                            <button type="button" @click="handleDelete" class="btn btn-error">
                                <i class="hgi-stroke hgi-delete-02"></i>
                                Delete
                            </button>
                        </div>
                    </div>
                    <form method="dialog" class="modal-backdrop">
                        <button @click="showDeleteModal = false">close</button>
                    </form>
                </dialog>

                <!-- Users Modal -->
                <dialog class="modal" :class="{ 'modal-open': showUsersModal }">
                    <div class="modal-box">
                        <div class="flex items-center justify-between mb-4">
                            <h3 class="text-lg font-semibold">
                                Users with role: <span class="text-primary" x-text="usersModalRole?.name"></span>
                            </h3>
                            <button @click="showUsersModal = false" class="btn btn-sm btn-circle btn-ghost">
                                <i class="hgi-stroke hgi-cancel-01"></i>
                            </button>
                        </div>

                        <!-- Loading state -->
                        <div x-show="usersLoading" class="flex justify-center py-8">
                            <span class="loading loading-spinner loading-md"></span>
                        </div>

                        <!-- Users list -->
                        <div x-show="!usersLoading">
                            <template x-if="roleUsers.length > 0">
                                <div class="divide-y divide-base-200">
                                    <template x-for="user in roleUsers" :key="user.id">
                                        <div class="flex items-center gap-3 py-3">
                                            <div class="avatar placeholder">
                                                <div class="bg-neutral text-neutral-content w-10 rounded-full">
                                                    <span x-text="user.full_name?.charAt(0)?.toUpperCase() || '?'"></span>
                                                </div>
                                            </div>
                                            <div class="flex-1 min-w-0">
                                                <p class="font-medium truncate" x-text="user.full_name || 'Unknown'"></p>
                                                <p class="text-sm text-base-content/60 truncate" x-text="user.email || '—'"></p>
                                            </div>
                                        </div>
                                    </template>
                                </div>
                            </template>

                            <!-- Empty state -->
                            <template x-if="roleUsers.length === 0">
                                <div class="text-center py-8">
                                    <i class="hgi-stroke hgi-user-block-01 text-base-content/30 text-4xl"></i>
                                    <p class="mt-2 text-sm text-base-content/60">No users have this role</p>
                                </div>
                            </template>
                        </div>

                        <div class="modal-action">
                            <button type="button" @click="showUsersModal = false" class="btn btn-ghost">
                                Close
                            </button>
                        </div>
                    </div>
                    <form method="dialog" class="modal-backdrop">
                        <button @click="showUsersModal = false">close</button>
                    </form>
                </dialog>

                <!-- Routes Modal -->
                <dialog class="modal" :class="{ 'modal-open': showRoutesModal }">
                    <div class="modal-box max-w-2xl">
                        <div class="flex items-center justify-between mb-4">
                            <h3 class="text-lg font-semibold">
                                Routes for role: <span class="text-secondary" x-text="routesModalRole?.name"></span>
                            </h3>
                            <button @click="showRoutesModal = false" class="btn btn-sm btn-circle btn-ghost">
                                <i class="hgi-stroke hgi-cancel-01"></i>
                            </button>
                        </div>

                        <!-- Loading state -->
                        <div x-show="routesLoading" class="flex justify-center py-8">
                            <span class="loading loading-spinner loading-md"></span>
                        </div>

                        <!-- Routes list -->
                        <div x-show="!routesLoading">
                            <template x-if="roleRoutes.length > 0">
                                <div class="divide-y divide-base-200">
                                    <template x-for="route in roleRoutes" :key="route.id">
                                        <div class="flex items-center gap-3 py-3">
                                            <div class="flex-shrink-0 w-8 h-8 rounded bg-secondary/10 flex items-center justify-center">
                                                <i class="hgi-stroke hgi-route-01 text-secondary text-sm"></i>
                                            </div>
                                            <div class="flex-1 min-w-0">
                                                <p class="font-mono text-sm font-medium truncate" x-text="route.url"></p>
                                                <p class="text-xs text-base-content/50 truncate" x-text="route.mapping"></p>
                                            </div>
                                        </div>
                                    </template>
                                </div>
                            </template>

                            <!-- Empty state -->
                            <template x-if="roleRoutes.length === 0">
                                <div class="text-center py-8">
                                    <i class="hgi-stroke hgi-route-03 text-base-content/30 text-4xl"></i>
                                    <p class="mt-2 text-sm text-base-content/60">No routes assigned to this role</p>
                                </div>
                            </template>
                        </div>

                        <div class="modal-action">
                            <button type="button" @click="showRoutesModal = false" class="btn btn-ghost">
                                Close
                            </button>
                        </div>
                    </div>
                    <form method="dialog" class="modal-backdrop">
                        <button @click="showRoutesModal = false">close</button>
                    </form>
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

        </cf_layout_default>
    </cffunction>


</cfcomponent>
