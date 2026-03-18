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
                            <i class="fal fa-cloud-arrow-up"></i>
                        </div>
                        <span class="flex-1 text-sm text-base-content/70">#attributes.help_text#</span>
                        <span class="badge badge-primary badge-soft">Browse</span>
                    </div>
                <cfelse>
                    <!--- Full dropzone style --->
                    <div class="flex flex-col items-center gap-3 pointer-events-none">
                        <div class="w-14 h-14 flex items-center justify-center bg-gradient-to-br from-primary to-primary/80 rounded-full text-primary-content text-2xl shadow-lg shadow-primary/30 transition-transform group-hover:-translate-y-0.5">
                            <i class="fal fa-cloud-arrow-up fa-lg"></i>
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
                                    <i class="fas fa-check"></i>
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
                                    <i class="fal fa-trash"></i>
                                </button>

                                <button
                                    type="button"
                                    class="btn btn-ghost btn-sm btn-square text-success hover:btn-success"
                                    x-on:click.stop="restoreFile(file.id)"
                                    x-show="file.is_trashed"
                                    title="Restore file"
                                >
                                    <i class="fal fa-undo"></i>
                                </button>
                            </div>
                        </div>
                    </template>
                </div>
            </template>
        </div>

        <cf_once id="moopa_file_upload_field_script" position="body">
            <script defer>
                document.addEventListener("alpine:init", () => {
                    Alpine.data("moopaFileUploadField", (config) => ({
                        value: null,
                        request_endpoint: config.request_endpoint,
                        table_name: config.table_name,
                        field_name: config.field_name,
                        show_file_list: config.show_file_list,

                        // File management
                        uploadProgress: {},
                        processingFiles: {},
                        trashed_files: [],
                        combined_files: [],
                        activeIndex: null,
                        uploadQueue: [],
                        fileUploadStatus: {},

                        // Temporary storage for pending files
                        pendingFiles: [],
                        pendingFileData: {},

                        // Serialized value for textarea binding
                        get serializedValue() {
                            return JSON.stringify(this.value);
                        },
                        set serializedValue(val) {
                            try {
                                this.value = JSON.parse(val);
                            } catch (e) {
                                // Invalid JSON, ignore
                            }
                        },

                        // Handle external model updates via textarea
                        handleModelUpdate() {
                            this.$dispatch('input', this.value);
                            this.$dispatch('update', { value: this.value });
                        },

                        // Determines if we're in multiple file mode based on the value type
                        get isMultipleMode() {
                            return Array.isArray(this.value);
                        },

                        get displayValue() {
                            return this.value || (this.isMultipleMode ? [] : null);
                        },

                        get parentId() {
                            // Extract parent ID from the parent scope if available
                            // This looks for common patterns like item.id or data.id in parent scope
                            try {
                                const parentData = this.$data;
                                if (parentData.item?.id) return parentData.item.id;
                                if (parentData.data?.id) return parentData.data.id;
                                if (parentData.id) return parentData.id;
                            } catch (e) {
                                // Ignore errors accessing parent scope
                            }
                            return null;
                        },

                        // Determines whether to show the upload area
                        get shouldShowUploadArea() {
                            // Always show for multiple file uploads
                            if (this.isMultipleMode) {
                                return true;
                            }

                            // For single file mode, check if we have an active file
                            const currentValue = this.displayValue;

                            // Show if no current value or empty object
                            if (!currentValue || Object.keys(currentValue).length === 0) {
                                return true;
                            }

                            // Also show if we only have pending files that aren't uploaded yet
                            if (this.pendingFiles.length > 0 && !this.hasCompletedFiles()) {
                                return true;
                            }

                            // Hide if there's an active file (uploaded or uploading)
                            return false;
                        },

                        // Update value and dispatch events
                        updateValue(newValue) {
                            this.value = newValue;
                            this.$nextTick(() => {
                                this.$dispatch('input', this.value);
                                this.$dispatch('update', { value: this.value });
                            });
                        },

                        // Determines if we're in single file mode
                        isSingleFile() {
                            return !this.isMultipleMode;
                        },

                        // Checks if there are any completed files
                        hasCompletedFiles() {
                            return this.pendingFiles.some(file =>
                                this.uploadProgress[file.id] === 100 && !this.processingFiles[file.id]
                            );
                        },

                        // Checks if there are any files currently uploading or processing
                        hasUploadingFiles() {
                            if (!this.combined_files?.length) return false;

                            return this.combined_files.some(file => {
                                const progress = this.uploadProgress[file.id];
                                const isProcessing = this.processingFiles[file.id];
                                return (progress !== undefined && progress < 100) || isProcessing;
                            });
                        },

                        // Updates the combined_files array for UI display
                        updateCombinedFiles() {
                            // Combine actual value, pending files, and trashed files for display
                            const currentValue = this.displayValue;
                            let files = [];

                            // Add files from the actual value
                            if (currentValue != null) {
                                if (Array.isArray(currentValue)) {
                                    files = files.concat(currentValue.map(file => ({
                                        ...file,
                                        is_trashed: false,
                                        is_pending: false
                                    })));
                                } else if (Object.keys(currentValue).length !== 0) {
                                    files.push({
                                        ...currentValue,
                                        is_trashed: false,
                                        is_pending: false
                                    });
                                }
                            }

                            // Add pending files that aren't in the actual value yet
                            const actualFileIds = files.map(f => f.id);
                            const pendingToShow = this.pendingFiles.filter(f => !actualFileIds.includes(f.id));
                            files = files.concat(pendingToShow.map(file => ({
                                ...file,
                                is_trashed: false,
                                is_pending: true
                            })));

                            // Add trashed files
                            files = files.concat(this.trashed_files.map(file => ({
                                ...file,
                                is_trashed: true,
                                is_pending: false
                            })));

                            this.combined_files = files;
                        },

                        // Determines the MIME type based on file extension
                        getContentType(fileName) {
                            const extension = fileName.split('.').pop().toLowerCase();
                            const mimeTypes = {
                                'pdf': 'application/pdf',
                                'png': 'image/png',
                                'jpg': 'image/jpeg',
                                'jpeg': 'image/jpeg',
                                'gif': 'image/gif',
                                'svg': 'image/svg+xml',
                                'txt': 'text/plain',
                                'html': 'text/html',
                                'css': 'text/css',
                                'js': 'application/javascript',
                                'json': 'application/json',
                                'xml': 'application/xml'
                            };

                            return mimeTypes[extension] || 'application/octet-stream';
                        },

                        // Handles file selection and initiates uploads
                        async handleFiles() {
                            const files = this.$refs['file-input'].files;
                            const currentValue = this.displayValue;

                            // If single file mode, only process the first file and replace existing
                            const filesToProcess = this.isSingleFile() ? [files[0]] : Array.from(files);

                            // If single file mode and we have an existing file, clear it first
                            if (this.isSingleFile() && currentValue && Object.keys(currentValue).length > 0) {
                                // Clear pending files and trashed files for single file mode
                                this.pendingFiles = [];
                                this.pendingFileData = {};
                                this.trashed_files = [];
                            }

                            for (let i = 0; i < filesToProcess.length; i++) {
                                const file = filesToProcess[i];

                                let req_params = {...this.request_endpoint};

                                req_params.data = {
                                    file_name: file.name,
                                    file_size: file.size,
                                    parent_table_name: this.table_name,
                                    parent_field: this.field_name,
                                    parent_id: this.parentId
                                };

                                req(req_params).then(res => {
                                    const file_data = res;

                                    // Store file data and add to pending files
                                    this.pendingFileData[file_data.file.id] = file_data;
                                    this.pendingFiles.push(file_data.file);

                                    // Add file to the upload queue and initialize status
                                    this.uploadQueue.push(file_data.file.id);
                                    this.fileUploadStatus[file_data.file.id] = false;

                                    this.uploadProgress[file_data.file.id] = 0;

                                    // Update combined files to show pending file
                                    this.updateCombinedFiles();

                                    // Start uploading the file
                                    this.uploadFileToServerWithProgress(file, file_data, file_data.file.id);
                                }).catch(error => {
                                    console.error('Error:', error);
                                });
                            }

                            // Clear the file input so the same file can be selected again
                            this.$refs['file-input'].value = '';
                        },

                        // Uploads a file to the server with progress tracking
                        uploadFileToServerWithProgress(file, file_data, fileId) {
                            try {
                                const route = file_data.presignedURL;
                                const xhr = new XMLHttpRequest();

                                this.$dispatch('file_uploading', {
                                    file: file_data.file
                                });

                                xhr.open('PUT', route, true);

                                const contentType = this.getContentType(file.name);
                                xhr.setRequestHeader('Content-Type', contentType);

                                xhr.upload.onprogress = (event) => {
                                    if (event.lengthComputable) {
                                        const progress = Math.round((event.loaded / event.total) * 99);
                                        this.uploadProgress[file_data.file.id] = progress;
                                    }
                                };

                                xhr.onload = async () => {
                                    if (xhr.status === 200) {
                                        this.uploadProgress[file_data.file.id] = 100;
                                        this.processingFiles[file_data.file.id] = true;

                                        let req_params = {...this.request_endpoint};
                                        req_params.data = {
                                            file_id: file_data.file.id
                                        };

                                        let res = await req(req_params);
                                        this.processingFiles[file_data.file.id] = false;

                                        // Update the file object with the new thumbnail and other updated data
                                        const updatedFile = res;
                                        const pendingIndex = this.pendingFiles.findIndex(f => f.id === fileId);
                                        if (pendingIndex !== -1) {
                                            this.pendingFiles[pendingIndex] = updatedFile;
                                        }

                                        this.$dispatch('file_uploaded', {
                                            file: updatedFile
                                        });

                                        this.fileUploadStatus[fileId] = true;
                                        this.checkAllUploadsComplete();
                                    } else {
                                        console.error('Error uploading file to server:', xhr.statusText);
                                        // Remove from pending if upload failed
                                        this.pendingFiles = this.pendingFiles.filter(f => f.id !== fileId);
                                        delete this.pendingFileData[fileId];
                                        this.updateCombinedFiles();
                                    }
                                };

                                xhr.onerror = () => {
                                    console.error('Upload error:', xhr.responseText);
                                    // Remove from pending if upload failed
                                    this.pendingFiles = this.pendingFiles.filter(f => f.id !== fileId);
                                    delete this.pendingFileData[fileId];
                                    this.updateCombinedFiles();
                                };

                                xhr.send(file);

                            } catch (error) {
                                console.error('Error uploading file to server:', error);
                            }
                        },

                        // Checks if all files in the queue have been uploaded and updates value
                        checkAllUploadsComplete() {
                            const allUploaded = this.uploadQueue.every(fileId => this.fileUploadStatus[fileId] === true);

                            if (allUploaded && this.uploadQueue.length > 0) {
                                // All files uploaded, now update the value with all pending files
                                const currentValue = this.displayValue;
                                let newValue;

                                if (this.isMultipleMode) {
                                    // For multiple mode, append all pending files
                                    const existingFiles = Array.isArray(currentValue) ? currentValue : [];
                                    newValue = [...existingFiles, ...this.pendingFiles];
                                } else {
                                    // For single mode, use the first (and only) pending file
                                    newValue = this.pendingFiles[0] || {};
                                }

                                // Update the value using the new method
                                this.updateValue(newValue);

                                // Clear pending files
                                this.pendingFiles = [];
                                this.pendingFileData = {};

                                this.$dispatch('all_files_uploaded', {
                                    files: newValue
                                });

                                this.uploadQueue = [];
                                this.fileUploadStatus = {};

                                // Update combined files after clearing pending
                                this.updateCombinedFiles();
                            }
                        },

                        // Removes a file from the value and moves it to trashed_files
                        removeFile(id) {
                            // Check if it's a pending file
                            const pendingIndex = this.pendingFiles.findIndex(file => file.id === id);
                            if (pendingIndex !== -1) {
                                // Remove from pending files
                                const removed = this.pendingFiles.splice(pendingIndex, 1)[0];
                                delete this.pendingFileData[id];

                                // Remove from upload queue if not yet uploaded
                                const queueIndex = this.uploadQueue.indexOf(id);
                                if (queueIndex !== -1 && !this.fileUploadStatus[id]) {
                                    this.uploadQueue.splice(queueIndex, 1);
                                    delete this.fileUploadStatus[id];
                                }

                                // Add to trashed files
                                this.trashed_files.push(removed);
                                this.updateCombinedFiles();
                                return;
                            }

                            // Otherwise, it's in the actual value
                            const currentValue = this.displayValue;

                            if (Array.isArray(currentValue)) {
                                const index = currentValue.findIndex(file => file.id === id);
                                if (index !== -1) {
                                    const removed = currentValue[index];
                                    const newValue = currentValue.filter((_, i) => i !== index);
                                    this.updateValue(newValue);
                                    this.trashed_files.push(removed);
                                }
                            } else {
                                if (currentValue && currentValue.id === id) {
                                    const removed = currentValue;
                                    this.updateValue({});
                                    this.trashed_files.push(removed);
                                }
                            }

                            this.updateCombinedFiles();
                        },

                        // Restores a file from trashed_files back to the value
                        restoreFile(id) {
                            const index = this.trashed_files.findIndex(file => file.id === id);
                            if (index !== -1) {
                                const restored = this.trashed_files.splice(index, 1)[0];
                                const currentValue = this.displayValue;

                                if (Array.isArray(currentValue)) {
                                    const newValue = [...currentValue, restored];
                                    this.updateValue(newValue);
                                } else {
                                    this.updateValue(restored);
                                }

                                this.updateCombinedFiles();
                            }
                        },

                        // Handles files dropped into the drop zone
                        handleDrop(event) {
                            event.preventDefault();
                            const files = event.dataTransfer.files;
                            const fileInput = this.$refs['file-input'];
                            const fileList = new DataTransfer();
                            for (let i = 0; i < files.length; i++) {
                                fileList.items.add(files[i]);
                            }
                            fileInput.files = fileList.files;
                            this.handleFiles();
                        },

                        // Document preview handler
                        handleDocumentPreview(document_id) {
                            // Use the global page function for document preview
                            this.$dispatch('preview-document', { document_id });
                        },

                        // Formats file size for display
                        formatFileSize(size) {
                            if (size >= 1024 * 1024 * 1024) {
                                return (size / (1024 * 1024 * 1024)).toFixed(2) + ' GB';
                            } else if (size >= 1024 * 1024) {
                                return (size / (1024 * 1024)).toFixed(2) + ' MB';
                            } else if (size >= 1024) {
                                return (size / 1024).toFixed(2) + ' KB';
                            } else {
                                return size + ' bytes';
                            }
                        },

                        // Initialize the component
                        init() {
                            // Watch for value changes to update combined files
                            this.$watch('value', () => {
                                this.updateCombinedFiles();
                            });

                            // Listen for document preview events and delegate to page handler
                            this.$el.addEventListener('preview-document', (event) => {
                                // Find the page component and call its handleDocumentPreview method
                                const pageElement = document.querySelector('[x-data*="page"]');
                                if (pageElement && pageElement._x_dataStack) {
                                    const pageComponent = pageElement._x_dataStack[0];
                                    if (pageComponent.handleDocumentPreview) {
                                        pageComponent.handleDocumentPreview(event.detail.document_id);
                                    }
                                }
                            });

                            this.uploadQueue = [];
                            this.fileUploadStatus = {};
                            this.pendingFiles = [];
                            this.pendingFileData = {};
                            this.updateCombinedFiles();
                        }
                    }));
                });
            </script>
        </cf_once>
    </cfoutput>

<cfelseif thisTag.executionMode EQ "end">
    <!--- not required --->
</cfif>
