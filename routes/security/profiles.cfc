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


        <cfset idList = "" />

        <cfif len(request.data.filter.term?:'')>
            <cfset aProfileIDs = application.lib.db.search(table_name='moo_profile', q="#request.data.filter.term?:''#", field_list="id", returnAsCFML=true) />

            <cfset idList = ArrayToList(ArrayMap(aProfileIDs, function(item) {
                return item.id;
            }), ",")>
        </cfif>




        <cfquery name="qData">
        SELECT COALESCE(array_to_json(array_agg(row_to_json(data)))::text, '[]') AS recordset
        FROM (
                SELECT #application.lib.db.select(table_name="moo_profile", field_list="id,full_name,email,mobile,address,roles,is_employee,employee_type,can_login,hero_employee_id,hero_employee_number,profile_picture_id,profile_avatar_id")#
                FROM moo_profile
                WHERE 1 = 1

                <cfif len(request.data.filter.term?:'')>
                    <cfif len(idList)>
                        AND moo_profile.id IN (<cfqueryparam cfsqltype="other" list="true" value="#idList#" />)
                    <cfelse>
                        AND 1 = 2
                    </cfif>
                </cfif>

                <cfif len(request.data.filter.employee_type?:'')>
                    <cfswitch expression="#request.data.filter.employee_type#">
                        <cfcase value="everyone">
                            <!--- ignore --->
                        </cfcase>
                        <cfcase value="employees">
                            AND is_employee = true
                        </cfcase>
                        <cfcase value="non">
                            AND is_employee = false
                        </cfcase>
                        <cfdefaultcase>
                            AND is_employee = true
                            AND employee_type = <cfqueryparam cfsqltype="varchar" value="#request.data.filter.employee_type#" />
                        </cfdefaultcase>
                    </cfswitch>
                </cfif>



                <cfif !len(idList)>
                    ORDER BY moo_profile.full_name
                </cfif>

                LIMIT 100
        ) AS data
        </cfquery>


        <cfif len(idList)>
            <!--- We need to sort the results based on the search response --->
            <cfset unorderedRecordset = deserializeJSON(qData.recordset) />

            <cfset orderedRecordset = []>

            <cfloop list="#idList#" item="id">
                <cfloop array="#unorderedRecordset#" item="record">
                    <cfif record.id EQ id>
                        <cfset ArrayAppend(orderedRecordset, record)>
                        <cfbreak>
                    </cfif>
                </cfloop>
            </cfloop>

            <cfreturn serializeJSON(orderedRecordset) />
        <cfelse>
            <cfreturn qData.recordset />
        </cfif>

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


    <cffunction name="get" output="true">
        <cf_layout_default content_class="w-full max-w-7xl mx-auto">

            <div x-data="profiles_admin" x-cloak class="flex flex-col gap-4">
                <!-- Header -->
                <div class="flex flex-col lg:flex-row lg:items-center gap-2">
                    <div>
                        <h1 class="m-0 text-2xl font-semibold">Profiles</h1>
                        <p class="text-base-content/60 text-sm">Manage user profiles and access permissions.</p>
                    </div>
                    <div class="lg:ms-auto">
                        <button class="btn btn-primary btn-soft" @click="addNew">
                            <span class="fal fa-plus"></span>
                            Add Profile
                        </button>
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
                                    <span class="font-semibold text-base-content" x-text="records.length"></span>
                                    <span x-text="records.length === 1 ? 'profile found' : 'profiles found'"></span>
                                </p>
                            </div>

                            <!-- Filter Content -->
                            <div class="px-5 py-4 space-y-4">
                                <!-- Search -->
                                <div>
                                    <label class="block text-sm font-medium mb-2">Search</label>
                                    <label class="input input-bordered w-full">
                                        <span class="fal fa-search text-base-content/50"></span>
                                        <input type="text" class="grow" placeholder="Search profiles..." x-model.debounce="filters.term">
                                        <button
                                            x-show="filters.term"
                                            x-transition
                                            @click="filters.term = ''"
                                            class="text-base-content/40 hover:text-base-content/70"
                                        >
                                            <span class="fal fa-times"></span>
                                        </button>
                                    </label>
                                </div>


                                <!-- Type Filter -->
                                <div>
                                    <label class="block text-sm font-medium mb-2">Type</label>
                                    <select class="select select-bordered w-full" x-model="filters.employee_type">
                                        <option value="everyone">Everyone</option>
                                        <option value="employees">Employees Only</option>
                                        <option value="non">NON Employees Only</option>
                                        <option value="salary">Salary Only</option>
                                        <option value="hourly">Hourly Only</option>
                                        <option value="contract_labour">Contract Labour Only</option>
                                    </select>
                                </div>
                            </div>

                            <!-- Filter Footer -->
                            <div class="px-5 py-4 border-t border-base-200 bg-base-200/30 rounded-b-2xl">
                                <button class="btn btn-outline btn-block" @click="resetFilters()" title="Reset filters">
                                    <span class="fal fa-refresh"></span>
                                    Reset Filters
                                </button>
                            </div>
                        </div>
                    </div>

                    <!-- Profiles Table Card -->
                    <div class="flex-1 min-w-0">
                        <div class="card card-border bg-base-100">
                            <!-- Loading State -->
                            <template x-if="loading">
                                <div class="p-6 text-center text-base-content/60">
                                    <span class="loading loading-spinner loading-md"></span>
                                    <p class="mt-2">Loading profiles…</p>
                                </div>
                            </template>

                            <!-- Table -->
                            <div class="overflow-auto" x-show="!loading">
                                <table class="table">
                                    <thead>
                                        <tr>
                                            <th>Full Name</th>
                                            <th>Mobile</th>
                                            <th>Status</th>
                                            <th class="text-end">Actions</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        <template x-for="item in records" :key="item.id">
                                            <tr class="hover:bg-base-200/40 cursor-pointer" @dblclick="select(item)">
                                                <!-- Full Name with Avatar -->
                                                <td>
                                                    <div class="flex items-center gap-3">
                                                        <div class="avatar placeholder">
                                                            <div class="bg-base-300 text-base-content/70 rounded-full w-10">
                                                                <template x-if="item.profile_picture_id?.thumbnail">
                                                                    <img :src="item.profile_picture_id.thumbnail" :alt="item.full_name" class="rounded-full">
                                                                </template>
                                                                <template x-if="!item.profile_picture_id?.thumbnail">
                                                                    <span class="text-sm font-medium" x-text="(item.full_name || '?').charAt(0).toUpperCase()"></span>
                                                                </template>
                                                            </div>
                                                        </div>
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
                                                <td colspan="5" class="text-center py-8 text-base-content/60">
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
                            <cf_fields table_name="moo_profile" fields="full_name,email,mobile" />


                            <cf_fields table_name="moo_profile" fields="profile_picture_id" />

                            <button class="btn btn-outline btn-sm" @click="generateAvatar(current_record)">
                                <span class="fal fa-wand-magic-sparkles"></span>
                                Generate Avatar
                            </button>

                            <cf_fields table_name="moo_profile" fields="roles,address,can_login" />

                            <div class="flex flex-wrap gap-4">
                                <div>
                                    <cf_fields table_name="moo_profile" fields="is_employee" />
                                </div>
                                <div x-show="current_record.is_employee" x-transition class="flex-1 min-w-64">
                                    <cf_fields table_name="moo_profile" fields="employee_type,hero_employee_id,hero_employee_number" />
                                </div>
                            </div>
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
                    Alpine.data('profiles_admin', () => ({
                        loading: false,
                        records: [],
                        current_record: {},
                        filters: {
                            term: '',
                            employee_type: 'everyone'
                        },

                        async init() {
                            const saved = await loadFilters({
                                term: '',
                                employee_type: 'everyone'
                            });
                            this.filters = saved || this.filters;
                            await this.load();
                            this.$watch('filters', () => {
                                saveFilters(this.filters);
                                this.load();
                            });
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
                            this.filters = {
                                term: '',
                                employee_type: 'everyone'
                            };
                            await clearFilters();
                            await saveFilters(this.filters);
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
