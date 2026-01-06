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
        <cfset result.stats = application.lib.meilisearch.get_stats() />

        <cfreturn result />
    </cffunction>




    <cffunction name="get" output="true">
        <cf_layout_default content_class="w-full">

            <div x-data="meilisearch" x-cloak class="flex flex-col gap-6">
                <!-- Page Title -->
                <p class="text-lg font-medium">Meilisearch Management</p>

                <!-- Tables Card -->
                <div class="card card-border bg-base-100">
                    <div class="card-body p-0">
                        <!-- Toolbar -->
                        <div class="flex items-center justify-between px-5 pt-5">
                            <div class="inline-flex items-center gap-3">
                                <label class="flex items-center gap-2 cursor-pointer">
                                    <input type="checkbox" class="checkbox checkbox-sm" @click="selectAllTables($event.target.checked)" />
                                    <span class="text-sm">Select All</span>
                                </label>
                            </div>
                            <div class="inline-flex items-center gap-2">
                                <button class="btn btn-primary btn-sm" @click="index_content" :disabled="!selectedTables.length">
                                    <span class="fal fa-database"></span>
                                    Index Selected Tables
                                </button>
                            </div>
                        </div>

                        <!-- Table -->
                        <div class="mt-4 overflow-auto">
                            <table class="table">
                                <thead>
                                    <tr>
                                        <th class="w-12"></th>
                                        <th>Table Name</th>
                                        <th>Searchable Fields</th>
                                        <th>Index Status</th>
                                        <th class="text-end">Actions</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <template x-for="table in enhancedTables" :key="table.table_name">
                                        <tr class="hover:bg-base-200/40" x-show="table.searchable_fields.length">
                                            <!-- Checkbox -->
                                            <td>
                                                <input type="checkbox" class="checkbox checkbox-sm" :value="table.table_name" x-model="selectedTables" />
                                            </td>
                                            <!-- Table Name -->
                                            <td>
                                                <span class="font-mono text-sm" x-text="table.table_name"></span>
                                            </td>
                                            <!-- Searchable Fields -->
                                            <td>
                                                <span class="text-sm text-base-content/70" x-text="table.searchable_fields"></span>
                                            </td>
                                            <!-- Index Status -->
                                            <td>
                                                <template x-if="table.isIndexed">
                                                    <div class="flex flex-col gap-0.5">
                                                        <div class="flex items-center gap-2">
                                                            <span class="badge badge-sm badge-success">Indexed</span>
                                                            <template x-if="table.isIndexing">
                                                                <span class="loading loading-spinner loading-xs"></span>
                                                            </template>
                                                        </div>
                                                        <span class="text-xs text-base-content/60" x-text="table.numberOfDocuments.toLocaleString() + ' docs'"></span>
                                                    </div>
                                                </template>
                                                <template x-if="!table.isIndexed">
                                                    <span class="badge badge-sm badge-ghost">Not Indexed</span>
                                                </template>
                                            </td>
                                            <!-- Actions -->
                                            <td>
                                                <div class="flex items-center justify-end gap-1">
                                                    <button type="button" class="btn btn-ghost btn-sm btn-square" @click="reset_index(table.table_name)" title="Reset Index">
                                                        <span class="fal fa-sync text-base-content/70"></span>
                                                    </button>
                                                    <button type="button" class="btn btn-ghost btn-sm btn-square" @click="delete_index(table.table_name)" title="Delete Index">
                                                        <span class="fal fa-trash text-error"></span>
                                                    </button>
                                                </div>
                                            </td>
                                        </tr>
                                    </template>
                                    <!-- Empty State -->
                                    <template x-if="!enhancedTables.length">
                                        <tr>
                                            <td colspan="5" class="text-center py-8 text-base-content/60">
                                                <span class="fal fa-database fa-2x mb-2 block"></span>
                                                No searchable tables found
                                            </td>
                                        </tr>
                                    </template>
                                </tbody>
                            </table>
                        </div>
                    </div>
                </div>

            </div>

            <script>
                document.addEventListener('alpine:init', () => {
                    Alpine.data('meilisearch', () => ({

                        tables: [],
                        selectedTables: [],
                        selectAll: false,
                        existing_in_es: [],
                        indexStats: {},

                        async init() {
                            await this.load();
                        },


                        async delete_index(table_name) {
                            await req({
                                endpoint: 'delete_index',
                                body: { table_name }
                            });
                            await this.load();
                        },

                        async reset_index(table_name) {
                            await req({
                                endpoint: 'reset_index',
                                body: { table_name }
                            });
                            await this.load();
                        },

                        async load() {
                            const data = await req({ endpoint: 'load' });

                            // Stats are keyed by index name: data.stats.indexes[table_name]
                            const indexStats = data.stats?.indexes || {};

                            // Convert the 'searchable_tables' object to an array of its values
                            this.tables = Object.values(data.searchable_tables).map(table => {
                                const existingIndex = data.existing_in_es.find(idx => idx.uid === table.table_name);
                                const stats = indexStats[table.table_name];
                                return {
                                    ...table,
                                    isIndexed: !!existingIndex,
                                    numberOfDocuments: stats?.numberOfDocuments ?? 0,
                                    isIndexing: stats?.isIndexing ?? false,
                                    createdAt: existingIndex?.createdAt
                                };
                            });

                            this.existing_in_es = data.existing_in_es;
                            this.indexStats = indexStats;
                        },


                        get enhancedTables() {
                            return this.tables;
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
                            await req({
                                endpoint: 'index_content',
                                body: { selectedTables: this.selectedTables }
                            });
                            await this.load();
                        },
                    }))
                })
               </script>
        </cf_layout_default>
    </cffunction>


</cfcomponent>
