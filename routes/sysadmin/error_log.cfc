<cfcomponent key="0eb48c9f-d8a8-451b-8ad6-eb3fc0dffee7" open_to="security">


    <cffunction name="read">
        <cfreturn application.lib.db.read(table_name='moo_error_log', id="#request.data.id#") />
    </cffunction>


    <cffunction name="search">
        <cfreturn application.lib.db.search(table_name='moo_error_log', q="#url.q?:''#", field_list="id,message,line,created_at") />
    </cffunction>


    <cffunction name="save">
        <cfreturn application.lib.db.save(
            table_name = "moo_error_log",
            data = request.data
        ) />
    </cffunction>

    <cffunction name="delete">
        <cfargument name="id" />
        <cfreturn application.lib.db.delete(table_name="moo_error_log", id="#arguments.id#") />
    </cffunction>





    <cffunction name="get">
        <cf_layout_default>

            <div x-data="error_log" x-cloak class="flex flex-col gap-4 lg:gap-5">
                <!-- Header -->
                <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                    <div class="min-w-0">
                        <div class="flex items-center gap-3">
                            <div class="flex h-9 w-9 shrink-0 items-center justify-center rounded-box border border-base-300 bg-base-100 text-primary">
                                <i class="hgi-stroke hgi-alert-02 text-base"></i>
                            </div>
                            <div class="min-w-0">
                                <div class="flex flex-wrap items-baseline gap-x-2.5 gap-y-1">
                                    <h1 class="text-[1.625rem] font-semibold leading-none tracking-[-0.03em]">Error Log</h1>
                                    <span class="text-[0.6875rem] font-medium uppercase tracking-[0.11em] text-base-content/42" x-text="errorSummary()"></span>
                                </div>
                                <p class="mt-1 max-w-[58ch] text-sm leading-5 text-base-content/62">Review captured application errors and inspect request context.</p>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- Results -->
                <div class="overflow-hidden rounded-lg border border-base-300 bg-base-100 md:flex md:max-h-[calc(100vh-9rem)] md:flex-col">
                    <div class="border-b border-base-300 px-4 py-3">
                        <div class="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
                            <div class="flex min-w-0 flex-col gap-2 sm:flex-row sm:items-center">
                                <label class="input input-sm w-full focus-within:outline-primary/55 focus-within:outline-offset-2 sm:w-72 lg:w-80">
                                    <i class="hgi-stroke hgi-search-01 text-base-content/40"></i>
                                    <input type="search" aria-label="Search error log" placeholder="Search messages or lines" x-model="filters.term" @input.debounce.300ms="search()" />
                                </label>
                                <button type="button" class="btn btn-ghost btn-sm justify-start" @click="resetFilter(); search();" :disabled="!hasActiveFilters()">
                                    Reset
                                </button>
                            </div>
                        </div>
                    </div>

                    <div class="hidden overflow-auto md:block md:min-h-0 md:flex-1">
                        <table class="table table-sm table-fixed w-full">
                            <thead>
                                <tr class="border-base-300 text-[0.8125rem] text-base-content/58">
                                    <th class="w-36 font-medium">Date</th>
                                    <th class="w-[52%] font-medium">Message</th>
                                    <th class="w-[36%] font-medium">Line</th>
                                </tr>
                            </thead>
                            <tbody>
                                <template x-for="item in records" :key="item.id">
                                    <tr class="border-base-200 hover:bg-base-200/35 cursor-pointer outline-none focus-visible:bg-base-200/45 focus-visible:ring-2 focus-visible:ring-primary/45 focus-visible:ring-inset" role="button" tabindex="0" @click="select(item)" @keydown.enter.prevent="select(item)" @keydown.space.prevent="select(item)" :aria-label="`Inspect error ${item.message || 'error'}`">
                                        <td><span class="block truncate font-mono text-xs text-base-content/70" x-text="formatDateTime(item.created_at)"></span></td>
                                        <td><span class="block truncate font-medium tracking-[-0.01em]" x-text="item.message || '—'" :title="item.message || '—'"></span></td>
                                        <td><span class="block truncate font-mono text-xs text-base-content/65" x-text="item.line || '—'" :title="item.line || '—'"></span></td>
                                    </tr>
                                </template>
                            </tbody>
                        </table>
                    </div>

                    <div class="divide-y divide-base-300 md:hidden">
                        <template x-for="item in records" :key="item.id">
                            <article class="p-4 cursor-pointer outline-none transition-colors hover:bg-base-200/35 focus-visible:bg-base-200/45 focus-visible:ring-2 focus-visible:ring-primary/45 focus-visible:ring-inset" role="button" tabindex="0" @click="select(item)" @keydown.enter.prevent="select(item)" @keydown.space.prevent="select(item)" :aria-label="`Inspect error ${item.message || 'error'}`">
                                <p class="text-xs font-mono text-base-content/55" x-text="formatDateTime(item.created_at)"></p>
                                <h3 class="mt-1 font-medium leading-tight tracking-[-0.01em]" x-text="item.message || '—'"></h3>
                                <p class="mt-3 truncate font-mono text-xs text-base-content/65" x-text="item.line || '—'"></p>
                            </article>
                        </template>
                    </div>

                    <template x-if="records.length === 0">
                        <div class="px-6 py-12 text-center">
                            <div class="mx-auto flex max-w-md flex-col items-center gap-3 text-base-content/65">
                                <i class="hgi-stroke hgi-alert-02 text-3xl text-base-content/35"></i>
                                <div>
                                    <p class="font-medium text-base-content" x-text="hasActiveFilters() ? 'No errors match these filters.' : 'No errors logged.'"></p>
                                    <p class="mt-1 text-sm" x-text="hasActiveFilters() ? 'Clear filters or search for a different message or line.' : 'Captured application errors will appear here.'"></p>
                                </div>
                                <button type="button" class="btn btn-sm" @click="resetFilter(); search();" x-show="hasActiveFilters()">Reset filters</button>
                            </div>
                        </div>
                    </template>

                    <div class="flex flex-col gap-2 border-t border-base-300 bg-base-100/95 px-4 py-1.5 text-[0.6875rem] leading-5 text-base-content/50 sm:flex-row sm:items-center sm:justify-between" x-show="records.length > 0">
                        <span x-text="latestSummary()"></span>
                        <span><strong class="font-semibold text-base-content" x-text="records.length"></strong> records</span>
                    </div>
                </div>

                <!-- Detail drawer -->
                <div class="fixed inset-0 z-[1000]" x-show="drawer_open" x-cloak style="display: none;" @keydown.escape.window="closeDrawer()">
                    <button type="button" class="absolute inset-0 bg-base-content/20" aria-label="Close error details" @click="closeDrawer()"></button>
                    <aside class="absolute right-0 top-0 flex h-full w-full max-w-3xl flex-col border-l border-base-300 bg-base-100 shadow-2xl" role="dialog" aria-modal="true" aria-labelledby="error-drawer-title" tabindex="-1" x-ref="drawerPanel" x-trap.noscroll="drawer_open" x-show="drawer_open" x-transition:enter="transition ease-out duration-200" x-transition:enter-start="translate-x-full" x-transition:enter-end="translate-x-0" x-transition:leave="transition ease-in duration-150" x-transition:leave-start="translate-x-0" x-transition:leave-end="translate-x-full">
                        <header class="flex items-start justify-between gap-4 border-b border-base-300 px-6 py-5">
                            <div class="min-w-0">
                                <p class="text-[0.6875rem] font-medium uppercase tracking-[0.12em] text-base-content/45" x-text="formatDateTime(current_record.created_at)"></p>
                                <h2 id="error-drawer-title" class="mt-1 text-xl font-semibold leading-tight tracking-[-0.026em]" x-text="current_record.message || 'Error details'"></h2>
                                <div class="mt-1 flex min-w-0 items-center gap-2">
                                    <p class="truncate font-mono text-xs text-base-content/62" x-text="current_record.line || 'No line captured.'"></p>
                                    <button type="button" class="btn btn-ghost btn-xs shrink-0" @click="copyToClipboard()" :disabled="!current_record.line">
                                        <i class="hgi-stroke hgi-copy-01"></i>
                                        Copy line
                                    </button>
                                </div>
                            </div>
                            <button type="button" class="btn btn-ghost btn-sm btn-circle shrink-0" @click="closeDrawer()" aria-label="Close error details">
                                <i class="hgi-stroke hgi-cancel-01"></i>
                            </button>
                        </header>

                        <div class="flex-1 overflow-y-auto px-6 py-5">
                            <div class="mb-4 flex flex-wrap gap-2">
                                <template x-for="tab in detailTabs" :key="tab.key">
                                    <button type="button" class="btn btn-sm" :class="activeTab === tab.key ? 'btn-primary' : 'btn-ghost'" @click="activeTab = tab.key" x-text="tab.label"></button>
                                </template>
                            </div>
                            <template x-for="tab in detailTabs" :key="tab.key">
                                <section x-show="activeTab === tab.key">
                                    <template x-if="tab.key === 'summary'">
                                        <div class="space-y-3">
                                            <div class="flex flex-col gap-3 rounded-lg border border-base-300 bg-base-200/35 px-4 py-3 text-sm leading-6 text-base-content/70 sm:flex-row sm:items-center sm:justify-between">
                                                <span>Markdown formatted for pasting into an LLM agent.</span>
                                                <button type="button" class="btn btn-primary btn-sm shrink-0" @click="copySummaryToClipboard()" :disabled="!hasCurrentRecord()">
                                                    <i class="hgi-stroke hgi-copy-01"></i>
                                                    Copy prompt
                                                </button>
                                            </div>
                                            <pre class="min-h-96 overflow-auto rounded-lg bg-neutral p-4 text-xs leading-relaxed text-neutral-content"><code x-text="errorSummaryMarkdown()"></code></pre>
                                        </div>
                                    </template>
                                    <template x-if="tab.key !== 'summary'">
                                        <pre class="min-h-96 overflow-auto rounded-lg bg-neutral p-4 text-xs leading-relaxed text-neutral-content"><code x-text="formatJsonValue(current_record[tab.key])"></code></pre>
                                    </template>
                                </section>
                            </template>
                        </div>

                    </aside>
                </div>
            </div>

            <script>
                document.addEventListener("alpine:init", () => {
                    Alpine.data("error_log", () => ({
                        filters: { term: '' },
                        records: [],
                        current_record: {},
                        drawer_open: false,
                        activeTab: 'summary',
                        detailTabs: [
                            { key: 'summary', label: 'Prompt' },
                            { key: 'exception', label: 'Exception' },
                            { key: 'current_auth', label: 'Auth' },
                            { key: 'cgi_scope', label: 'CGI' },
                            { key: 'form_scope', label: 'Form' },
                            { key: 'request_scope', label: 'Request' },
                            { key: 'url_scope', label: 'URL' },
                            { key: 'session_scope', label: 'Session' }
                        ],

                        init() {
                            this.search();
                        },

                        async search() {
                            this.records = await req({
                                endpoint: 'search',
                                q: this.filters.term
                            });
                        },

                        resetFilter() {
                            this.filters = { term: '' };
                        },

                        hasActiveFilters() {
                            return Object.values(this.filters || {}).some(value => `${value || ''}`.trim().length);
                        },

                        errorSummary() {
                            const total = this.records.length || 0;
                            if (!total) return 'No errors';
                            if (total === 1) return '1 error';
                            return `${total} errors`;
                        },

                        latestSummary() {
                            if (!this.records.length) return '';
                            return `Latest ${this.formatDateTime(this.records[0]?.created_at)}`;
                        },

                        async select(item) {
                            this.current_record = await req({
                                endpoint: 'read',
                                body: { id: item.id }
                            });
                            this.activeTab = 'summary';
                            this.drawer_open = true;
                            this.$nextTick(() => this.$refs.drawerPanel?.focus());
                        },

                        closeDrawer() {
                            this.drawer_open = false;
                        },

                        hasCurrentRecord() {
                            return !!(this.current_record && Object.keys(this.current_record).length);
                        },

                        parseJsonValue(value) {
                            let parsed = value;

                            for (let index = 0; index < 3; index++) {
                                if (typeof parsed !== 'string') break;

                                const trimmed = parsed.trim();
                                if (!trimmed) return '';

                                try {
                                    parsed = JSON.parse(trimmed);
                                } catch (e) {
                                    break;
                                }
                            }

                            return parsed;
                        },

                        exceptionObject() {
                            const exception = this.parseJsonValue(this.current_record.exception);
                            if (!exception || typeof exception !== 'object' || Array.isArray(exception)) return {};
                            return exception;
                        },

                        getObjectValue(object, keys) {
                            if (!object || typeof object !== 'object') return '';

                            for (const key of keys) {
                                if (Object.prototype.hasOwnProperty.call(object, key)) {
                                    return object[key];
                                }
                            }

                            const normalisedKeys = keys.map(key => key.toLowerCase());
                            const matchingEntry = Object.entries(object).find(([key]) => normalisedKeys.includes(key.toLowerCase()));
                            return matchingEntry ? matchingEntry[1] : '';
                        },

                        findObjectValue(object, keys, maxDepth = 4) {
                            const directValue = this.getObjectValue(object, keys);
                            if (directValue !== undefined && directValue !== null && directValue !== '') return directValue;
                            if (maxDepth <= 0 || !object || typeof object !== 'object') return '';

                            const values = Array.isArray(object) ? object : Object.values(object);
                            for (const value of values) {
                                if (!value || typeof value !== 'object') continue;
                                const foundValue = this.findObjectValue(value, keys, maxDepth - 1);
                                if (foundValue !== undefined && foundValue !== null && foundValue !== '') return foundValue;
                            }

                            return '';
                        },

                        cleanMarkdownText(value) {
                            if (value === undefined || value === null) return '';
                            if (typeof value === 'string') return value.replace(/\s+/g, ' ').trim();
                            if (typeof value === 'number' || typeof value === 'boolean') return String(value);
                            return JSON.stringify(value);
                        },

                        markdownInlineCode(value) {
                            const text = this.cleanMarkdownText(value) || '—';
                            return `\`${text.replace(/`/g, '\\`')}\``;
                        },

                        markdownFence(language, value) {
                            const text = value || '';
                            const fence = text.includes('```') ? '~~~~' : '```';
                            return `${fence}${language}\n${text}\n${fence}`;
                        },

                        exceptionType() {
                            const exception = this.exceptionObject();
                            return this.cleanMarkdownText(this.getObjectValue(exception, ['type']) || this.current_record.tag || 'Unknown');
                        },

                        exceptionMessage() {
                            const exception = this.exceptionObject();
                            return this.cleanMarkdownText(this.getObjectValue(exception, ['message']) || this.current_record.message || '—');
                        },

                        exceptionSql() {
                            const sql = this.findObjectValue(this.exceptionObject(), ['sql']);
                            if (sql === undefined || sql === null) return '';
                            if (typeof sql === 'string') return sql.trim();
                            if (typeof sql === 'number' || typeof sql === 'boolean') return String(sql);
                            return JSON.stringify(sql, null, 2);
                        },

                        compactSqlForSummary(sql) {
                            if (!sql) return '';

                            return String(sql)
                                .replace(/\r\n?/g, '\n')
                                .split('\n')
                                .map(line => line.replace(/[ \t]+$/g, ''))
                                .filter(line => line.trim().length)
                                .join('\n')
                                .trim();
                        },

                        exceptionTagContext() {
                            const tagContext = this.getObjectValue(this.exceptionObject(), ['tagContext']);
                            return Array.isArray(tagContext) ? tagContext : [];
                        },

                        isDatabaseException() {
                            return this.exceptionType().toLowerCase().includes('database') || !!this.exceptionSql();
                        },

                        errorSummaryMarkdown() {
                            if (!this.hasCurrentRecord()) return 'No error selected.';

                            const lines = [
                                `${String.fromCharCode(35)} Moopa error summary`,
                                '',
                                `- Type: ${this.markdownInlineCode(this.exceptionType())}`,
                                `- Message: ${this.exceptionMessage()}`
                            ];

                            if (this.isDatabaseException()) {
                                const sql = this.compactSqlForSummary(this.exceptionSql());
                                lines.push('', `${String.fromCharCode(35).repeat(2)} SQL`, '', sql ? this.markdownFence('sql', sql) : 'No SQL captured.');
                            }

                            const tagContextLines = this.exceptionTagContext().slice(0, 3).map((context, index) => {
                                const template = this.cleanMarkdownText(this.getObjectValue(context, ['template']) || 'Unknown template');
                                const line = this.cleanMarkdownText(this.getObjectValue(context, ['line']) || 'Unknown line');
                                return `${index + 1}. ${this.markdownInlineCode(`${template}:${line}`)}`;
                            });

                            lines.push('', `${String.fromCharCode(35).repeat(2)} Tag context`, '', tagContextLines.length ? tagContextLines.join('\n') : 'No tag context captured.');

                            return lines.join('\n');
                        },

                        formatDateTime(value) {
                            if (!value) return '';
                            const date = new Date(value);
                            if (Number.isNaN(date.getTime())) return '';
                            return `${date.toLocaleDateString('en-AU', { month: 'short', day: 'numeric', weekday: 'short' })} ${date.toLocaleTimeString('en-AU', { hour: '2-digit', minute: '2-digit', hour12: false })}`;
                        },

                        copyTextWithFallback(text) {
                            const textarea = document.createElement('textarea');
                            textarea.value = text;
                            textarea.setAttribute('readonly', '');
                            textarea.style.position = 'fixed';
                            textarea.style.left = '-9999px';
                            document.body.appendChild(textarea);
                            textarea.select();

                            try {
                                if (!document.execCommand('copy')) {
                                    throw new Error('Copy command was rejected.');
                                }
                            } finally {
                                document.body.removeChild(textarea);
                            }
                        },

                        async copyTextToClipboard(text, successMessage) {
                            if (!text) return;

                            try {
                                if (navigator.clipboard?.writeText) {
                                    await navigator.clipboard.writeText(text);
                                } else {
                                    this.copyTextWithFallback(text);
                                }

                                if (window.toast) {
                                    window.toast({ type: 'success', message: successMessage, duration: 1500 });
                                }
                            } catch (e) {
                                try {
                                    this.copyTextWithFallback(text);
                                    if (window.toast) {
                                        window.toast({ type: 'success', message: successMessage, duration: 1500 });
                                    }
                                } catch (fallbackError) {
                                    if (window.toast) {
                                        window.toast({ type: 'error', message: 'Could not copy to clipboard', duration: 3000 });
                                    }
                                }
                            }
                        },

                        copySummaryToClipboard() {
                            this.copyTextToClipboard(this.errorSummaryMarkdown(), 'Prompt copied');
                        },

                        copyToClipboard() {
                            this.copyTextToClipboard(this.current_record.line, 'Line copied');
                        },

                        formatJsonValue(value) {
                            const parsed = this.parseJsonValue(value);
                            if (parsed === undefined || parsed === null || parsed === '') return 'No data captured.';
                            if (typeof parsed === 'string') return parsed;
                            return JSON.stringify(parsed, null, 2);
                        }
                    }));
                });
            </script>

        </cf_layout_default>
    </cffunction>

</cfcomponent>
