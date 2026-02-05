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


    <cffunction name="generateAvatar">
        <cfset profile = application.lib.db.read( table_name : 'moo_profile', id : url.id, returnAsCFML:true ) />
        <cfset profile_picture = application.lib.db.read( table_name : 'moo_file', id : profile.profile_picture_id.id, returnAsCFML:true ) />

        <cfif !len(profile.profile_picture_id)>
            <cfreturn {done:false} />
        </cfif>


        <cfset profile_picture_data = s3readBinary(bucketName="#server.system.environment.S3_bucket#", objectName=profile_picture.path)>


        <!--- Save the PDF locally for processing --->
        <cfset tempPath = "#GetTempDirectory()##getFileFromPath(profile_picture.path)#">
        <cffile action="write" file="#tempPath#" output="#profile_picture_data#">


        <cfset tempAvatarPath = "#GetTempDirectory()#avatar.png">
        <cfscript>
        // Load the Java libraries
        javaImageIO = createObject("java", "javax.imageio.ImageIO");
        javaFile = createObject("java", "java.io.File");
        javaBufferedImage = createObject("java", "java.awt.image.BufferedImage");
        javaImage = javaImageIO.read(javaFile.init(tempPath));


        // Convert to RGBA format if not already
        if (javaImage.getType() neq javaBufferedImage.TYPE_INT_ARGB) {
            convertedImage = createObject("java", "java.awt.image.BufferedImage").init(
                javaImage.getWidth(),
                javaImage.getHeight(),
                javaBufferedImage.TYPE_INT_ARGB
            );
            graphics = convertedImage.createGraphics();
            graphics.drawImage(javaImage, 0, 0, javaCast("null", ""));
            graphics.dispose();
        } else {
            convertedImage = javaImage;
        }

        // Save the converted image as PNG
        javaImageIO.write(convertedImage, "png", javaFile.init(tempAvatarPath));
        </cfscript>


