<cfcomponent key="6220e84e-4e5e-4893-90cf-51d33ec6640e">

    <cffunction name="get">

        <cfset statements = application.lib.db.compareDatabaseSchema(application.lib.db.codeSchema) />
        <cfset reinitUrl = (url.route ?: "/schema/") & "?init=" & randRange(1, 1000) />

        <cf_layout_default title="Schema">
            <div x-data="coapi" x-cloak class="flex flex-col gap-4 lg:gap-5">

                <!-- Header -->
                <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                    <div class="min-w-0">
                        <div class="flex items-center gap-3">
                            <div class="flex h-9 w-9 shrink-0 items-center justify-center rounded-box border border-base-300 bg-base-100 text-primary">
                                <i class="hgi-stroke hgi-database text-base"></i>
                            </div>
                            <div class="min-w-0">
                                <div class="flex flex-wrap items-baseline gap-x-2.5 gap-y-1">
                                    <h1 class="text-[1.625rem] font-semibold leading-none tracking-[-0.03em]">Schema</h1>
                                    <span class="text-[0.6875rem] font-medium uppercase tracking-[0.11em] text-base-content/42" x-text="statementSummary()"></span>
                                </div>
                                <p class="mt-1 max-w-[58ch] text-sm leading-5 text-base-content/62">Review database changes generated from Moopa table definitions.</p>
                            </div>
                        </div>
                    </div>
                </div>

                <div class="grid grid-cols-1 gap-5">

                    <!-- Statements -->
                    <div class="min-w-0 overflow-hidden rounded-lg border border-base-300 bg-base-100">
                        <div class="border-b border-base-300 px-4 py-3">
                            <div class="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
                                <div class="flex min-w-0 flex-col gap-2 sm:flex-row sm:items-center">
                                    <label class="input input-sm w-full focus-within:outline-primary/55 focus-within:outline-offset-2 sm:w-72 lg:w-80">
                                        <i class="hgi-stroke hgi-search-01 text-base-content/40"></i>
                                        <input type="search" aria-label="Search schema statements" x-model.debounce.250ms="filter.statement" placeholder="Search statements" />
                                    </label>
                                    <select class="select select-sm w-full focus:outline-primary/55 focus:outline-offset-2 sm:w-52" aria-label="Filter statements by table" x-model="filter.table">
                                        <option value="">All tables</option>
                                        <template x-for="table in getUniqueTables()" :key="table">
                                            <option :value="table" x-text="table"></option>
                                        </template>
                                    </select>
                                    <button type="button" class="btn btn-ghost btn-sm justify-start" @click="resetFilters" :disabled="!hasActiveFilters()">
                                        Reset
                                    </button>
                                </div>
                                <div class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-end">
                                    <cfoutput>
                                        <a href="#encodeForHTMLAttribute(reinitUrl)#" class="btn btn-primary btn-sm gap-2">
                                            <i class="hgi-stroke hgi-refresh-01"></i>
                                            Re-init
                                        </a>
                                    </cfoutput>
                                    <button type="button" class="btn btn-ghost btn-sm gap-2" @click="openSqlDrawer()" :disabled="selectedCount === 0">
                                        <i class="hgi-stroke hgi-code"></i>
                                        Show SQL
                                    </button>
                                    <button type="button" class="btn btn-success btn-sm gap-2" @click="copyToClipboard" :disabled="selectedCount === 0">
                                        <i class="hgi-stroke hgi-copy-01"></i>
                                        Copy SQL
                                    </button>
                                </div>
                            </div>
                        </div>

                        <div class="overflow-x-auto">
                            <table class="table table-sm w-full">
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
                                        <th class="w-48">Table</th>
                                        <th>Statement</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <template x-for="(statement, i) in getFilteredStatements()" :key="statement.statement + '-' + i">
                                        <tr
                                            class="hover:bg-base-200/35 align-top cursor-pointer select-none outline-none focus-visible:bg-base-200/45 focus-visible:ring-2 focus-visible:ring-primary/45 focus-visible:ring-inset"
                                            role="button"
                                            tabindex="0"
                                            @click="statement.selected = !statement.selected"
                                            @keydown.enter.prevent="statement.selected = !statement.selected"
                                            @keydown.space.prevent="statement.selected = !statement.selected"
                                            :aria-label="`Toggle statement ${statement.title || statement.statement}`"
                                        >
                                            <td>
                                                <input type="checkbox" class="checkbox checkbox-sm checkbox-primary pointer-events-none" x-model="statement.selected" tabindex="-1">
                                            </td>
                                            <td>
                                                <span class="badge badge-ghost badge-sm" x-text="statement.priority"></span>
                                            </td>
                                            <td>
                                                <span class="block truncate font-mono text-xs text-base-content/70" x-text="statement.table_name || 'unknown table'" :title="statement.table_name || 'unknown table'"></span>
                                            </td>
                                            <td>
                                                <div class="flex flex-col gap-2">
                                                    <div class="flex flex-wrap items-center gap-2">
                                                        <span class="font-medium" x-text="statement.title"></span>
                                                        <template x-if="statement.mismatches && statement.mismatches.length > 0">
                                                            <button type="button" class="badge badge-warning badge-sm gap-1" @click.stop="openMismatch = statement">
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
                                    <i class="hgi-stroke hgi-filter-remove text-3xl text-base-content/35"></i>
                                    <div>
                                        <h3 class="font-semibold" x-text="hasActiveFilters() ? 'No statements match these filters.' : 'No pending schema statements.'"></h3>
                                        <p class="text-sm text-base-content/60" x-text="hasActiveFilters() ? 'Clear filters or search for a different table or statement.' : 'The database schema matches the code definitions.'"></p>
                                    </div>
                                    <button type="button" class="btn btn-sm" @click="resetFilters" x-show="hasActiveFilters()">Reset filters</button>
                                </div>
                            </template>
                        </div>

                        <div class="grid gap-3 border-t border-base-300 px-4 py-3 text-sm text-base-content/65 sm:grid-cols-3 sm:items-center" x-show="statements.length > 0">
                            <span class="sm:justify-self-start"><strong class="font-semibold text-base-content" x-text="selectedCount"></strong> selected</span>
                            <span class="text-center sm:justify-self-center">
                                Showing <strong class="font-semibold text-base-content" x-text="filteredCount"></strong>
                                of <strong class="font-semibold text-base-content" x-text="statements.length"></strong>
                                records
                            </span>
                            <button type="button" class="btn btn-ghost btn-sm sm:justify-self-end" @click="toggleFilteredSelection()" :disabled="filteredCount === 0" x-text="filteredSelectedCount === filteredCount && filteredCount > 0 ? 'Clear visible' : 'Select visible'"></button>
                        </div>
                    </div>

                </div>

                <!-- Selected SQL drawer -->
                <div class="fixed inset-0 z-[1000]" x-show="sqlDrawerOpen" x-cloak style="display: none;" @keydown.escape.window="closeSqlDrawer()">
                    <button type="button" class="absolute inset-0 bg-base-content/20" aria-label="Close selected SQL drawer" @click="closeSqlDrawer()"></button>
                    <aside class="absolute right-0 top-0 flex h-full w-full max-w-3xl flex-col border-l border-base-300 bg-base-100 shadow-2xl" role="dialog" aria-modal="true" aria-labelledby="selected-sql-drawer-title" tabindex="-1" x-ref="sqlDrawerPanel" x-trap.noscroll="sqlDrawerOpen" x-show="sqlDrawerOpen" x-transition:enter="transition ease-out duration-200" x-transition:enter-start="translate-x-full" x-transition:enter-end="translate-x-0" x-transition:leave="transition ease-in duration-150" x-transition:leave-start="translate-x-0" x-transition:leave-end="translate-x-full">
                        <header class="flex items-start justify-between gap-4 border-b border-base-300 px-6 py-5">
                            <div class="min-w-0">
                                <p class="text-[0.6875rem] font-medium uppercase tracking-[0.12em] text-base-content/45">Selected SQL</p>
                                <h2 id="selected-sql-drawer-title" class="mt-1 text-xl font-semibold leading-tight tracking-[-0.026em]">Review generated script</h2>
                                <p class="mt-1 text-sm leading-5 text-base-content/62">
                                    <span x-text="selectedCount"></span> statement<span x-show="selectedCount !== 1">s</span> selected.
                                </p>
                            </div>
                            <button type="button" class="btn btn-ghost btn-sm btn-circle" @click="closeSqlDrawer()" aria-label="Close selected SQL drawer">
                                <i class="hgi-stroke hgi-cancel-01"></i>
                            </button>
                        </header>
                        <div class="flex-1 overflow-y-auto px-6 py-5">
                            <template x-if="selectedCount === 0">
                                <div class="rounded-lg border border-dashed border-base-300 px-4 py-8 text-center text-sm text-base-content/60">
                                    Select statements from the ledger to build an executable SQL script.
                                </div>
                            </template>
                            <template x-if="selectedCount > 0">
                                <pre class="min-h-full overflow-auto rounded-lg bg-neutral p-4 text-xs leading-relaxed text-neutral-content"><code x-text="selectedSql"></code></pre>
                            </template>
                        </div>
                        <footer class="flex justify-end gap-2 border-t border-base-300 bg-base-100/95 px-6 py-4 shadow-[0_-8px_24px_oklch(19.5%_0.02_41_/_0.06)]">
                            <button type="button" class="btn btn-ghost btn-sm" @click="closeSqlDrawer()">Close</button>
                            <button type="button" class="btn btn-success btn-sm gap-2" @click="copyToClipboard" :disabled="selectedCount === 0">
                                <i class="hgi-stroke hgi-copy-01"></i>
                                Copy SQL
                            </button>
                        </footer>
                    </aside>
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
                                    <button type="button" class="btn btn-ghost btn-sm btn-circle" @click.stop="openMismatch = null" aria-label="Close">
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
                            this.$nextTick(() => this.$refs.sqlDrawerPanel?.focus());
                        },

                        closeSqlDrawer() {
                            this.sqlDrawerOpen = false;
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
