<cfcomponent key="6220e84e-4e5e-4893-90cf-51d33ec6640e" open_to="security">

    <cffunction name="get">

        <cfset statements = application.lib.schemaSync.compareDatabaseSchema(application.lib.db.codeSchema) />

        <cfmodule template="/moopa/tags/moopa_layout.cfm" title="Schema">
            <div x-data="coapi" x-cloak class="page">

                <div class="page-header">
                    <div>
                        <div class="eyebrow" x-text="statementSummary()"></div>
                        <h1>Schema</h1>
                        <p class="page-lede">The database changes Moopa's table definitions call for. Select statements to review or copy them; Moopa never applies them itself.</p>
                    </div>
                    <div class="page-actions">
                        <!--- Re-initialising is for sysadmins only (application.cfc _reinitAllowed) --->
                        <cfif application.lib.auth.isSysAdmin()>
                            <button type="button" class="btn btn-sm" @click="reinit()"><i class="fa-solid fa-rotate-right"></i> Re-initialise</button>
                        </cfif>
                    </div>
                </div>

                <div class="card">
                    <div class="card-header">
                        <div class="cluster">
                            <div class="input-icon" style="width: 18rem; max-width: 100%">
                                <i class="fa-solid fa-magnifying-glass"></i>
                                <input class="input input-sm" type="search" aria-label="Search schema statements" x-model.debounce.250ms="filter.statement" placeholder="Search statements" />
                            </div>
                            <select class="select select-sm" style="width: 13rem" aria-label="Filter statements by table" x-model="filter.table">
                                <option value="">All tables</option>
                                <template x-for="table in getUniqueTables()" :key="table">
                                    <option :value="table" x-text="table"></option>
                                </template>
                            </select>
                            <button type="button" class="btn btn-ghost btn-sm" @click="resetFilters" :disabled="!hasActiveFilters()">Reset</button>
                        </div>
                        <div class="cluster">
                            <button type="button" class="btn btn-sm" @click="openSqlDrawer()" :disabled="selectedCount === 0"><i class="fa-solid fa-code"></i> Show SQL</button>
                            <button type="button" class="btn btn-primary btn-sm" @click="copyToClipboard" :disabled="selectedCount === 0"><i class="fa-solid fa-copy"></i> Copy SQL</button>
                        </div>
                    </div>

                    <div class="table-wrap" x-show="filteredCount > 0">
                        <table class="table table-sm table-hover table-clickable table-top">
                            <thead>
                                <tr>
                                    <th style="width: 2.5rem">
                                        <input type="checkbox" class="checkbox" aria-label="Toggle the statements shown"
                                            :checked="filteredCount > 0 && filteredSelectedCount === filteredCount"
                                            :disabled="filteredCount === 0"
                                            x-effect="$el.indeterminate = filteredSelectedCount > 0 && filteredSelectedCount < filteredCount"
                                            @change="toggleFilteredSelection()">
                                    </th>
                                    <th style="width: 5rem">Priority</th>
                                    <th style="width: 12rem">Table</th>
                                    <th>Statement</th>
                                </tr>
                            </thead>
                            <tbody>
                                <template x-for="(statement, i) in getFilteredStatements()" :key="statement.statement + '-' + i">
                                    <tr :class="{ 'is-selected': statement.selected }" tabindex="0"
                                        @click="statement.selected = !statement.selected"
                                        @keydown.enter.prevent="statement.selected = !statement.selected"
                                        @keydown.space.prevent="statement.selected = !statement.selected"
                                        :aria-label="`Toggle statement ${statement.title || statement.statement}`">
                                        <td><input type="checkbox" class="checkbox" style="pointer-events: none" x-model="statement.selected" tabindex="-1"></td>
                                        <td><span class="badge" x-text="statement.priority"></span></td>
                                        <td><span class="mono muted truncate" style="display: block" x-text="statement.table_name || 'unknown table'" :title="statement.table_name || 'unknown table'"></span></td>
                                        <td>
                                            <div class="stack stack-sm">
                                                <div class="cluster">
                                                    <span class="cell-main" x-text="statement.title"></span>
                                                    <template x-if="statement.mismatches && statement.mismatches.length > 0">
                                                        <button type="button" class="badge badge-warning" @click.stop="openMismatch = statement; $refs.mismatch.showModal()">
                                                            <span x-text="statement.mismatches.length"></span> diff
                                                        </button>
                                                    </template>
                                                </div>
                                                <code class="code-inline break" style="display: block; white-space: pre-wrap; padding: var(--sp-2) var(--sp-3)" x-text="statement.statement"></code>
                                            </div>
                                        </td>
                                    </tr>
                                </template>
                            </tbody>
                        </table>
                    </div>

                    <div class="empty" x-show="filteredCount === 0">
                        <i class="fa-solid" :class="hasActiveFilters() ? 'fa-filter-circle-xmark' : 'fa-circle-check'"></i>
                        <p class="strong secondary" x-text="hasActiveFilters() ? 'No statements match these filters.' : 'No pending schema statements.'"></p>
                        <p class="small" x-text="hasActiveFilters() ? 'Clear the filters, or search for a different table or statement.' : 'The database matches the table definitions.'"></p>
                    </div>

                    <div class="card-footer cluster cluster-between small muted" x-show="statements.length > 0">
                        <div class="cluster">
                            <span><strong class="secondary" x-text="selectedCount"></strong> selected</span>
                            <button type="button" class="btn btn-ghost btn-xs" @click="toggleFilteredSelection()" :disabled="filteredCount === 0" x-text="filteredSelectedCount === filteredCount && filteredCount > 0 ? 'Clear visible' : 'Select visible'"></button>
                        </div>
                        <span><strong class="secondary" x-text="filteredCount"></strong> of <strong class="secondary" x-text="statements.length"></strong></span>
                    </div>
                </div>

                <dialog class="modal modal-lg" x-ref="sql" aria-labelledby="selected-sql-title" @close="sqlDrawerOpen = false">
                    <div class="modal-header">
                        <div>
                            <div class="eyebrow">Selected SQL</div>
                            <h2 id="selected-sql-title" class="card-title">Review the generated script</h2>
                            <p class="card-sub"><span x-text="selectedCount"></span> statement<span x-show="selectedCount !== 1">s</span> selected.</p>
                        </div>
                        <button type="button" class="btn btn-ghost btn-icon btn-sm" @click="closeSqlDrawer()" aria-label="Close"><i class="fa-solid fa-xmark"></i></button>
                    </div>
                    <div class="modal-body">
                        <pre class="code-block" x-show="selectedCount > 0"><code x-text="selectedSql"></code></pre>
                        <p class="empty" x-show="selectedCount === 0">Select statements to build a script.</p>
                    </div>
                    <div class="modal-footer">
                        <button type="button" class="btn btn-sm" @click="closeSqlDrawer()">Close</button>
                        <button type="button" class="btn btn-primary btn-sm" @click="copyToClipboard" :disabled="selectedCount === 0"><i class="fa-solid fa-copy"></i> Copy SQL</button>
                    </div>
                </dialog>

                <dialog class="modal modal-lg" x-ref="mismatch" aria-labelledby="mismatch-title" @close="openMismatch = null">
                    <div class="modal-header">
                        <div>
                            <h2 id="mismatch-title" class="card-title" x-text="openMismatch ? openMismatch.title : ''"></h2>
                            <p class="card-sub mono" x-text="openMismatch ? openMismatch.table_name : ''"></p>
                        </div>
                        <button type="button" class="btn btn-ghost btn-icon btn-sm" @click="$refs.mismatch.close()" aria-label="Close"><i class="fa-solid fa-xmark"></i></button>
                    </div>
                    <div class="modal-body stack">
                        <template x-for="mismatch in (openMismatch?.mismatches || [])" :key="mismatch.param">
                            <section class="stack stack-sm">
                                <div class="strong" x-text="mismatch.param"></div>
                                <div class="auto-grid" style="--auto-min: 16rem">
                                    <div class="alert alert-danger" style="display: block">
                                        <div class="eyebrow text-danger">Database now</div>
                                        <pre class="mono break" style="margin: var(--sp-1) 0 0; white-space: pre-wrap" x-text="mismatch.db || '(empty)'"></pre>
                                    </div>
                                    <div class="alert alert-success" style="display: block">
                                        <div class="eyebrow text-success">Code expects</div>
                                        <pre class="mono break" style="margin: var(--sp-1) 0 0; white-space: pre-wrap" x-text="mismatch.code || '(empty)'"></pre>
                                    </div>
                                </div>
                            </section>
                        </template>
                    </div>
                </dialog>
            </div>

            <cfoutput>
            <script>
                document.addEventListener("alpine:init", () => {
                    Alpine.data("coapi", () => ({
                        statements: #serializeJson(statements)#,
                        openMismatch: null,
                        sqlDrawerOpen: false,
                        filter: {
                            table: "",
                            statement: ""
                        },

                        get filteredCount() {
                            return this.getFilteredStatements().length;
                        },

                        get selectedCount() {
                            return this.getSelectedStatements().length;
                        },

                        get filteredSelectedCount() {
                            return this.getFilteredStatements().filter((statement) => statement.selected === true).length;
                        },

                        get selectedSql() {
                            const selectedStatements = this.getSelectedStatements();
                            if (!selectedStatements.length) {
                                return "";
                            }
                            return selectedStatements.map((statement) => statement.statement).join(";\n") + ";";
                        },

                        getUniqueTables() {
                            const tables = [...new Set(this.statements.map((statement) => statement.table_name).filter(Boolean))];
                            return tables.sort();
                        },

                        getFilteredStatements() {
                            const statementFilter = this.filter.statement.toLowerCase().trim();

                            return this.statements.filter((statement) => {
                                const tableMatch = this.filter.table === "" || statement.table_name === this.filter.table;
                                const haystack = [statement.title, statement.table_name, statement.statement].join(" ").toLowerCase();
                                const statementMatch = statementFilter === "" || haystack.includes(statementFilter);

                                return tableMatch && statementMatch;
                            });
                        },

                        getSelectedStatements() {
                            return this.statements.filter((statement) => statement.selected === true);
                        },

                        hasActiveFilters() {
                            return Object.values(this.filter || {}).some((value) => `${value || ""}`.trim().length);
                        },

                        statementSummary() {
                            const total = this.statements.length;
                            if (!total) return "No statements";
                            if (total === 1) return "1 statement";
                            return `${total} statements`;
                        },

                        async reinit() {
                            await req({ url_params: { init: "1" }, body: {} });
                            window.location.reload();
                        },

                        resetFilters() {
                            this.filter.table = "";
                            this.filter.statement = "";
                        },

                        toggleFilteredSelection() {
                            const filteredStatements = this.getFilteredStatements();
                            const shouldSelect = this.filteredSelectedCount !== filteredStatements.length;

                            filteredStatements.forEach((statement) => {
                                statement.selected = shouldSelect;
                            });
                        },

                        openSqlDrawer() {
                            if (this.selectedCount === 0) return;
                            this.sqlDrawerOpen = true;
                            this.$refs.sql.showModal();
                        },

                        closeSqlDrawer() {
                            this.$refs.sql.close();
                        },

                        async copyToClipboard() {
                            if (!this.selectedSql.length) {
                                return;
                            }

                            await navigator.clipboard.writeText(this.selectedSql);

                            if (window.sonner) {
                                window.sonner.success("Selected SQL copied", {
                                    description: `${this.selectedCount} statement${this.selectedCount === 1 ? "" : "s"} copied to clipboard.`
                                });
                            }
                        }
                    }));
                });
            </script>
            </cfoutput>

        </cfmodule>

    </cffunction>

</cfcomponent>