<!---
        <!-- Load the image -->
        <cfimage action="read" source="#tempPath#" name="imageObj">

        <!-- Convert to PNG -->
        <cfset tempAvatarPath = "#GetTempDirectory()#avatar.png">
        <cfimage action="write" source="#imageObj#" destination="#tempAvatarPath#" format="png">

 --->
        <cfset stAnalysis = application.lib.openai.image_edits(
                prompt = "A pixel art avatar in the style of Leisure Suit Larry, depicting the person in the image uploaded. The background should be simple and unobtrusive to highlight the character.",
                image_path = tempAvatarPath,
                size = "1024x1024"
            ) />

        <cfdump var="#stAnalysis#"><cfabort>
        <cfreturn stAnalysis />

    </cffunction>


    <cffunction name="read">
        <cfreturn application.lib.db.read(table_name='moo_profile', id=id, field_list="*", returnAsCFML=true) />
    </cffunction>


    <cffunction name="search">

        <cfset searchTerm = request.data.filter.term?:'' />

        <cfreturn application.lib.db.search(
            table_name = "moo_profile",
            field_list = "id,full_name,email,mobile,address,roles,is_employee,employee_type,can_login,hero_employee_id,hero_employee_number,profile_picture_id,profile_avatar_id,external_auth_id",
            q = searchTerm,
            limit = 100,
            select_append = "COALESCE((
                SELECT json_agg(moo_role.name ORDER BY moo_role.name)
                FROM moo_profile_roles
                INNER JOIN moo_role ON moo_role.id = moo_profile_roles.foreign_id
                WHERE moo_profile_roles.primary_id = moo_profile.id
            ), '[]') AS role_labels"
        ) />

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
                                    <span class="fal fa-search text-base-content/80"></span>
                                    <input type="text" class="w-48" placeholder="Search profiles..." x-model="filters.term">
                                </label>
                                <button class="btn btn-ghost btn-sm" @click="resetFilters()" title="Clear filters">
                                    <span class="fal fa-times"></span>
                                </button>
                            </div>
                            <div class="inline-flex items-center gap-3">
                                <button class="btn btn-primary btn-sm" @click="addNew">
                                    <span class="fal fa-plus"></span>
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
                                            <th>External Auth ID</th>
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
                                                        <div class="min-w-0">
                                                            <p class="font-medium truncate" x-text="item.full_name"></p>
                                                            <p class="text-xs text-base-content/60 truncate" x-text="item.email"></p>
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
                                                        <span class="fal fa-right-to-bracket"
                                                              :class="item.can_login ? 'text-success' : 'text-base-content/30'"
                                                              :title="item.can_login ? 'Can Login' : 'Cannot Login'"></span>
                                                        <!-- Employee Badge -->
                                                        <template x-if="item.is_employee">
                                                            <span class="badge badge-sm badge-soft badge-info capitalize" x-text="item.employee_type || 'employee'"></span>
                                                        </template>
                                                        <template x-if="item.is_employee && item.hero_employee_number">
                                                            <span class="badge badge-sm badge-ghost" x-text="'##' + item.hero_employee_number"></span>
                                                        </template>
                                                    </div>
                                                </td>
                                                <!-- External Auth ID -->
                                                <td>
                                                    <span class="text-xs font-mono text-base-content/70" x-text="item.external_auth_id || '—'"></span>
                                                </td>
                                                <!-- Actions -->
                                                <td>
                                                    <div class="flex items-center justify-end gap-1">
                                                        <button class="btn btn-ghost btn-sm btn-square" @click.stop="select(item)" title="Edit">
                                                            <span class="fal fa-pencil text-base-content/70"></span>
                                                        </button>

                                                        <button class="btn btn-ghost btn-sm btn-square text-error" @click.stop="openDeleteModal(item)" title="Delete">
                                                            <span class="fal fa-trash"></span>
                                                        </button>
                                                    </div>
                                                </td>
                                            </tr>
                                        </template>
                                        <!-- Empty State -->
                                        <template x-if="!loading && records.length === 0">
                                            <tr>
                                                <td colspan="6" class="text-center py-8 text-base-content/60">
                                                    <span class="fal fa-users fa-2x mb-2 block"></span>
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
                                    <span class="fal fa-times"></span>
                                </button>
                            </form>
                        </div>

                        <div class="space-y-4">
                            <!-- Basic Info -->
                            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                                <cf_table_controls table_name="moo_profile" fields="full_name,email,mobile" />
                            </div>

                            <!-- Profile Picture -->
                            <div class="divider text-sm text-base-content/50">Profile Picture</div>
                            <cf_table_controls table_name="moo_profile" fields="profile_picture_id" />

                            <button class="btn btn-outline btn-sm" @click="generateAvatar(current_record)">
                                <span class="fal fa-wand-magic-sparkles"></span>
                                Generate Avatar
                            </button>

                            <!-- Permissions & Address -->
                            <div class="divider text-sm text-base-content/50">Permissions & Address</div>
                            <cf_table_controls table_name="moo_profile" fields="roles" />
                            <cf_table_controls table_name="moo_profile" fields="address" />
                            <cf_table_controls table_name="moo_profile" fields="can_login" />

                            <!-- External Auth -->
                            <div class="divider text-sm text-base-content/50">External Authentication</div>
                            <cf_table_controls table_name="moo_profile" fields="external_auth_id" />


                        </div>

                        <div class="modal-action">
                            <form method="dialog">
                                <button class="btn btn-ghost">Cancel</button>
                            </form>
                            <button class="btn btn-primary" @click="handleSave">
                                <span class="fal fa-check"></span>
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
                            <span class="fal fa-triangle-exclamation fa-3x text-error mb-4 block"></span>
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
                                <span class="fal fa-trash"></span>
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
                    const default_filters = { term: '' };

                    Alpine.data('profiles_admin', () => ({
                        loading: false,
                        records: [],
                        current_record: {},
                        filters: { ...default_filters },

                        getInitials(name) {
                            const cleaned = (name || '').trim();
                            if (!cleaned) return '?';
                            const parts = cleaned.split(/\s+/).filter(Boolean);
                            if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
                            return parts.slice(0, 2).map(p => (p[0] || '')).join('').toUpperCase();
                        },

                        async init() {
                            this.filters = await loadFilters(default_filters);
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

                        async generateAvatar(item) {
                            const res = await req({ endpoint: 'generateAvatar', id: item.id });
                            console.log(res);
                        },

                        async handleSave() {
                            await req({ endpoint: 'save', body: this.current_record });
                            this.$refs.editModal.close();
                            this.current_record = {};
                            await this.load();
                            if (window.notyf?.open) {
                                window.notyf.open({ type: 'success', message: 'Profile saved successfully', duration: 2000 });
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
                            if (window.notyf?.open) {
                                window.notyf.open({ type: 'success', message: 'Profile deleted', duration: 2000 });
                            }
                        }
                    }));
                });
                </script>
            </div>

        </cf_layout_default>
    </cffunction>


</cfcomponent>
