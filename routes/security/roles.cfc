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
        <cfparam name="url.role_id" />
        <cfquery name="q">
            SELECT COALESCE(jsonb_agg(data ORDER BY full_name)::text, '[]') as data
            FROM (
                SELECT moo_profile.id
                    , moo_profile.full_name
                    , moo_profile.email
                FROM moo_profile
                INNER JOIN moo_profile_roles ON moo_profile_roles.primary_id = moo_profile.id
                WHERE moo_profile_roles.foreign_id = <cfqueryparam value="#url.role_id#" cfsqltype="other" />
            ) as data
        </cfquery>
        <cfreturn q.data />
    </cffunction>

    <cffunction name="routes">
        <cfparam name="url.role_id" />
        <cfquery name="q">
            SELECT COALESCE(jsonb_agg(data ORDER BY url)::text, '[]') as data
            FROM (
                SELECT moo_route.id
                    , moo_route.url
                    , moo_route.mapping
                FROM moo_route
                INNER JOIN moo_route_roles ON moo_route_roles.primary_id = moo_route.id
                WHERE moo_route_roles.foreign_id = <cfqueryparam value="#url.role_id#" cfsqltype="other" />
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





    <cffunction name="get" output="true">
        <cf_layout_default content_class="w-full max-w-7xl mx-auto">

            <div x-data="roles" x-cloak class="flex flex-col gap-4">
                <!-- Header -->
                <div class="flex items-center justify-between">
                    <div>
                        <h1 class="m-0 text-lg font-medium">Roles</h1>
                    </div>

                </div>

                <!-- Content Card -->
                <div class="card bg-base-100 shadow">
                    <div class="card-body p-0">
                        <!-- Slim Filter Bar -->
                        <div class="flex items-center justify-between px-5 pt-5">
                            <div class="inline-flex items-center gap-3">
                                <label class="input input-sm">
                                    <span class="fal fa-search text-base-content/80 text-sm"></span>
                                    <input
                                        class="w-24 sm:w-36"
                                        placeholder="Search roles..."
                                        aria-label="Search roles"
                                        type="search"
                                        x-model="filters.search"
                                        @input.debounce.300ms="search()"
                                    />
                                </label>

                            </div>
                            <button class="btn btn-sm btn-primary" @click="addNew">
                                <i class="fal fa-plus"></i>
                                <span class="hidden sm:inline">New Role</span>
                            </button>
                        </div>

                        <!-- Table -->
                        <div class="mt-4 overflow-auto">
                            <table class="table">
                                <thead>
                                    <tr>
                                        <th>Name</th>
                                        <th>Description</th>
                                        <th>Users</th>
                                        <th>Routes</th>
                                        <th>Action</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <template x-for="item in records" :key="item.id">
                                        <tr class="hover:bg-base-200/40 *:text-nowrap">
                                            <td class="font-medium" x-text="item.name"></td>
                                            <td class="text-sm text-base-content/60" x-text="item.description || '—'"></td>
                                            <td>
                                                <button
                                                    @click="showUsersForRole(item)"
                                                    class="badge badge-ghost hover:badge-primary cursor-pointer gap-1.5 transition-colors"
                                                    :class="{ 'badge-outline': item.user_count === 0 }"
                                                >
                                                    <i class="fal fa-users text-xs"></i>
                                                    <span x-text="item.user_count"></span>
                                                </button>
                                            </td>
                                            <td>
                                                <button
                                                    @click="showRoutesForRole(item)"
                                                    class="badge badge-ghost hover:badge-secondary cursor-pointer gap-1.5 transition-colors"
                                                    :class="{ 'badge-outline': item.route_count === 0 }"
                                                >
                                                    <i class="fal fa-route text-xs"></i>
                                                    <span x-text="item.route_count"></span>
                                                </button>
                                            </td>
                                            <td>
                                                <button @click="select(item)" class="btn btn-square btn-ghost btn-sm" aria-label="Edit">
                                                    <i class="fal fa-pencil text-base-content/80"></i>
                                                </button>
                                                <button @click="confirmDelete(item)" class="btn btn-square btn-ghost btn-sm" aria-label="Delete">
                                                    <i class="fal fa-trash text-error/80"></i>
                                                </button>
                                            </td>
                                        </tr>
                                    </template>
                                </tbody>
                            </table>
                        </div>

                        <!-- Empty State -->
                        <div x-show="records.length === 0" class="text-center py-16">
                            <i class="fal fa-users text-base-content/30 text-5xl"></i>
                            <h3 class="mt-2 text-sm font-medium">No roles found</h3>
                            <p class="mt-1 text-sm text-base-content/60">Try adjusting your search or create a new role</p>
                            <div class="mt-6">
                                <button @click="addNew" class="btn btn-primary">
                                    <i class="fal fa-plus"></i>
                                    New Role
                                </button>
                            </div>
                        </div>

                        <!-- Footer with count -->
                        <div class="flex items-center justify-between p-6" x-show="records.length > 0">
                            <span class="text-base-content/80 text-sm">
                                Showing
                                <span class="text-base-content font-medium" x-text="records.length"></span>
                                <span x-text="records.length === 1 ? 'role' : 'roles'"></span>
                            </span>
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
                            <div class="form-control">
                                <label class="label">
                                    <span class="label-text font-medium">Description</span>
                                </label>
                                <textarea class="textarea textarea-bordered w-full" rows="3" x-model="current_record.description" placeholder="Optional description"></textarea>
                            </div>
                        </div>

                        <div class="modal-action">
                            <button type="button" @click="showEditModal = false" class="btn btn-ghost">
                                Cancel
                            </button>
                            <button type="button" @click="handleSave" class="btn btn-primary">
                                <i class="fal fa-save"></i>
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
                                <i class="fal fa-exclamation-triangle text-error"></i>
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
                                <i class="fal fa-trash"></i>
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
                                <i class="fal fa-times"></i>
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
                                    <i class="fal fa-user-slash text-base-content/30 text-4xl"></i>
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
                                <i class="fal fa-times"></i>
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
                                                <i class="fal fa-route text-secondary text-sm"></i>
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
                                    <i class="fal fa-map-signs text-base-content/30 text-4xl"></i>
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
                                    role_id: role.id
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
                                    role_id: role.id
                                });
                            } catch (error) {
                                console.error('Error loading routes:', error);
                                this.showNotification('Error loading routes', 'error');
                            } finally {
                                this.routesLoading = false;
                            }
                        },

                        showNotification(message, type = 'info') {
                            // Simple notification - you can replace with your preferred notification system
                            if (window.notyf) {
                                window.notyf.open({
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
