<cfcomponent key="6220e84e-4e5e-4893-90cf-51d33ec6640e">

    <cffunction name="get" output="true">

        <cfset statements = application.lib.db.compareDatabaseSchema(application.lib.db.codeSchema) />
        <cfset reinitUrl = (url.route ?: "/schema/") & "?init=" & randRange(1, 1000) />

        <cf_layout_default title="Schema">
            <div x-data="coapi" x-cloak class="flex flex-col gap-5">

                <!-- Header -->
                <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                    <div>
                        <div class="flex items-center gap-3">
                            <div class="flex h-11 w-11 items-center justify-center rounded-box bg-primary/10 text-primary">
                                <i class="hgi-stroke hgi-database text-xl"></i>
                            </div>
                            <div>
                                <h1 class="text-2xl font-semibold tracking-tight">Schema</h1>
                                <p class="text-sm text-base-content/60">Review database changes generated from Moopa table definitions.</p>
                            </div>
                        </div>
                    </div>

                    <cfoutput>
                        <a href="#encodeForHTMLAttribute(reinitUrl)#" class="btn btn-primary btn-sm gap-2">
                            <i class="hgi-stroke hgi-refresh-01"></i>
                            Re-init
                        </a>
                    </cfoutput>
                </div>

                <!-- Filters -->
                <div class="card card-border bg-base-100 shadow-sm w-full max-w-5xl">
                    <div class="card-body gap-4">
                        <div class="flex flex-col gap-4 xl:flex-row xl:items-end">
                            <fieldset class="fieldset w-full xl:max-w-xs">
                                <legend class="fieldset-legend">Table</legend>
                                <select class="select select-sm w-full" x-model="filter.table">
                                    <option value="">All tables</option>
                                    <template x-for="table in getUniqueTables()" :key="table">
                                        <option :value="table" x-text="table"></option>
                                    </template>
                                </select>
                            </fieldset>

                            <fieldset class="fieldset w-full xl:max-w-2xl xl:flex-1">
                                <legend class="fieldset-legend">Statement</legend>
                                <label class="input input-sm w-full">
                                    <i class="hgi-stroke hgi-search-01 text-base-content/40"></i>
                                    <input type="search" x-model.debounce.250ms="filter.statement" placeholder="Filter statements..." />
                                </label>
                            </fieldset>

                            <div class="flex flex-wrap gap-2">
                                <button type="button" class="btn btn-ghost btn-sm" @click="resetFilters">
                                    Reset filters
                                </button>

                            </div>
                        </div>
                    </div>
                </div>

                <div class="grid grid-cols-1 gap-5 xl:grid-cols-2">

                    <!-- Statements -->
                    <div class="card card-border bg-base-100 shadow-sm min-w-0">
                        <div class="card-body gap-4">
                            <div>
                                <h2 class="card-title text-lg">Pending statements</h2>
                                <p class="text-sm text-base-content/60">
                                    Showing <span class="font-medium text-base-content" x-text="filteredCount"></span>
                                    of <span class="font-medium text-base-content" x-text="statements.length"></span> statements.
                                </p>
                            </div>
                        </div>

                        <div class="overflow-x-auto">
                            <table class="table table-sm">
                                <thead>
                                    <tr>
                                        <th class="w-10">
                                            <input
                                                type="checkbox"
                                                class="checkbox checkbox-sm checkbox-primary"
                                                aria-label="Toggle filtered statements"
                                                :checked="filteredCount > 0 && filteredSelectedCount === filteredCount"
                                                :disabled="filteredCount === 0"
                                                x-effect="$el.indeterminate = filteredSelectedCount > 0 && filteredSelectedCount < filteredCount"
                                                @change="toggleFilteredSelection()"
                                            >
                                        </th>
                                        <th class="w-20">Priority</th>
                                        <th>Statement</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <template x-for="(statement, i) in getFilteredStatements()" :key="statement.statement + '-' + i">
                                        <tr
                                            class="hover:bg-base-200/60 align-top cursor-pointer select-none"
                                            @click="statement.selected = !statement.selected"
                                        >
                                            <td>
                                                <input type="checkbox" class="checkbox checkbox-sm checkbox-primary pointer-events-none" x-model="statement.selected" tabindex="-1">
                                            </td>
                                            <td>
                                                <span class="badge badge-ghost badge-sm" x-text="statement.priority"></span>
                                            </td>
                                            <td>
                                                <div class="flex flex-col gap-2">
                                                    <div class="flex flex-wrap items-center gap-2">
                                                        <span class="font-medium" x-text="statement.title"></span>
                                                        <span class="badge badge-ghost badge-sm" x-text="statement.table_name || 'unknown table'"></span>
                                                        <template x-if="statement.mismatches && statement.mismatches.length > 0">
                                                            <button type="button" class="badge badge-warning badge-sm gap-1" @click="openMismatch = statement">
                                                                <span x-text="statement.mismatches.length"></span>
                                                                diff
                                                            </button>
                                                        </template>
                                                    </div>
                                                    <code class="block whitespace-pre-wrap break-words rounded-box bg-base-200/70 px-3 py-2 text-xs leading-relaxed" x-text="statement.statement"></code>
                                                </div>
                                            </td>
                                        </tr>
                                    </template>
                                </tbody>
                            </table>

                            <template x-if="filteredCount === 0">
                                <div class="flex flex-col items-center justify-center gap-3 px-6 py-16 text-center">
                                    <div class="flex h-12 w-12 items-center justify-center rounded-full bg-base-200 text-base-content/50">
                                        <i class="hgi-stroke hgi-filter-remove text-xl"></i>
                                    </div>
                                    <div>
                                        <h3 class="font-semibold">No statements match your filters</h3>
                                        <p class="text-sm text-base-content/60">Clear the filters to see all generated schema statements.</p>
                                    </div>
                                    <button type="button" class="btn btn-sm" @click="resetFilters">Reset filters</button>
                                </div>
                            </template>
                        </div>
                    </div>

                    <!-- Selected statements -->
                    <div class="card card-border bg-base-100 shadow-sm xl:sticky xl:top-6 xl:self-start">
                        <div class="card-body gap-4">
                            <div class="flex items-start justify-between gap-3">
                                <div>
                                    <h2 class="card-title text-lg">Selected SQL</h2>
                                    <p class="text-sm text-base-content/60">
                                        <span x-text="selectedCount"></span> statement<span x-show="selectedCount !== 1">s</span> selected.
                                    </p>
                                </div>
                                <button type="button" class="btn btn-success btn-sm gap-2" @click="copyToClipboard" :disabled="selectedCount === 0">
                                    <i class="hgi-stroke hgi-copy-01"></i>
                                    Copy
                                </button>
                            </div>

                            <template x-if="selectedCount === 0">
                                <div class="rounded-box border border-dashed border-base-300 bg-base-200/40 p-8 text-center text-sm text-base-content/60">
                                    Select statements from the table to build an executable SQL script.
                                </div>
                            </template>

                            <template x-if="selectedCount > 0">
                                <pre class="max-h-[60vh] overflow-auto rounded-box bg-neutral p-4 text-xs leading-relaxed text-neutral-content"><code x-text="selectedSql"></code></pre>
                            </template>
                        </div>
                    </div>
                </div>

                <!-- Mismatch modal -->
                <template x-teleport="body">
                    <div x-show="openMismatch" x-cloak
                        class="fixed inset-0 z-[200] flex items-center justify-center bg-black/50 p-4"
                        @click.self="openMismatch = null"
                        x-transition.opacity>
                        <div class="card w-full max-w-3xl bg-base-100 shadow-xl" @click.stop>
                            <div class="card-body gap-4">
                                <div class="flex items-start justify-between gap-4">
                                    <div>
                                        <h3 class="card-title" x-text="openMismatch ? openMismatch.title : ''"></h3>
                                        <p class="text-sm text-base-content/60" x-text="openMismatch ? openMismatch.table_name : ''"></p>
                                    </div>
                                    <button type="button" class="btn btn-ghost btn-sm btn-circle" @click="openMismatch = null" aria-label="Close">
                                        <i class="hgi-stroke hgi-cancel-01"></i>
                                    </button>
                                </div>

                                <template x-for="mismatch in (openMismatch?.mismatches || [])" :key="mismatch.param">
                                    <div class="rounded-box border border-base-300 p-4">
                                        <div class="mb-3 font-semibold text-sm" x-text="mismatch.param"></div>
                                        <div class="grid gap-3 md:grid-cols-2">
                                            <div class="rounded-box border border-error/20 bg-error/10 p-3">
                                                <div class="mb-2 text-[10px] font-semibold uppercase tracking-wide text-error">DB current</div>
                                                <pre class="whitespace-pre-wrap break-words font-mono text-xs text-error" x-text="mismatch.db || '(empty)'"></pre>
                                            </div>
                                            <div class="rounded-box border border-success/20 bg-success/10 p-3">
                                                <div class="mb-2 text-[10px] font-semibold uppercase tracking-wide text-success">Code expected</div>
                                                <pre class="whitespace-pre-wrap break-words font-mono text-xs text-success" x-text="mismatch.code || '(empty)'"></pre>
                                            </div>
                                        </div>
                                    </div>
                                </template>
                            </div>
                        </div>
                    </div>
                </template>
            </div>

            <cfoutput>
            <script>
                document.addEventListener("alpine:init", () => {
                    Alpine.data("coapi", () => ({
                        statements: #serializeJson(statements)#,
                        openMismatch: null,
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

                        async copyToClipboard() {
                            if (!this.selectedSql.length) {
                                return;
                            }

                            await navigator.clipboard.writeText(this.selectedSql);

                            if (window.sonner) {
                                window.sonner.success("Selected SQL copied", {
                                    description: `${this.selectedCount} statement${this.selectedCount === 1 ? "" : "s"} copied to clipboard.`,
                                    icon: "hgi-tick-02"
                                });
                            }
                        }
                    }));
                });
            </script>
            </cfoutput>

        </cf_layout_default>

    </cffunction>

</cfcomponent>
