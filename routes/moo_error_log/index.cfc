<cfcomponent key="0eb48c9f-d8a8-451b-8ad6-eb3fc0dffee7">


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





    <cffunction name="get" output="true">
        <cf_layout_default>


            <div x-data="error_log">

                <div class="bg-white rounded-lg border border-gray-200 overflow-hidden">
                    <div class="overflow-x-auto">
                        <table class="w-full text-sm">
                            <colgroup>
                                <col class="w-32">
                                <col class="">
                                <col class="">
                            </colgroup>
                            <thead class="bg-gray-50">
                            <tr>
                                <th class="px-4 py-3 text-left font-medium text-gray-700">date</th>
                                <th class="px-4 py-3 text-left font-medium text-gray-700">message</th>
                                <th class="px-4 py-3 text-left font-medium text-gray-700">line</th>
                            </tr >
                            </thead>
                            <tbody class="divide-y divide-gray-200">
                                <template x-for="(item, index) in records" :key="item.id">
                                    <tr @click="select(item)" role="button" class="hover:bg-gray-50 cursor-pointer select-none">

                                        <td class="px-4 py-3"><span x-text="formatLocalDate(item.created_at)"></span> <span x-text="formatToTheLocalMinute(item.created_at)"></span></td>
                                        <td class="px-4 py-3"><span x-text="item.message"></span></td>
                                        <td class="px-4 py-3"><span x-text="item.line"></span></td>


                                    </tr>
                                </template>
                            </tbody>
                        </table>
                    </div>
                </div>



                <!-- Edit Modal -->
                <el-dialog>
                    <dialog id="error-log-dialog" aria-labelledby="dialog-title" class="fixed inset-0 size-auto max-h-none max-w-none overflow-y-auto bg-transparent backdrop:bg-transparent">
                        <el-dialog-backdrop class="fixed inset-0 bg-gray-500/75 transition-opacity data-closed:opacity-0 data-enter:duration-300 data-enter:ease-out data-leave:duration-200 data-leave:ease-in"></el-dialog-backdrop>

                        <div tabindex="0" class="flex min-h-full items-end justify-center p-4 text-center focus:outline-none sm:items-center sm:p-0">
                            <el-dialog-panel class="relative transform overflow-hidden rounded-lg bg-white px-4 pt-5 pb-4 text-left shadow-xl transition-all data-closed:translate-y-4 data-closed:opacity-0 data-enter:duration-300 data-enter:ease-out data-leave:duration-200 data-leave:ease-in sm:my-8 sm:w-full sm:max-w-4xl sm:p-6 data-closed:sm:translate-y-0 data-closed:sm:scale-95">
                                <div>
                                    <div class="mb-4">
                                        <h3 id="dialog-title" class="text-base font-semibold text-gray-900">Error Log Details</h3>
                                    </div>

                                    <div class="space-y-4">
                                        <div>
                                            <label class="block text-sm font-medium text-gray-700 mb-1" for="message">message</label>
                                            <input type="text" class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500" placeholder="" x-model="current_record.message" id="message">
                                        </div>
                                        <div>
                                            <label class="block text-sm font-medium text-gray-700 mb-1" for="line">line</label>
                                            <div class="flex">
                                                <button class="px-4 py-2 border border-gray-300 rounded-l-lg hover:bg-gray-50 focus:ring-2 focus:ring-blue-500 focus:border-blue-500" type="button" id="button-addon2" @click="copyToClipboard">Copy</button>
                                                <input type="text" class="flex-1 px-3 py-2 border border-gray-300 rounded-r-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500" placeholder="" x-model="current_record.line" id="line">
                                            </div>
                                        </div>
                                        <div>
                                            <label class="block text-sm font-medium text-gray-700 mb-1" for="tag">tag</label>
                                            <input type="text" class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500" placeholder="" x-model="current_record.tag" id="tag">
                                        </div>

                                        <template x-if="current_record?.id">
                                            <div class="mt-6" x-data="{ activeTab: 'exception' }">
                                                <div class="border-b border-gray-200">
                                                    <nav class="-mb-px flex space-x-8">
                                                        <button @click="activeTab = 'exception'" :class="activeTab === 'exception' ? 'border-blue-500 text-blue-600' : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'" class="whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm">exception</button>
                                                        <button @click="activeTab = 'current_auth'" :class="activeTab === 'current_auth' ? 'border-blue-500 text-blue-600' : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'" class="whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm">current_auth</button>
                                                        <button @click="activeTab = 'cgi_scope'" :class="activeTab === 'cgi_scope' ? 'border-blue-500 text-blue-600' : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'" class="whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm">cgi_scope</button>
                                                        <button @click="activeTab = 'form_scope'" :class="activeTab === 'form_scope' ? 'border-blue-500 text-blue-600' : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'" class="whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm">form_scope</button>
                                                        <button @click="activeTab = 'request_scope'" :class="activeTab === 'request_scope' ? 'border-blue-500 text-blue-600' : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'" class="whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm">request_scope</button>
                                                        <button @click="activeTab = 'url_scope'" :class="activeTab === 'url_scope' ? 'border-blue-500 text-blue-600' : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'" class="whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm">url_scope</button>
                                                        <button @click="activeTab = 'session_scope'" :class="activeTab === 'session_scope' ? 'border-blue-500 text-blue-600' : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'" class="whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm">session_scope</button>
                                                    </nav>
                                                </div>
                                                <div class="mt-4">
                                                    <div x-show="activeTab === 'exception'" class="space-y-4">
                                                        <pre class="bg-gray-100 p-4 rounded-lg text-sm overflow-x-auto" x-text="formatJson(JSON.stringify(current_record.exception))"></pre>
                                                    </div>
                                                    <div x-show="activeTab === 'current_auth'" class="space-y-4">
                                                        <pre class="bg-gray-100 p-4 rounded-lg text-sm overflow-x-auto" x-text="formatJson(JSON.stringify(current_record.current_auth))"></pre>
                                                    </div>
                                                    <div x-show="activeTab === 'cgi_scope'" class="space-y-4">
                                                        <pre class="bg-gray-100 p-4 rounded-lg text-sm overflow-x-auto" x-text="formatJson(JSON.stringify(current_record.cgi_scope))"></pre>
                                                    </div>
                                                    <div x-show="activeTab === 'form_scope'" class="space-y-4">
                                                        <pre class="bg-gray-100 p-4 rounded-lg text-sm overflow-x-auto" x-text="formatJson(JSON.stringify(current_record.form_scope))"></pre>
                                                    </div>
                                                    <div x-show="activeTab === 'request_scope'" class="space-y-4">
                                                        <pre class="bg-gray-100 p-4 rounded-lg text-sm overflow-x-auto" x-text="formatJson(JSON.stringify(current_record.request_scope))"></pre>
                                                    </div>
                                                    <div x-show="activeTab === 'url_scope'" class="space-y-4">
                                                        <pre class="bg-gray-100 p-4 rounded-lg text-sm overflow-x-auto" x-text="formatJson(JSON.stringify(current_record.url_scope))"></pre>
                                                    </div>
                                                    <div x-show="activeTab === 'session_scope'" class="space-y-4">
                                                        <pre class="bg-gray-100 p-4 rounded-lg text-sm overflow-x-auto" x-text="formatJson(JSON.stringify(current_record.session_scope))"></pre>
                                                    </div>
                                                </div>
                                            </div>
                                        </template>
                                    </div>
                                </div>
                                <div class="mt-5 sm:mt-6">
                                    <button type="button" command="close" commandfor="error-log-dialog" class="inline-flex w-full justify-center rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-indigo-500 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600">Close</button>
                                </div>
                            </el-dialog-panel>
                        </div>
                    </dialog>
                </el-dialog>


            </div>

            <script>
                document.addEventListener("alpine:init", () => {
                    Alpine.data("error_log", () => ({

                        filters: {},
                        records: [],
                        current_record: {},


                        init()  {
                            this.resetFilter();
                            this.search();
                            this.$watch('filters', () => this.search());
                        },

                        async search() {
                            this.records = await fetchData({
                                endpoint: 'search',
                                body: {
                                    filter:this.filters
                                }
                            });
                        },

                        resetFilter() {
                            this.filters = {
                                term: '',
                            }
                        },


                        async select(item) {
                            // Load the record and show modal
                            this.current_record = await fetchData({
                                endpoint: 'read',
                                data: {id:item.id},
                            });
                            // Use Elements UI command to show modal
                            document.getElementById('error-log-dialog').showModal();
                        },


                        formatLocalDate(utcString) {
                            // Check if the timestamp is an empty string
                            if (!utcString) {
                                return '';
                            }

                            // This function should convert the UTC time to local time.
                            // Implement this function to suit your conversion logic.
                            const utcDate = new Date(utcString);
                            // Using 'en-US' locale to ensure AM/PM is included. Adjust the locale as needed.
                            return utcDate.toLocaleDateString('en-AU', {
                                                                            month: 'short',
                                                                            day: 'numeric',
                                                                            weekday: 'short' });
                        },
                        formatToTheLocalMinute(utcString) {
                            // This function should convert the UTC time to local time.
                            // Implement this function to suit your conversion logic.
                            const utcDate = new Date(utcString);
                            return utcDate.toLocaleTimeString('en-AU', { hour: '2-digit', minute: '2-digit', hour12: false });
                        },
                        copyToClipboard() {
                            navigator.clipboard.writeText(this.current_record.line).then(() => {

                                window.notyf.open({
                                    type:'default',
                                    message:'Text copied to clipboard!',
                                    duration:1000,
                                    ripple:false,
                                    dismissible:true,
                                    position: {
                                        x: 'right',
                                        y: 'top'
                                    }
                                });

                                // Optionally, show a success message or toast to the user
                            }).catch(err => {
                                console.error('Could not copy text: ', err);
                                // Optionally, show an error message or toast to the user
                            });
                        },

                        formatJson(jsonString) {
                            try {
                                const obj = JSON.parse(jsonString);
                                return JSON.stringify(obj, null, 2);
                            } catch (e) {
                                return jsonString;
                            }
                        }

                    }))
                })
            </script>

        </cf_layout_default>
    </cffunction>


</cfcomponent>
