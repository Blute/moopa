<cfif thisTag.executionMode EQ "start">

    <cfparam name="attributes.model" default="" />
    <cfparam name="attributes.value" default="" />
    <cfparam name="attributes.path" default="" hint="path to the property in the model. Can use template syntax to reference nested properties." />
    <cfparam name="attributes.class" default="" />
    <cfparam name="attributes.label" default="Upload Files" />
    <cfparam name="attributes.help_text" default="Click or drag files to upload" />
    <cfparam name="attributes.show_file_list" default="true" hint="Whether to show the file list after upload. Set to false to hide completed files." />
    <cfparam name="attributes.upload_body_class" default="p-4 text-center" />
    <cfparam name="attributes.route" default="" />
    <cfparam name="attributes.endpoint" default="" />
    <cfparam name="attributes.table_name" default="" />
    <cfparam name="attributes.field_name" default="" />

    <!--- If model is provided, use it for value and path --->
    <cfif len(attributes.model) AND !len(attributes.value)>
        <cfset attributes.value = attributes.model />
    </cfif>
    <cfif len(attributes.model) AND !len(attributes.path)>
        <cfset attributes.path = attributes.model />
    </cfif>

    <!--- Build endpoint configuration --->
    <cfif !len(attributes.endpoint)>
        <cfset attributes.endpoint = "uploadFileToServerWithProgress.#listLast(attributes.path,'.')#" />
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
                value: #attributes.value#,
                path: `#attributes.path#`,
                request_endpoint: #request_endpoint#,
                table_name: '#attributes.table_name#',
                field_name: '#attributes.field_name#',
                show_file_list: #lCase(attributes.show_file_list)#
            })"
        >


            <div class="card border mb-2"
                x-data="{ isDragging: false, isOver: false }"
                x-on:dragover.prevent="isDragging = true"
                x-on:dragleave="if (!event.relatedTarget || !event.relatedTarget.closest('.card')) { isDragging = false }"
                x-on:drop.prevent="isDragging = false; handleDrop($event)"
                :class="{ 'bg-secondary text-white': isDragging }"
                x-show="shouldShowUploadArea"
            >
                <div class="#attributes.upload_body_class#">
                    <div class="file-selector">
                        <label :for="$id('input_file')" class="d-block">
                            <span class="">
                                <i class="fal fa-cloud-arrow-up fa-xl me-2"></i> #attributes.help_text#
                            </span>
                        </label>
                        <input type="file" :id="$id('input_file')" :multiple="isMultipleMode" x-ref="file-input" @change="handleFiles" class="d-none">
                    </div>
                </div>
            </div>


            <template x-if="combined_files?.length && (show_file_list || hasUploadingFiles())">
                <table class="table table-hover table-sm border">
                    <tbody>
                        <template x-for="(file, index) in combined_files" :key="file.id">
                            <tr
                                :class="{'table-danger': file.is_trashed}"
                                @mouseenter="activeIndex = index"
                                @mouseleave="activeIndex = null"
                            >
                                <td class="text-nowrap" style="width:50px;">
                                    <button class="btn btn-sm btn-link" @click.prevent="handleDocumentPreview(file.id)">
                                        <img :src="file.thumbnail" style="width:30px;height:30px;">
                                    </button>
                                </td>

                                <td class="text-truncate" style="max-width: 0;">
                                    <span x-text="file.name" :class="{'text-muted': file.is_trashed}"></span>
                                </td>

                                <td class="text-nowrap" style="width:100px;">
                                    <span class="text-muted text-nowrap mx-2" x-text="formatFileSize(file.size)"></span>
                                </td>

                                <td class="text-nowrap" style="width:85px;">
                                    <span
                                        class="upload-indicator"
                                        x-show="uploadProgress[file.id] < 100 && !processingFiles[file.id]"
                                        :class="{ 'badge text-bg-danger': uploadProgress[file.id] === 0, 'badge text-bg-light': uploadProgress[file.id] > 0 }"
                                    >
                                        <span x-text="uploadProgress[file.id] + '%'"></span>
                                    </span>

                                    <span
                                        class="upload-indicator badge text-bg-success text-white"
                                        x-show="uploadProgress[file.id] === 100 && !processingFiles[file.id]"
                                    >
                                        uploaded
                                    </span>

                                    <span
                                        class="upload-indicator badge text-bg-info text-white"
                                        x-show="processingFiles[file.id]"
                                    >
                                        <i class="fas fa-spinner fa-spin me-1"></i> processing
                                    </span>
                                </td>

                                <td class="text-nowrap" style="width:65px;">
                                    <button
                                        type="button"
                                        class="btn btn-link py-0 border-0 text-danger"
                                        x-on:click.stop="removeFile(file.id)"
                                        x-bind:class="{'text-danger': activeIndex===index, 'text-muted': activeIndex!==index}"
                                        x-show="!file.is_trashed"
                                    >
                                        <i class="fal fa-trash fa-xl"></i>
                                    </button>

                                    <button
                                        type="button"
                                        class="btn btn-link py-0 border-0 text-danger"
                                        x-on:click.stop="restoreFile(file.id)"
                                        x-bind:class="{'text-danger': activeIndex===index, 'text-muted': activeIndex!==index}"
                                        x-show="file.is_trashed"
                                    >
                                        <i class="fal fa-trash-undo fa-xl"></i>
                                    </button>
                                </td>
                            </tr>
                        </template>
                    </tbody>
                </table>
            </template>
        </div>

        <cf_once id="moopa_file_upload_field_script" position="body">
            <script defer>
                document.addEventListener("alpine:init", () => {
                    Alpine.data("moopaFileUploadField", (config) => ({
                        value: config.value,
                        path: config.path,
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

                        // Determines if we're in multiple file mode based on the value type
                        get isMultipleMode() {
                            const currentValue = this.getPropertyValueByPath(this.path);
                            return Array.isArray(currentValue) || Array.isArray(this.value);
                        },

                        get displayValue() {
                            const currentValue = this.getPropertyValueByPath(this.path);
                            return this.format(currentValue);
                        },

                        get parentId() {
                            // Extract parent ID from path by removing the last segment
                            const pathParts = this.path.split('.');
                            pathParts.pop(); // Remove the field name
                            const parentPath = pathParts.join('.') + '.id';
                            return this.getPropertyValueByPath(parentPath);
                        },

                        // Determines whether to show the upload area
                        get shouldShowUploadArea() {
                            // Always show for multiple file uploads
                            if (!this.isSingleFile()) {
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

                        format(value) {
                            return value || (this.isMultipleMode ? [] : null);
                        },

                        parse(value) {
                            return value || (this.isMultipleMode ? [] : null);
                        },

                        validate(value) {
                            return true;
                        },

                        updateProperty(newValue) {
                            const parsedValue = this.parse(newValue);

                            if (!this.validate(parsedValue)) {
                                return;
                            }

                            this.updatePropertyByPath(this.path, parsedValue);
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

                                this.$dispatch('file_uploading_input_file', {
                                    file: file_data.file,
                                    path: this.path
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

                                        this.$dispatch('file_uploaded_input_file', {
                                            file: updatedFile,
                                            path: this.path
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

                        // Checks if all files in the queue have been uploaded and updates property
                        checkAllUploadsComplete() {
                            const allUploaded = this.uploadQueue.every(fileId => this.fileUploadStatus[fileId] === true);

                            if (allUploaded && this.uploadQueue.length > 0) {
                                // All files uploaded, now update the property with all pending files
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

                                // Update the property
                                this.updateProperty(newValue);

                                // Clear pending files
                                this.pendingFiles = [];
                                this.pendingFileData = {};

                                this.$dispatch('all_files_uploaded_input_file', {
                                    files: newValue,
                                    path: this.path
                                });

                                this.uploadQueue = [];
                                this.fileUploadStatus = {};

                                // Update combined files after clearing pending
                                this.updateCombinedFiles();
                            }
                        },

                        // Removes a file from the property and moves it to trashed_files
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
                                    this.updateProperty(newValue);
                                    this.trashed_files.push(removed);
                                }
                            } else {
                                if (currentValue && currentValue.id === id) {
                                    const removed = currentValue;
                                    this.updateProperty({});
                                    this.trashed_files.push(removed);
                                }
                            }

                            this.updateCombinedFiles();
                        },

                        // Restores a file from trashed_files back to the property
                        restoreFile(id) {
                            const index = this.trashed_files.findIndex(file => file.id === id);
                            if (index !== -1) {
                                const restored = this.trashed_files.splice(index, 1)[0];
                                const currentValue = this.displayValue;

                                if (Array.isArray(currentValue)) {
                                    const newValue = [...currentValue, restored];
                                    this.updateProperty(newValue);
                                } else {
                                    this.updateProperty(restored);
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
                            this.$watch(() => this.getPropertyValueByPath(this.path), () => {
                                this.updateCombinedFiles();
                            });

                            this.$watch(() => this.parentId, () => {
                                this.trashed_files = [];
                                this.pendingFiles = [];
                                this.pendingFileData = {};
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
