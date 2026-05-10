<cfif thisTag.executionMode EQ "start">

    <cfparam name="attributes.model" default="" />
    <cfparam name="attributes.class" default="" />
    <cfparam name="attributes.label" default="Upload Files" />
    <cfparam name="attributes.help_text" default="Drop files here or click to browse" />
    <cfparam name="attributes.show_file_list" default="true" hint="Whether to show the file list after upload. Set to false to hide completed files." />
    <cfparam name="attributes.upload_body_class" default="" />
    <cfparam name="attributes.route" default="" />
    <cfparam name="attributes.endpoint" default="" />
    <cfparam name="attributes.table_name" default="" />
    <cfparam name="attributes.field_name" default="" />
    <cfparam name="attributes.compact" default="false" hint="Use compact single-line dropzone style" />

    <!--- Build endpoint configuration --->
    <cfif !len(attributes.endpoint)>
        <cfset attributes.endpoint = "uploadFileToServerWithProgress.#listLast(attributes.model,'.')#" />
    </cfif>

    <cfif len(attributes.route)>
        <cfset signed_endpoint = application.lib.auth.signedEndpoint(route=attributes.route, endpoint=attributes.endpoint) />
        <cfset request_endpoint = "{#signed_endpoint#}" />
    <cfelse>
        <cfset request_endpoint = "{endpoint:'#attributes.endpoint#'}" />
    </cfif>

    <cfoutput>
        <div
            class="#attributes.class#"
            x-id="['input_file']"
            x-data="moopaFileUploadField({
                request_endpoint: #request_endpoint#,
                table_name: '#attributes.table_name#',
                field_name: '#attributes.field_name#',
                show_file_list: #lCase(attributes.show_file_list)#
            })"
            x-modelable="value"
            x-model="#attributes.model#"
        >
            <!--- Hidden textarea for x-model binding --->
            <textarea
                x-ref="hiddenValue"
                x-model="serializedValue"
                @input="handleModelUpdate"
                class="hidden"
            ></textarea>

            <!--- Dropzone using Tailwind/daisyUI --->
            <div
                class="card card-dash bg-base-200/50 cursor-pointer transition-all duration-200 hover:border-primary hover:bg-primary/5 mb-3<cfif attributes.compact> p-3<cfelse> p-6</cfif>"
                x-data="{ isDragging: false }"
                x-on:dragenter.prevent="isDragging = true"
                x-on:dragover.prevent="isDragging = true"
                x-on:dragleave.prevent="if (!$el.contains(event.relatedTarget)) isDragging = false"
                x-on:drop.prevent="isDragging = false; handleDrop($event)"
                :class="{ '!border-primary !border-solid !bg-primary/10 scale-[1.01] ring-4 ring-primary/20': isDragging }"
                x-show="shouldShowUploadArea"
                @click="$refs['file-input'].click()"
            >
                <input
                    type="file"
                    :id="$id('input_file')"
                    :multiple="isMultipleMode"
                    x-ref="file-input"
                    @change="handleFiles"
                    @click.stop
                    class="hidden"
                >

                <cfif attributes.compact>
                    <!--- Compact single-line style --->
                    <div class="flex items-center gap-3 pointer-events-none">
                        <div class="w-8 h-8 flex items-center justify-center bg-primary rounded-full text-primary-content text-sm shrink-0">
                            <i class="hgi-stroke hgi-cloud-upload"></i>
                        </div>
                        <span class="flex-1 text-sm text-base-content/70">#attributes.help_text#</span>
                        <span class="badge badge-primary badge-soft">Browse</span>
                    </div>
                <cfelse>
                    <!--- Full dropzone style --->
                    <div class="flex flex-col items-center gap-3 pointer-events-none">
                        <div class="w-14 h-14 flex items-center justify-center bg-gradient-to-br from-primary to-primary/80 rounded-full text-primary-content text-2xl shadow-lg shadow-primary/30 transition-transform group-hover:-translate-y-0.5">
                            <i class="hgi-stroke hgi-cloud-upload text-lg"></i>
                        </div>
                        <div class="text-center">
                            <span class="block font-medium text-base-content text-sm mb-1">#attributes.help_text#</span>
                            <span class="text-sm text-base-content/60">or <span class="text-primary font-medium underline underline-offset-2">browse files</span></span>
                        </div>
                    </div>
                </cfif>
            </div>

            <!--- File List using Tailwind/daisyUI --->
            <template x-if="combined_files?.length && (show_file_list || hasUploadingFiles())">
                <div class="flex flex-col gap-2">
                    <template x-for="(file, index) in combined_files" :key="file.id">
                        <div
                            class="flex items-center gap-3 p-2.5 bg-base-100 border border-base-300 rounded-lg transition-all duration-200 hover:border-primary hover:shadow-sm animate-in slide-in-from-top-2"
                            :class="{
                                'opacity-50 !bg-error/5 !border-error': file.is_trashed,
                                'border-l-4 !border-l-success': uploadProgress[file.id] === 100 && !processingFiles[file.id] && !file.is_trashed
                            }"
                            @mouseenter="activeIndex = index"
                            @mouseleave="activeIndex = null"
                        >
                            <!--- Thumbnail with progress indicator --->
                            <div class="relative shrink-0">
                                <button class="btn btn-ghost btn-sm p-0 w-11 h-11 rounded-lg overflow-hidden" @click.prevent="handleDocumentPreview(file.id)">
                                    <img :src="file.thumbnail" class="w-full h-full object-cover" :alt="file.name">
                                </button>

                                <!--- Circular progress indicator --->
                                <svg
                                    class="absolute -top-1 -left-1 w-[52px] h-[52px] -rotate-90 pointer-events-none"
                                    x-show="uploadProgress[file.id] !== undefined && uploadProgress[file.id] < 100 && !processingFiles[file.id]"
                                    viewBox="0 0 36 36"
                                >
                                    <circle
                                        class="stroke-base-300"
                                        cx="18" cy="18" r="16"
                                        fill="none"
                                        stroke-width="3"
                                    />
                                    <circle
                                        class="stroke-primary transition-all duration-300"
                                        cx="18" cy="18" r="16"
                                        fill="none"
                                        stroke-width="3"
                                        stroke-linecap="round"
                                        :stroke-dasharray="100.53"
                                        :stroke-dashoffset="100.53 - (uploadProgress[file.id] / 100) * 100.53"
                                    />
                                </svg>

                                <!--- Processing spinner --->
                                <div
                                    class="absolute inset-0 flex items-center justify-center bg-base-100/90 rounded-lg"
                                    x-show="processingFiles[file.id]"
                                >
                                    <span class="loading loading-spinner loading-sm text-primary"></span>
                                </div>

                                <!--- Complete checkmark --->
                                <div
                                    class="absolute -bottom-1 -right-1 w-5 h-5 flex items-center justify-center bg-success rounded-full text-success-content text-xs shadow-sm"
                                    x-show="uploadProgress[file.id] === 100 && !processingFiles[file.id] && !file.is_trashed"
                                    x-transition:enter="transition ease-out duration-300"
                                    x-transition:enter-start="opacity-0 scale-0"
                                    x-transition:enter-end="opacity-100 scale-100"
                                >
                                    <i class="hgi-stroke hgi-tick-02"></i>
                                </div>
                            </div>

                            <!--- File info --->
                            <div class="flex-1 min-w-0 flex flex-col gap-0.5">
                                <span class="text-sm font-medium text-base-content truncate" x-text="file.name" :title="file.name"></span>
                                <span class="text-xs text-base-content/60" x-text="formatFileSize(file.size)"></span>
                            </div>

                            <!--- Status badge --->
                            <div class="shrink-0">
                                <span
                                    class="badge badge-sm badge-info badge-soft"
                                    x-show="uploadProgress[file.id] < 100 && !processingFiles[file.id]"
                                    x-text="uploadProgress[file.id] + '%'"
                                ></span>
                                <span
                                    class="badge badge-sm badge-warning badge-soft animate-pulse"
                                    x-show="processingFiles[file.id]"
                                >
                                    Processing...
                                </span>
                            </div>

                            <!--- Actions --->
                            <div class="shrink-0 flex gap-1">
                                <button
                                    type="button"
                                    class="btn btn-ghost btn-sm btn-square opacity-40 hover:opacity-100 hover:btn-error"
                                    x-on:click.stop="removeFile(file.id)"
                                    x-show="!file.is_trashed"
                                    :class="{ '!opacity-100': activeIndex === index }"
                                    title="Remove file"
                                >
                                    <i class="hgi-stroke hgi-delete-02"></i>
                                </button>

                                <button
                                    type="button"
                                    class="btn btn-ghost btn-sm btn-square text-success hover:btn-success"
                                    x-on:click.stop="restoreFile(file.id)"
                                    x-show="file.is_trashed"
                                    title="Restore file"
                                >
                                    <i class="hgi-stroke hgi-undo-03"></i>
                                </button>
                            </div>
                        </div>
                    </template>
                </div>
            </template>
        </div>
    </cfoutput>

<cfelseif thisTag.executionMode EQ "end">
    <!--- not required --->
</cfif>
