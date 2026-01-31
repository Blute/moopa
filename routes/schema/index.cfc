<cfcomponent key="6220e84e-4e5e-4893-90cf-51d33ec6640e">
    <cffunction name="get" output="true">

<!---
<cfset dbSchema = application.lib.db.getSchemaFromDb("item_option,item_choice,item_group")>

<cfset sanitizedDbSchema = application.lib.db.sanitizeCodeSchema(dbSchema)>
<cfoutput><h1>Database Schema</h1><textarea>#serializeJSON(sanitizedDbSchema['item_option'])#</textarea></cfoutput>

 --->

<!---
<cfloop list="item_group,item_option,item_choice" item="table_name" index="i">
    <cfset dbSchema = application.lib.db.getSchemaFromDb(table_name)>

    <cfset jsonSchema[table_name] = dbSchema />

</cfloop>
<cfoutput><pre>#serializeJSON(jsonSchema)#</pre></cfoutput><cfabort> --->
<!---
<cfquery name="q">
<cfloop from="1" to="10000" index="i">
    INSERT INTO _test (title) VALUES ('/coapi/index.cfc?#i#');
</cfloop>
</cfquery> --->

<cf_layout_default container="container-fluid">

    <h1 class="text-xl font-semibold">
        Schema
        <a href="#url.route#?init=#randRange(1,1000)#" class="link link-primary text-sm ml-2">RE-INIT</a>
    </h1>

    <div class="divider"></div>

    <!--- <cfdump var="#sanitizedCodeSchema#" label="sanitizedCodeSchema" expand="false"> --->

    <cfset statements = application.lib.db.compareDatabaseSchema(application.lib.db.codeSchema) />
    <!--- <cfdump var="#statements#" label="statements" expand="false"> --->

        <div class="flex gap-4" x-data="coapi">
            <div class="w-64 shrink-0">
                <div class="card card-border bg-base-100">
                    <div class="card-body">
                        <label class="label">
                            <span class="label-text font-medium">Table</span>
                        </label>
                        <select class="select select-bordered select-sm w-full" x-model="filter.table">
                            <option value="">All Tables</option>
                            <template x-for="table in getUniqueTables()" :key="table">
                                <option :value="table" x-text="table"></option>
                            </template>
                        </select>

                        <label class="label mt-2">
                            <span class="label-text font-medium">Statement</span>
                        </label>
                        <input type="text" class="input input-bordered input-sm w-full" x-model.debounce="filter.statement" placeholder="Filter statements...">

                        <button type="button" class="btn btn-outline btn-info btn-sm mt-4" @click="filter.table = '';filter.statement = '';">Reset Filters</button>

                        <div class="text-xs text-base-content/60 mt-2">
                            Showing <span x-text="getFilteredStatements().length" class="font-semibold"></span> of <span x-text="statements.length" class="font-semibold"></span> statements
                        </div>
                    </div>
                </div>
            </div>

            <div class="flex-1">
                <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
                    <div class="card card-border bg-base-100">
                        <div class="card-body">
                            <div class="flex gap-2 mb-4">
                                <button type="button" class="btn btn-outline btn-primary btn-sm" @click="selectAll">Select All</button>
                                <button type="button" class="btn btn-outline btn-secondary btn-sm" @click="deselectAll">Deselect All</button>
                            </div>
                        </div>
                        <div class="overflow-x-auto">
                            <table class="table table-sm">
                                <thead>
                                <tr>
                                    <th>##</th>
                                    <th>Priority</th>
                                    <th>Title</th>
                                    <th>Statement</th>
                                </tr>
                                </thead>
                                <tbody>
                                    <template x-for="(statement, i) in getFilteredStatements">
                                        <tr x-id="['checkbox']" class="hover">
                                            <td>
                                                <input type="checkbox" class="checkbox checkbox-sm checkbox-primary" x-model="statement.selected" @click="toggleStatement(statement)">
                                            </td>
                                            <td x-text="statement.priority"></td>
                                            <td>
                                                <div class="flex items-center gap-2">
                                                    <span x-text="statement.title"></span>
                                                    <template x-if="statement.mismatches && statement.mismatches.length > 0">
                                                        <div class="dropdown dropdown-hover dropdown-right">
                                                            <div tabindex="0" class="badge badge-warning badge-xs cursor-pointer gap-1">
                                                                <span x-text="statement.mismatches.length"></span> diff
                                                            </div>
                                                            <div tabindex="0" class="dropdown-content z-50 p-3 shadow-lg bg-base-200 rounded-lg text-xs w-max max-w-md">
                                                                <div class="font-semibold text-warning mb-2">Mismatches:</div>
                                                                <template x-for="mismatch in statement.mismatches">
                                                                    <div class="mb-2 font-mono">
                                                                        <span class="font-semibold" x-text="mismatch.param"></span>:<br>
                                                                        <span class="text-error">db: <span x-text="mismatch.db || '(empty)'"></span></span><br>
                                                                        <span class="text-success">code: <span x-text="mismatch.code"></span></span>
                                                                    </div>
                                                                </template>
                                                            </div>
                                                        </div>
                                                    </template>
                                                </div>
                                            </td>
                                            <td x-text="statement.statement"></td>
                                        </tr>
                                    </template>
        <!---
                                    <cfloop array="#statements#" item="statement" index="i">
                                        <tr>
                                            <td><input type="checkbox" class="checkbox checkbox-sm" id="checkbox-#i#" @click="toggleStatement(#i#)" x-model="selectedStatements[#i - 1#]">

                                            </td>
                                            <td>#statements[i].title#</td>
                                            <td>#statements[i].statement#</td>
                                        </tr>
                                    </cfloop> --->
                                </tbody>
                            </table>
                        </div>
                    </div>
                    <div class="card card-border bg-base-100">
                        <div class="card-body">
                            <h2 class="card-title text-lg">Selected Statements</h2>

                            <div x-show="getSelectedStatements().length" class="my-3">
                                <button type="button" class="btn btn-success btn-sm" @click="copyToClipboard">Copy to Clipboard</button>
                            </div>

                            <template x-for="(statement, index) in getSelectedStatements">
                                <div class="text-sm font-mono">
                                    <span x-text="statement.statement"></span>;
                                </div>
                            </template>
                        </div>
                    </div>
                </div>
            </div>
        </div>



    <script>
        document.addEventListener("alpine:init", () => {


            Alpine.data("coapi", () => ({
                statements : #serializeJson(statements)#,
                filter:{
                    table:'',
                    statement:''
                },

                getUniqueTables() {
                    const tables = [...new Set(this.statements.map(s => s.table_name))];
                    return tables.sort();
                },

                getFilteredStatements() {
                    return this.statements.filter((statement) => {
                        const tableMatch = this.filter.table === '' || statement.table_name === this.filter.table;
                        const statementMatch = statement.statement.toLowerCase().includes(this.filter.statement.toLowerCase());

                        return tableMatch && statementMatch;
                    });
                },



                getSelectedStatements() {
                    return this.statements.filter((statement) => statement.selected === true || false);
                },

                toggleStatement(statement) {
                    statement.selected = !statement.selected ?? true;
                },


                selectAll() {
                    this.statements.forEach((statement) => {
                        statement.selected = false;
                    });
                    this.getFilteredStatements().forEach((statement) => {
                        statement.selected = true;
                    });
                },

                deselectAll() {
                    this.statements.forEach((statement) => {
                        statement.selected = false;
                    });
                },

                copyToClipboard: function() {
                    const selectedStatements = this.getSelectedStatements();
                    const textToCopy = selectedStatements.map((statement) => statement.statement).join(';\n');

                    navigator.clipboard.writeText(`${textToCopy};`)
                    .then(() => {
                        // console.log('Text copied to clipboard:', textToCopy);
                        // You can optionally show a success message or perform additional actions
                    })
                    .catch((error) => {
                        console.error('Failed to copy text to clipboard:', error);
                        // You can handle errors here or show an error message
                    });
                }
            }))
        })
    </script>

 </cf_layout_default>

</cffunction>
</cfcomponent>
