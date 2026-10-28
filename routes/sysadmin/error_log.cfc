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
        <cfmodule template="/moopa/tags/moopa_layout.cfm" title="Error log">

            <div x-data="error_log" x-cloak class="page">
                <div class="page-header">
                    <div>
                        <div class="eyebrow" x-text="errorSummary()"></div>
                        <h1>Error log</h1>
                        <p class="page-lede">Captured application errors with their request context.</p>
                    </div>
                </div>

                <div class="card">
                    <div class="card-header">
                        <div class="cluster">
                            <div class="input-icon" style="width: 20rem; max-width: 100%">
                                <i class="fa-solid fa-magnifying-glass"></i>
                                <input class="input input-sm" type="search" aria-label="Search error log" placeholder="Search messages or lines" x-model="filters.term" @input.debounce.300ms="search()" />
                            </div>
                            <button type="button" class="btn btn-ghost btn-sm" @click="resetFilter(); search();" :disabled="!hasActiveFilters()">Reset</button>
                        </div>
                        <span class="muted small" x-text="latestSummary()"></span>
                    </div>

                    <div class="table-wrap" x-show="records.length > 0">
                        <table class="table table-sm table-hover table-clickable table-fixed">
                            <colgroup><col style="width: 10.5rem"><col><col style="width: 36%"></colgroup>
                            <thead><tr><th>Date</th><th>Message</th><th>Line</th></tr></thead>
                            <tbody>
                                <template x-for="item in records" :key="item.id">
                                    <tr tabindex="0" @click="select(item)" @keydown.enter.prevent="select(item)" :aria-label="`Inspect error ${item.message || 'error'}`">
                                        <td class="mono muted nowrap" x-text="formatDateTime(item.created_at)"></td>
                                        <td><span class="cell-main truncate" style="display: block" x-text="item.message || '—'" :title="item.message || '—'"></span></td>
                                        <td><span class="mono muted truncate" style="display: block" x-text="item.line || '—'" :title="item.line || '—'"></span></td>
                                    </tr>
                                </template>
                            </tbody>
                        </table>
                    </div>

                    <div class="empty" x-show="records.length === 0">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        <p class="strong secondary" x-text="hasActiveFilters() ? 'No errors match this search.' : 'No errors logged.'"></p>
                        <p class="small" x-text="hasActiveFilters() ? 'Clear the search, or try a different message or line.' : 'Captured application errors will appear here.'"></p>
                    </div>

                    <div class="card-footer cluster cluster-between small muted" x-show="records.length > 0">
                        <span x-text="latestSummary()"></span>
                        <span><strong class="secondary" x-text="records.length"></strong> records</span>
                    </div>
                </div>

                <dialog class="modal modal-xl" x-ref="detail" aria-labelledby="error-detail-title" @close="drawer_open = false">
                    <div class="modal-header">
                        <div>
                            <div class="eyebrow" x-text="formatDateTime(current_record.created_at)"></div>
                            <h2 id="error-detail-title" class="card-title" x-text="current_record.message || 'Error details'"></h2>
                            <div class="row">
                                <span class="mono muted truncate small" x-text="current_record.line || 'No line captured.'"></span>
                                <button type="button" class="btn btn-ghost btn-xs" @click="copyToClipboard()" :disabled="!current_record.line"><i class="fa-solid fa-copy"></i> Copy line</button>
                            </div>
                        </div>
                        <button type="button" class="btn btn-ghost btn-icon btn-sm" @click="closeDrawer()" aria-label="Close"><i class="fa-solid fa-xmark"></i></button>
                    </div>
                    <div class="modal-body stack">
                        <div class="tabs" role="tablist">
                            <template x-for="tab in detailTabs" :key="tab.key">
                                <button type="button" class="tab" role="tab" :aria-selected="activeTab === tab.key" @click="activeTab = tab.key" x-text="tab.label"></button>
                            </template>
                        </div>
                        <template x-for="tab in detailTabs" :key="tab.key">
                            <section x-show="activeTab === tab.key" class="stack stack-sm">
                                <template x-if="tab.key === 'summary'">
                                    <div class="cluster cluster-between">
                                        <span class="muted small">Markdown, ready to paste into an LLM agent.</span>
                                        <button type="button" class="btn btn-primary btn-sm" @click="copySummaryToClipboard()" :disabled="!hasCurrentRecord()"><i class="fa-solid fa-copy"></i> Copy prompt</button>
                                    </div>
                                </template>
                                <pre class="code-block" style="min-height: 20rem"><code x-text="tab.key === 'summary' ? errorSummaryMarkdown() : formatJsonValue(current_record[tab.key])"></code></pre>
                            </section>
                        </template>
                    </div>
                </dialog>
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
                            this.$refs.detail.showModal();
                        },

                        closeDrawer() {
                            this.$refs.detail.close();
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

        </cfmodule>
    </cffunction>

</cfcomponent>
