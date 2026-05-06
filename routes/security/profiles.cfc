<cfcomponent key="88fcf7cb-d88c-41b0-b1c8-861c1cfe1895">


    <cffunction name="uploadFileToServerWithProgress.profile_picture_id">

        <cfparam name="request.data.file_id" default="" />
        <cfparam name="request.data.file_name" default="" />
        <cfparam name="request.data.file_size" default="" />
        <!--- <cfparam name="request.data.file" default="" /> --->


        <!--- Calling without the ID will generate the record for then will call again when the file is uploaded --->
        <cfif !len(request.data.file_id)>

            <cfset res = {} />

            <cfset file_extension = listLast(request.data.file_name,".") />

            <cfset new_path = "/moo_file/#dateFormat(now(),'yyyy-mm')#/#createUUID()#/#request.data.file_name#" />
            <cfset new_thumbnail = '/icons/square-o/#file_extension#.svg' />


            <cfset new_file = application.lib.db.save(
                table_name : 'moo_file',
                data : {
                    name : request.data.file_name,
                    size : request.data.file_size,
                    thumbnail: new_thumbnail,
                    path : new_path
                },
                returnAsCFML:true
            ) />
            <cfset res.file = application.lib.db.read( table_name : 'moo_file', id : new_file.id, returnAsCFML=true ) />


            <cfset res.presignedURL = s3generatePresignedUrl(
                bucket= '#server.system.environment.S3_bucket#',
                objectName = new_path,
                httpMethod = "PUT",
                expireDate = dateAdd('n', 5, now())
            ) />


            <cfreturn res />
        </cfif>


        <cfset new_file = application.lib.db.read( table_name : 'moo_file', id : request.data.file_id, returnAsCFML:true ) />

        <cfset file_extension = listLast(new_file.name,".") />

        <cfif listFindNoCase("JPG,JPEG,PNG,GIF,WebP,SVG,TIFF,BMP,HEIF", file_extension)>
            <cfset save_data = application.lib.db.save(
                    table_name : 'moo_file',
                    data : {
                        id : request.data.file_id,
                        thumbnail: '#new_file.path#'
                    },
                    returnAsCFML:true
                ) />


            <cfset new_file = application.lib.db.read( table_name : 'moo_file', id : request.data.file_id ) />
        </cfif>


        <cfreturn new_file>
    </cffunction>


    <cffunction name="read">
        <cfreturn application.lib.db.read(table_name='moo_profile', id=id, field_list="*", returnAsCFML=true) />
    </cffunction>


    <cffunction name="getAuthTypes">
        <cfquery name="qAuthTypes">
            SELECT COALESCE(array_to_json(array_agg(auth_type ORDER BY auth_type))::text, '[]') AS recordset
            FROM (
                SELECT DISTINCT auth_type
                FROM moo_profile
                WHERE auth_type IS NOT NULL AND auth_type <> ''
            ) AS t
        </cfquery>
        <cfreturn qAuthTypes.recordset />
    </cffunction>


    <cffunction name="search">

        <cfset searchTerm = request.data.filter.term?:'' />
        <cfset authTypeFilter = request.data.filter.auth_type?:'' />

        <cfquery name="qData">
        SELECT COALESCE(array_to_json(array_agg(row_to_json(data)))::text, '[]') AS recordset
        FROM (
            SELECT #application.lib.db.select(table_name="moo_profile", field_list="id,full_name,email,mobile,address,roles,is_employee,employee_type,can_login,profile_picture_id,profile_avatar_id,auth_type,external_auth_id,last_login_at")#,
                COALESCE((
                    SELECT json_agg(moo_role.name ORDER BY moo_role.name)
                    FROM moo_profile_roles
                    INNER JOIN moo_role ON moo_role.id = moo_profile_roles.foreign_id
                    WHERE moo_profile_roles.primary_id = moo_profile.id
                ), '[]') AS role_labels
            FROM moo_profile
            WHERE 1=1
            <cfif len(searchTerm)>
                AND <cfqueryparam cfsqltype="varchar" value="#searchTerm#" /> <% search_text
            </cfif>
            <cfif len(authTypeFilter)>
                AND moo_profile.auth_type = <cfqueryparam cfsqltype="varchar" value="#authTypeFilter#" />
            </cfif>
            <cfif len(searchTerm)>
                ORDER BY word_similarity(<cfqueryparam cfsqltype="varchar" value="#searchTerm#" />, search_text) DESC
            <cfelse>
                ORDER BY moo_profile.full_name
            </cfif>
            LIMIT 100
        ) AS data
        </cfquery>

        <cfreturn qData.recordset />

    </cffunction>





    <cffunction name="new">
        <cfreturn application.lib.db.getNewObject( "moo_profile"  ) />
    </cffunction>

    <cffunction name="save">
        <cfreturn application.lib.db.save(
            table_name = "moo_profile",
            data = request.data
        ) />
    </cffunction>

    <cffunction name="delete">
        <cfreturn application.lib.db.delete(table_name="moo_profile", id="#url.id#") />
    </cffunction>


    <cffunction name="search.current_record.roles">
        <cfreturn application.lib.db.search(table_name='moo_role', q="#url.q?:''#") />
    </cffunction>

    <cffunction name="search.roles">
        <cfreturn application.lib.db.search(table_name='moo_role', q="#url.q?:''#", field_list="id,label") />
    </cffunction>


    <cffunction name="get" output="true">
        <cf_layout_default content_class="w-full">

            <div x-data="profiles_admin" x-cloak class="flex flex-col gap-6">
                <!-- Page Title -->
                <p class="text-lg font-medium">Profiles</p>

                <!-- Profiles Card -->
                <div class="card card-border bg-base-100">
                    <div class="card-body p-0">
                        <!-- Filters Bar -->
                        <div class="flex items-center justify-between px-5 pt-5">
                            <div class="inline-flex items-center gap-3">
                                <label class="input input-sm" @input.debounce.500ms="load()" @change.stop>
                                    <i class="fal fa-search text-base-content/80"></i>
                                    <input type="text" class="w-48" placeholder="Search profiles..." x-model="filters.term">
                                </label>
                                <select class="select select-sm" x-model="filters.auth_type" @change="load()">
                                    <option value="">All Auth Types</option>
                                    <template x-for="type in auth_types" :key="type">
                                        <option :value="type" x-text="type"></option>
                                    </template>
                                </select>
                                <button class="btn btn-ghost btn-sm" @click="resetFilters()" title="Clear filters">
                                    <i class="fal fa-times"></i>
                                </button>
                            </div>
                            <div class="inline-flex items-center gap-3">
                                <button class="btn btn-primary btn-sm" @click="addNew">
                                    <i class="fal fa-plus"></i>
                                    New Profile
                                </button>
                            </div>
                        </div>

                        <!-- Loading State -->
                        <template x-if="loading">
                            <div class="p-6 text-center text-base-content/60">
                                <span class="loading loading-spinner loading-md"></span>
                                <p class="mt-2">Loading profiles…</p>
                            </div>
                        </template>

                        <!-- Table -->
                        <div class="mt-4 overflow-auto" x-show="!loading">
                                <table class="table">
                                    <thead>
                                        <tr>
                                            <th>Full Name</th>
                                            <th>Mobile</th>
                                            <th>Roles</th>
                                            <th>Status</th>
                                            <th>Auth Type</th>
                                            <th>External Auth ID</th>
                                            <th>Last Login</th>
                                            <th class="text-end">Actions</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        <template x-for="item in records" :key="item.id">
                                            <tr class="hover:bg-base-200/40 cursor-pointer" @click="select(item)">
                                                <!-- Full Name with Avatar -->
                                                <td>
                                                    <div class="flex items-center gap-3">
                                                        <template x-if="item.profile_picture_id?.thumbnail">
                                                            <div class="avatar">
                                                                <div class="w-10 rounded-full bg-base-200">
                                                                    <img :src="item.profile_picture_id.thumbnail" :alt="item.full_name" />
                                                                </div>
                                                            </div>
                                                        </template>
                                                        <template x-if="!item.profile_picture_id?.thumbnail">
                                                            <div class="avatar avatar-placeholder">
                                                                <div class="bg-neutral text-neutral-content w-10 rounded-full flex items-center justify-center">
                                                                    <span class="text-xs font-semibold" x-text="getInitials(item.full_name)"></span>
                                                                </div>
                                                            </div>
                                                        </template>
                                                        <div class="min-w-0 max-w-[260px]">
                                                            <p class="font-medium truncate" x-text="item.full_name" :title="item.full_name"></p>
                                                            <p class="text-xs text-base-content/60 truncate" x-text="item.email" :title="item.email"></p>
                                                        </div>
                                                    </div>
                                                </td>
                                                <!-- Mobile -->
                                                <td>
                                                    <span class="text-sm" x-text="item.mobile || '—'"></span>
                                                </td>
                                                <!-- Roles -->
                                                <td>
                                                    <div class="flex flex-wrap gap-1">
                                                        <template x-for="role in item.role_labels" :key="role">
                                                            <span class="badge badge-sm badge-soft badge-neutral" x-text="role"></span>
                                                        </template>
                                                        <template x-if="!item.role_labels?.length">
                                                            <span class="text-base-content/40 text-sm">—</span>
                                                        </template>
                                                    </div>
                                                </td>
                                                <!-- Status -->
                                                <td>
                                                    <div class="flex items-center gap-2 flex-wrap">
                                                        <!-- Login Status -->
                                                        <i class="fal fa-right-to-bracket" :class="item.can_login ? 'text-success' : 'text-base-content/30'" x-bind:title="item.can_login ? 'Can Login' : 'Cannot Login'"></i>
                                                        <!-- Employee Badge -->
                                                        <template x-if="item.is_employee">
                                                            <span class="badge badge-sm badge-soft badge-info capitalize" x-text="item.employee_type || 'employee'"></span>
                                                        </template>
                                                        <template x-if="item.is_employee && item.hero_employee_number">
                                                            <span class="badge badge-sm badge-ghost" x-text="'##' + item.hero_employee_number"></span>
                                                        </template>
                                                    </div>
                                                </td>
                                                <!-- Auth Type -->
                                                <td>
                                                    <span class="text-xs font-mono text-base-content/70" x-text="item.auth_type || '—'"></span>
                                                </td>
                                                <!-- External Auth ID -->
                                                <td>
                                                    <span class="text-xs font-mono text-base-content/70" x-text="item.external_auth_id || '—'"></span>
                                                </td>
                                                <!-- Last Login -->
                                                <td>
                                                    <span class="text-xs font-mono text-base-content/70" x-text="prettyDate(item.last_login_at) || '—'" :title="prettyDateTitle(item.last_login_at) || '—'"></span>
                                                </td>
                                                <!-- Actions -->
                                                <td>
                                                    <div class="flex items-center justify-end gap-1">
                                                        <template x-if="['gday','agent'].includes(item.auth_type)">
                                                            <cf_impersonate_button click="impersonate(item.id)" />
                                                        </template>
                                                        <button class="btn btn-ghost btn-sm btn-square" @click.stop="select(item)" title="Edit">
                                                            <i class="fal fa-pencil text-base-content/70"></i>
                                                        </button>

                                                        <button class="btn btn-ghost btn-sm btn-square text-error" @click.stop="openDeleteModal(item)" title="Delete">
                                                            <i class="fal fa-trash"></i>
                                                        </button>
                                                    </div>
                                                </td>
                                            </tr>
                                        </template>
                                        <!-- Empty State -->
                                        <template x-if="!loading && records.length === 0">
                                            <tr>
                                                <td colspan="6" class="text-center py-8 text-base-content/60">
                                                    <i class="fal fa-users fa-2x mb-2 block"></i>
                                                    No profiles found
                                                </td>
                                            </tr>
                                        </template>
                                    </tbody>
                                </table>
                        </div>
                    </div>
                </div>

                <!-- Edit Modal -->
                <dialog id="edit_modal" class="modal" x-ref="editModal">
                    <div class="modal-box max-w-2xl">
                        <div class="flex items-center justify-between mb-4">
                            <h3 class="text-lg font-semibold" x-text="current_record.id ? 'Edit Profile' : 'New Profile'"></h3>
                            <form method="dialog">
                                <button class="btn btn-sm btn-ghost btn-circle" aria-label="Close">
                                    <i class="fal fa-times"></i>
                                </button>
                            </form>
                        </div>

                        <div class="space-y-4">
                            <!-- Basic Info -->
                            <cf_table_controls table_name="moo_profile" fields="full_name" />
                            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                                <cf_table_controls table_name="moo_profile" fields="email,mobile" />
                            </div>

                            <!-- Profile Picture -->
                            <div class="divider text-sm text-base-content/50">Profile Picture</div>
                            <cf_table_controls table_name="moo_profile" fields="profile_picture_id" />

                            <!-- Permissions & Address -->
                            <div class="divider text-sm text-base-content/50">Permissions & Address</div>
                            <cf_table_controls table_name="moo_profile" fields="roles" />
                            <cf_table_controls table_name="moo_profile" fields="address" />
                            <cf_table_controls table_name="moo_profile" fields="can_login" />

                            <!-- External Auth -->
                            <div class="divider text-sm text-base-content/50">External Authentication</div>
                            <template x-if="current_record.external_auth_id">
                                <fieldset class="fieldset">
                                    <legend class="fieldset-legend">External Auth ID</legend>
                                    <div class="text-xs font-mono text-base-content/70 break-all" x-text="current_record.external_auth_id"></div>
                                    <p class="fieldset-label text-base-content/50">Issued by the third-party identity provider — not editable here.</p>
                                </fieldset>
                            </template>
                            <template x-if="!current_record.external_auth_id">
                                <fieldset class="fieldset">
                                    <legend class="fieldset-legend">External Auth ID</legend>
                                    <div class="text-sm text-base-content/50 italic">No external identity linked.</div>
                                </fieldset>
                            </template>


                        </div>

                        <div class="modal-action">
                            <form method="dialog">
                                <button class="btn btn-ghost">Cancel</button>
                            </form>
                            <button class="btn btn-primary" @click="handleSave">
                                <i class="fal fa-check"></i>
                                Save
                            </button>
                        </div>
                    </div>
                    <form method="dialog" class="modal-backdrop">
                        <button>close</button>
                    </form>
                </dialog>

                <!-- Delete Confirmation Modal -->
                <dialog id="delete_modal" class="modal" x-ref="deleteModal">
                    <div class="modal-box max-w-sm text-center">
                        <div class="py-4">
                            <i class="fal fa-triangle-exclamation fa-3x text-error mb-4 block"></i>
                            <h3 class="text-lg font-semibold">Delete Profile</h3>
                            <p class="text-base-content/70 mt-2">
                                Are you sure you want to delete <span class="font-medium" x-text="current_record.full_name"></span>?
                            </p>
                            <p class="text-sm text-error mt-2">This action cannot be undone.</p>
                        </div>
                        <div class="modal-action justify-center">
                            <form method="dialog">
                                <button class="btn btn-ghost">Cancel</button>
                            </form>
                            <button class="btn btn-error" @click="deleteRecord">
                                <i class="fal fa-trash"></i>
                                Delete
                            </button>
                        </div>
                    </div>
                    <form method="dialog" class="modal-backdrop">
                        <button>close</button>
                    </form>
                </dialog>

                <script>
                document.addEventListener('alpine:init', () => {
                    const default_filters = { term: '', auth_type: '' };

                    Alpine.data('profiles_admin', () => ({
                        loading: false,
                        records: [],
                        current_record: {},
                        filters: { ...default_filters },
                        auth_types: [],

                        getInitials(name) {
                            const cleaned = (name || '').trim();
                            if (!cleaned) return '?';
                            const parts = cleaned.split(/\s+/).filter(Boolean);
                            if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
                            return parts.slice(0, 2).map(p => (p[0] || '')).join('').toUpperCase();
                        },

                        async init() {
                            this.filters = await loadFilters(default_filters);
                            this.auth_types = await req({ endpoint: 'getAuthTypes' });
                            await this.load();
                        },

                        async load() {
                            this.loading = true;
                            this.records = await req({
                                endpoint: 'search',
                                body: { filter: this.filters }
                            });
                            this.loading = false;
                        },

                        async resetFilters() {
                            this.filters = { ...default_filters };
                            await clearFilters();
                            await this.load();
                        },

                        async handleSave() {
                            await req({ endpoint: 'save', body: this.current_record });
                            this.$refs.editModal.close();
                            this.current_record = {};
                            await this.load();
                            if (window.toast) {
                                window.toast({ type: 'success', message: 'Profile saved successfully', duration: 2000 });
                            }
                        },

                        async addNew() {
                            this.current_record = await req({ endpoint: 'new' });
                            this.$refs.editModal.showModal();
                        },

                        select(item) {
                            this.current_record = JSON.parse(JSON.stringify(item));
                            this.$refs.editModal.showModal();
                        },

                        openDeleteModal(item) {
                            this.current_record = item;
                            this.$refs.deleteModal.showModal();
                        },

                        async deleteRecord() {
                            await req({ endpoint: 'delete', id: this.current_record.id });
                            this.$refs.deleteModal.close();
                            this.current_record = {};
                            await this.load();
                            if (window.toast) {
                                window.toast({ type: 'success', message: 'Profile deleted', duration: 2000 });
                            }
                        }
                    }));
                });
                </script>
            </div>

        </cf_layout_default>
    </cffunction>


</cfcomponent>
