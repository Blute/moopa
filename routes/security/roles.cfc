<cfcomponent key="0b348660-a526-4ad5-a807-fd7ec8d2d31c">


    <cffunction name="read">
        <cfreturn application.lib.db.read(table_name='moo_role', id=request.data.id, field_list="*", returnAsCFML=true) />
    </cffunction>


    <cffunction name="search">
        <cfreturn application.lib.db.search(table_name='moo_role', q="#url.q?:''#") />
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
                                        <th>Action</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <template x-for="item in records" :key="item.id">
                                        <tr class="hover:bg-base-200/40 *:text-nowrap">
                                            <td class="font-medium" x-text="item.name"></td>
                                            <td class="text-sm text-base-content/60" x-text="item.description || '—'"></td>
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
