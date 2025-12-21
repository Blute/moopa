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


    <cffunction name="search.filters.company_id">
        <cfreturn application.lib.db.search(table_name='company', q="#url.q?:''#") />
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
                SELECT #application.lib.db.select(table_name="moo_profile", field_list="id,full_name,company_name,company_id,email,mobile,address,roles,is_employee,employee_type,can_login,hero_employee_id,hero_employee_number,profile_picture_id,profile_avatar_id")#
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


                <cfif len(request.data.filter.company_id.id?:'')>
                    AND company_id = <cfqueryparam cfsqltype="other" value="#request.data.filter.company_id.id#" />
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



    <cffunction name="search.current_record.company_id">
        <cfreturn application.lib.db.search(table_name='company', q="#url.q?:''#") />
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
        <cf_layout_default container="container-fluid">



            <div x-data="admin">


                <div class="d-flex align-items-center mb-3">
                    <h1>Profiles</h1>
                    <button type="button" class="btn btn-outline-primary ms-auto" @click="addNew">Add Profile</button>
                </div>

                <div class="d-flex gap-4 flex-column flex-xl-row  align-items-xl-start">
                    <div >
                        <div class="card p-3" style="width:260px">
                            <cf_input_text label="" model="filters.term" modifiers=".debounce" placeholder="Search" />
                            

                            <cf_input_many_to_one label="Company" model="filters.company_id" modifiers=".debounce" />

                            <div class="mb-3">
                                <label for="filter_employee_type" class="form-label mb-0 fw-bold">Type</label>
                                <select class="form-select" id="filter_employee_type" x-model="filters.employee_type">
                                    <option value="everyone">Everyone</option>
                                    <option value="employees">Employees Only</option>
                                    <option value="non">NON Employees Only</option>
                                    <option value="salary">Salary Only</option>
                                    <option value="hourly">Hourly Only</option>
                                    <option value="contract_labour">Contract Labour Only</option>
                                </select>
                            </div>
                            <button type="button" class="btn btn-outline-primary" @click="resetFilter">Reset</button>
                        </div>
                    </div>

                    <div class="bg-white">
                        <table class="table table-hover table-sm" style="table-layout: fixed;">
                            <colgroup>
                                <col style="min-width:200px;">
                                <col style="min-width:200px;">
                                <col style="width:100px;">
                                <col style="width:160px;">
                                <col style="width:90px;">
                            </colgroup>
                        <thead>
                        <tr>
                            <th>Full Name</th>
                            <th>Company</th>
                            <th>Mobile</th>
                            <th>Login</th>
                            <th></th>
                        </tr > 
                        </thead>  
                        <tbody>             
                        <template x-for="(item, index) in records" :key="item.id">
                            <tr @dblclick="select(item)" role="button" style="user-select: none;">

                                <td class="fw-bold"><span  x-text="item.full_name"></span> <span x-text="item.preferred_name"></span></td>
                                <td>
                                    <div class="text-truncate">
                                        <div x-show="!item.company_id || !item.company_id.id" class="fst-italic text-warning">
                                            Entered as 
                                            <span x-text="item.company_name"></span>
                                        </div>
                                        <span x-text="item.company_id.name"></span>
                                    </div>
                                </td>
                                <td class=""><div class="text-truncate"><span x-text="item.mobile"></span></div></td>
                                <td class="">
                                    <div class="text-truncate">

                                        <i class="fal fa-right-to-bracket me-2" :class="{'text-success': item.can_login, 'opacity-25': !item.can_login}" :title="item.can_login? 'Can Login' : 'Cannot login'"></i>

                                        <span x-text="item.employee_type" x-show="item.is_employee == 1"></span>
                                        <span x-show="item.is_employee == 1">
                                            ##<span x-text="item.hero_employee_number"></span>
                                        </span>
                                    </div>

                                </td>
                                <td>
                                    <a :href="`/moo_profile/${item.id}/diary`" class="btn btn-outline-primary border-0" @click.stop="" >
                                        <i class="fat fa-clock"></i>
                                    </a>
                                    <button class="btn btn-outline-danger border-0" @click.stop="openModalDelete(item)" >
                                        <i class="fat fa-trash"></i>
                                    </button>
                                </td>
                            </tr >
                        </template>
                        </tbody>
                        </table>

                        <cf_modal id="editModal" title="Edit" size="modal-lg">

                            <cf_fields table_name="moo_profile" fields="full_name,email,mobile,company_id" />

                            <div class="text-muted text-sm mb-3">
                                Company Name was entered as: <span class="fw-bold" x-text="current_record.company_name"></span>
                            </div>

                            <cf_fields table_name="moo_profile" fields="profile_picture_id" />

                            <button class="btn btn-primary" @click="generateAvatar(current_record)">Generate Avatar</button>


                            <cf_fields table_name="moo_profile" fields="roles,address,can_login" />


                            <div class="d-flex gap-4">
                                <div>
                                    <cf_fields table_name="moo_profile" fields="is_employee" />
                                </div>
                                <div  x-show="current_record.is_employee">
                                    <cf_fields table_name="moo_profile" fields="employee_type,hero_employee_id,hero_employee_number" />
                                </div>
                            </div>

                            <cf_fragment name="actions">
                                <button class="btn btn-primary" @click="handleSave">Save</button>
                            </cf_fragment>
                        </cf_modal>


                        <!---
                        DELETE MODAL
                        --->
                        <cf_modal id="deleteConfirmationModal" title="Delete Confirmation" closeButtonText="Cancel" size="modal-sm">
                            <div class="text-center">
                                <i class="fal fa-light-emergency-on fa-3x text-danger"></i>
                                <h3>Delete: <span x-text="current_record.name"></span></h3>
                                <p> Warning: This cannot be undone.</p>
                            </div>
                            <cf_fragment name="actions">
                                <button class="btn btn-danger" @click="deleteRecord()">Yes, Delete Please</button>
                            </cf_fragment>
                        </cf_modal>


                    </div>
                </div>
            </div>


            <script>
            document.addEventListener('alpine:init', () => {

                Alpine.data('admin', () => ({
                    error_messages: [],
                    appState: 'idle',
                    filters: {},
                    records: [],
                    current_record: {},


                    init()  {
                        this.resetFilter();
                        this.load();
                        this.$watch('filters', () => this.load());
                    },

                    generateAvatar(item) {
                        fetchData({
                            endpoint: 'generateAvatar',
                            id: item.id
                        }).then(res => {
                            console.log(res)
                        });
                    },

                    async load() {
                        this.records = await fetchData({
                            method: 'POST',
                            endpoint: 'search',
                            body: {
                                filter:this.filters
                            }
                        });
                    },

                    resetFilter() {
                        this.filters = {
                            term: '',
                            employee_type: 'everyone',
                            company_id: {}
                        }
                    },

                    async handleSave() {
                        await fetchData({
                            method: 'POST',
                            endpoint: 'save',
                            body: this.current_record
                        });
                        this.load()
                        this.current_record = {}
                        bootstrap.Modal.getInstance(this.$refs.editModal).hide()
                    },

                    async addNew() {
                        this.current_record = await fetchData({
                            method: 'GET',
                            endpoint: 'new'
                        });
                        bootstrap.Modal.getInstance(this.$refs.editModal).show()
                    },

                    select(item) {
                        this.current_record = JSON.parse(JSON.stringify(item))
                        bootstrap.Modal.getInstance(this.$refs.editModal).show()
                    },

                    openModalDelete(current_record) {
                        this.current_record = current_record
                        bootstrap.Modal.getInstance(this.$refs.deleteConfirmationModal).show()
                    },

                    async deleteRecord() {
                        await fetchData({
                            method: 'DELETE',
                            id: this.current_record.id
                        });

                        this.load()
                        this.current_record = {}
                        bootstrap.Modal.getInstance(this.$refs.deleteConfirmationModal).hide()

                    },


                }))
            })
            </script>


        </cf_layout_default>
    </cffunction>


</cfcomponent>
