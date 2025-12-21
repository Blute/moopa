<cfcomponent key="f72abf15-799d-4328-838a-ed1db1dfeb82">

    <cffunction name="index_content">

        <cfsetting requesttimeout="600" />

        <cfset results = [] />


        <cfloop array="#request.data.selectedTables#" item="table_name" index="i">

            <cfset table = application.lib.db.codeSchema[table_name] />
            <cfset indexed_data = application.lib.meilisearch.index_all_records(index_name="#table.table_name#", field_list="#table.searchable_fields#") />

            <cfset ArrayAppend(results, indexed_data) />
        </cfloop>
       

        <!-- Output the result for debugging -->
        <cfreturn results />
    </cffunction>

    <cffunction name="delete_index">
        <cfset result = application.lib.meilisearch.delete_index(index_name="#request.data.table_name#") />

        <!-- Output the result for debugging -->
        <cfreturn result />
    </cffunction>

    <cffunction name="reset_index">
        <cfset result = application.lib.meilisearch.reset_index(index_name="#request.data.table_name#") />

        <!-- Output the result for debugging -->
        <cfreturn result />
    </cffunction>



    <cffunction name="find_content">


        <cfset orderedRecordset = []>

        <cfset idList = application.lib.meilisearch.query_index(index_name="company", query="#request.data.filter_term#") />
        

        <cfif arrayLen(idList)>
            <cfquery name="recordset" returntype="array">
            SELECT
            #application.lib.db.select("company", "id,name")#
            FROM company
            WHERE id in (<cfqueryparam cfsqltype="other" list="true" value="#idList#" />)
            </cfquery>

            <!--- Reorder records based on Algolia ID list order --->
            <cfloop array="#idList#" item="id">
                <cfloop array="#recordset#" item="record">
                    <cfif record.id EQ id>
                        <cfset ArrayAppend(orderedRecordset, record)>
                        <cfbreak>
                    </cfif>
                </cfloop>
            </cfloop>

        </cfif>

        <cfreturn orderedRecordset  />
    </cffunction>


    <cffunction name="load">
        <cfset result = {} />

        <cfset result.searchable_tables = application.lib.db.getSearchableTables() />
        <cfset result.existing_in_es = application.lib.meilisearch.get_indexes() />

        <cfreturn result />
    </cffunction>




    <cffunction name="get" output="true">
        <cf_layout_default>
            


               <div x-data="algolia">

                    <h1>Meilisearch Search</h1>
                    <div class="d-flex gap-1 align-items-center mb-3">
                        <input type="checkbox" @click="selectAllTables($event.target.checked)" id="select-all"> <label for="select-all">Select All</label>


                        <button class="btn btn-outline-primary" @click="index_content">Index Selected Tables</button>

                    </div>


                    <cf_define_admin_grid class="admin-grid" grid_template_columns="80px 200px 1fr 1fr 80px" />

                    <div>
                        <template x-for="table in enhancedTables" :key="table.table_name">
                            <div class='admin-grid w-100 p-1' x-show="table.searchable_fields.length">
                                <div>
                                    <input type="checkbox" :value="table.table_name" x-model="selectedTables" :checked="selectAll">
                                </div>
                                <div x-text="table.table_name"></div>
                                <div x-text="table.searchable_fields"></div>
                                <div>
                                    <div x-show="table.isIndexed" x-text="'Indexed: ' + table.datasetSize + ' | Health: ' + table.health + ' | Docs: ' + table.docsCount"></div>
                                </div>

                                <div>
                                    <button type="button" class="btn btn-outline-danger" @click="delete_index(table.table_name)"><i class="fal fa-trash"></i></button>
                                    <button type="button" class="btn btn-outline-danger" @click="reset_index(table.table_name)"><i class="fal fa-broom"></i></button>
                                </div>
                            </div>
                        </template>
                    </div>




                    <div class="mb-3">
                        <input type="text" class="form-control" placeholder="Search" x-model.debounce="filter_term" />
                    </div>
                    
                    <div class="list-group">
                        <template x-for="(item, i) in results" :key="item.id">
                            <div class="list-group-item d-flex gap-1">
                                <span x-text="item.name"></span>
                            </div>
                        </template>
                    </div>

                       
               </div>
               
               <script>
                document.addEventListener("alpine:init", () => {
                    Alpine.data("algolia", () => ({
                       
                       filter_term: '',
                        results: [],
                        tables: [],
                        selectedTables: [],
                        selectAll: false,

                        init() {
                            this.load();
                            this.$watch('filter_term', () => this.find_content());
                        },
                        

                        async delete_index(table_name) {

                            // EXPORT DATA
                            this.results = await fetchData({
                                endpoint: 'delete_index',
                                method:"POST",
                                body:{
                                    table_name:table_name
                                }
                            });

                            this.load()
                        },

                        async reset_index(table_name) {

                            // EXPORT DATA
                            this.results = await fetchData({
                                endpoint: 'reset_index',
                                method:"POST",
                                body:{
                                    table_name:table_name
                                }
                            });

                            this.load()
                        },

                        async load() {
                            let data = await fetchData({
                                endpoint: 'load',
                                method: 'GET'
                            });

                            // Convert the 'searchable_tables' object to an array of its values
                            this.tables = Object.values(data.searchable_tables).map(table => {
                                let existingIndex = data.existing_in_es.find(index => index.index === table.table_name);
                                return {
                                    ...table,
                                    isIndexed: !!existingIndex,
                                    datasetSize: existingIndex ? existingIndex['dataset.size'] : null,
                                    health: existingIndex ? existingIndex.health : null,
                                    docsCount: existingIndex ? existingIndex['docs.count'] : null
                                };
                            });

                            this.existing_in_es = data.existing_in_es;
                        },


                        get enhancedTables() {
                            return this.tables.map(table => {
                                let existingIndex = this.existing_in_es.find(index => index.index === table.table_name);
                                return {
                                    ...table,
                                    isIndexed: !!existingIndex,
                                    datasetSize: existingIndex ? existingIndex['dataset.size'] : null
                                };
                            });
                        },

                        selectAllTables(isChecked) {
                            this.selectAll = isChecked;
                            if(isChecked) {
                                this.selectedTables = this.tables.map(table => table.table_name);
                            } else {
                                this.selectedTables = [];
                            }
                        },

                        async index_content() {

                            // EXPORT DATA
                            data = await fetchData({
                                endpoint: 'index_content',
                                method: 'POST',
                                body: {
                                    selectedTables : this.selectedTables
                                }
                            });


                            this.load()


                        },
                        

                        async find_content() {

                            // EXPORT DATA
                            this.results = await fetchData({
                                endpoint: 'find_content',
                                method:"POST",
                                body:{
                                    filter_term:this.filter_term
                                }
                            });
                        },
                    }))
                })
               </script>
        </cf_layout_default>
    </cffunction>


</cfcomponent>