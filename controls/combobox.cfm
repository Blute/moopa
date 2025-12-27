<cfif thisTag.executionMode EQ "start">

    <cfparam name="attributes.model" default="" />
    <cfparam name="attributes.value" default="" />
    <cfparam name="attributes.path" default="" hint="path to the property in the model. Can use template syntax to reference nested properties." />
    <cfparam name="attributes.class" default="w-full" />
    <cfparam name="attributes.input_class" default="input input-bordered w-full" />
    <cfparam name="attributes.placeholder" default="Select..." />
    <cfparam name="attributes.route" default="" />
    <cfparam name="attributes.endpoint" default="" />
    <cfparam name="attributes.model_for_search" default="" hint="Model path to include in search requests" />

    <!--- If model is provided, use it for value and path --->
    <cfif len(attributes.model) AND !len(attributes.value)>
        <cfset attributes.value = attributes.model />
    </cfif>
    <cfif len(attributes.model) AND !len(attributes.path)>
        <cfset attributes.path = attributes.model />
    </cfif>

    <!--- Set default endpoint if not provided --->
    <cfif !len(attributes.endpoint)>
        <cfset attributes.endpoint = "search.#attributes.value#" />
    </cfif>

    <!--- Handle route signing if route is provided --->
    <cfif len(attributes.route?:'')>
        <!--- Turns into a signed endpoint string like 'route:'/purchasing/123/details',endpoint:'search.purchase.company_id',x_signed_route:'/purchasing/123/details',x_signature:'...' --->
        <cfset signed_endpoint = application.lib.auth.signedEndpoint(route=attributes.route, endpoint=attributes.endpoint) />
        <cfset request_endpoint = "{#signed_endpoint#}" />
    <cfelse>
        <cfset request_endpoint = "{endpoint:'#attributes.endpoint#'}" />
    </cfif>

    <cfoutput>
    <div
        x-data="moopaComboboxField({
            value: #attributes.value#,
            path: `#attributes.path#`,
            request_endpoint: #request_endpoint#,
            placeholder: '#attributes.placeholder#' <cfif len(attributes.model_for_search?:'')>,
            model_path: '#attributes.model_for_search#'</cfif>
        })"
        class="#attributes.class#"
    >
        <div
            x-combobox
            x-model="selectedValue"
            class="position-relative"
        >
            <!--- Selected items display for multiple mode --->
            <template x-if="isMultipleMode && selectedItems.length > 0">
                <div class="mb-2">
                    <template x-for="(item, index) in selectedItems" :key="item.id">
                        <span class="badge bg-secondary me-1 mb-1 d-inline-flex align-items-center">
                            <span x-text="item.label"></span>
                            <button
                                type="button"
                                class="btn-close btn-close-white ms-2"
                                style="font-size: 0.6em;"
                                @click.stop="removeSelectedItem(index)"
                                aria-label="Remove"
                            ></button>
                        </span>
                    </template>
                </div>
            </template>

            <!--- Input and trigger container --->
            <div class="form-control form-control-sm d-flex align-items-center p-0">
                <input
                    x-combobox:input
                    x-ref="comboboxInput"
                    :display-value="item => isMultipleMode ? '' : (item?.label || '')"
                    @input.debounce.300ms="performSearch($event.target.value)"
                    @keydown.arrow-down="performSearch('')"
                    @click="$event.target.select()"
                    type="text"
                    class="border-0 w-100 #attributes.input_class#"
                    :placeholder="isMultipleMode ? (selectedItems.length > 0 ? 'Add another...' : placeholder) : placeholder"
                    style="outline: none;"
                >
                <div class="d-flex align-items-center h-100">
                    <div class="d-flex align-items-center">
                        <i class="fat fa-fw fa-spinner fa-spin" x-show="loading"></i>
                    </div>
                    <div class="border-start h-100 d-flex">
                        <button
                            type="button"
                            class="btn btn-sm btn-link p-1 h-100 border-0 text-secondary"
                            @click.stop.prevent="clearSelection();"
                            x-show="(isMultipleMode && selectedItems.length > 0) || (!isMultipleMode && selectedValue?.id)"
                            tabindex="-1"
                        >
                            <i class="fat fa-fw fa-times"></i>
                        </button>
                        <button
                            x-combobox:button
                            @click="performSearch('')"
                            type="button"
                            x-show="(isMultipleMode && selectedItems.length === 0) || (!isMultipleMode && !selectedValue?.id)"
                            class="btn btn-sm btn-link p-1 h-100 border-0"
                            tabindex="-1"
                        >
                            <i class="fat fa-fw fa-angles-up-down"></i>
                        </button>
                    </div>
                </div>
            </div>

            <!--- Options dropdown --->
            <ul
                x-combobox:options
                x-show="$combobox.isOpen"
                class="dropdown-menu w-100 shadow-sm border mt-0 p-0 show list-unstyled"
                style="position: absolute; z-index: 1050;"
            >
                <div class="overflow-auto" style="max-height: 250px;">
                    <template x-if="loading && options.length === 0">
                        <li class="dropdown-item px-3 py-2 text-muted">Loading...</li>
                    </template>
                    <template x-if="!loading && options.length === 0">
                        <li class="dropdown-item px-3 py-2 text-muted">No results found</li>
                    </template>
                    <template x-for="option in filteredOptions" :key="option.id">
                        <li
                            x-combobox:option
                            :value="option"
                            @click="handleSelectionChange"
                            class="dropdown-item px-3 py-2 d-flex align-items-center"
                            :class="{
                                'bg-primary text-white': $comboboxOption.isActive,
                                'opacity-75': isOptionSelected(option) && !$comboboxOption.isActive
                            }"
                            style="cursor: pointer;"
                        >
                            <div class="flex-shrink-0 d-flex align-items-center" style="width: 16px; margin-right: 8px;">
                                <i
                                    class="fas fa-check"
                                    :class="$comboboxOption.isActive ? 'text-white' : ''"
                                    x-show="isOptionSelected(option)"
                                ></i>
                            </div>
                            <span class="text-truncate" x-text="option.label"></span>
                        </li>
                    </template>
                </div>
            </ul>
        </div>
    </div>

    <cf_once id="moopa_combobox_field_script" position="body">
    <script defer>
        document.addEventListener("alpine:init", () => {
            Alpine.data("moopaComboboxField", (config) => ({
                // Control pattern properties
                value: config.value,
                path: config.path,

                // Combobox specific properties
                request_endpoint: config.request_endpoint,
                placeholder: config.placeholder,
                model_path: config.model_path || "",
                selectedValue: {},
                selectedItems: [],
                options: [],
                loading: false,

                // Determines if we're in multiple selection mode based on the value type
                get isMultipleMode() {
                    const currentValue = this.getPropertyValueByPath(this.path);
                    return Array.isArray(currentValue) || Array.isArray(this.value);
                },

                // Control pattern computed property
                get displayValue() {
                    const currentValue = this.getPropertyValueByPath(this.path);
                    return this.format(currentValue);
                },

                // Filter options to exclude already selected items in multiple mode
                get filteredOptions() {
                    if (!this.isMultipleMode) {
                        return this.options;
                    }

                    const selectedIds = this.selectedItems.map(item => item.id);
                    return this.options.filter(option => !selectedIds.includes(option.id));
                },

                // Control pattern methods
                format(value) {
                    // Format the stored value for display
                    if (this.isMultipleMode) {
                        return Array.isArray(value) ? value : [];
                    } else {
                        if (!value || (typeof value === 'object' && Object.keys(value).length === 0)) {
                            return {};
                        }
                        return value;
                    }
                },

                parse(value) {
                    // Parse the input value for storage
                    if (this.isMultipleMode) {
                        return Array.isArray(value) ? value : [];
                    } else {
                        if (!value || (typeof value === 'object' && Object.keys(value).length === 0)) {
                            return {};
                        }
                        return value;
                    }
                },

                validate(value) {
                    // Basic validation - always valid by default
                    return true;
                },

                updateProperty(newValue) {
                    const parsedValue = this.parse(newValue);

                    if (!this.validate(parsedValue)) {
                        return;
                    }

                    // Prevent duplicate updates by checking if value actually changed
                    const currentValue = this.getPropertyValueByPath(this.path);
                    if (JSON.stringify(currentValue) === JSON.stringify(parsedValue)) {
                        return; // No change, skip update
                    }

                    this.updatePropertyByPath(this.path, parsedValue);
                },

                // Check if an option is currently selected
                isOptionSelected(option) {
                    if (this.isMultipleMode) {
                        return this.selectedItems.some(item => item.id === option.id);
                    } else {
                        return this.selectedValue?.id === option.id;
                    }
                },

                // Combobox specific methods
                async performSearch(searchTerm = '') {
                    this.loading = true;

                    try {
                        let req_params = {...this.request_endpoint};
                        req_params.q = searchTerm;

                        // If a model path is provided, evaluate it and include in body
                        if (this.model_path && typeof this.getPropertyValueByPath === 'function') {
                            const model_value = this.getPropertyValueByPath(this.model_path);
                            req_params.body = { ...(req_params.body || {}), model: model_value };
                        }

                        const response = await req(req_params);
                        this.options = response || [];
                    } catch (error) {
                        console.error('Error searching:', error);
                        this.options = [];
                    } finally {
                        this.loading = false;
                    }
                },

                clearSelection() {
                    if (this.isMultipleMode) {
                        this.selectedItems = [];
                        this.updateProperty([]);
                    } else {
                        this.selectedValue = {};
                        this.updateProperty({});
                    }
                    this.$refs.comboboxInput.focus();
                    this.$nextTick(() => {
                        this.handleSelectionChange();
                    });
                },

                removeSelectedItem(index) {
                    this.selectedItems.splice(index, 1);
                    this.updateProperty(this.selectedItems);
                    this.$dispatch('value-changed', { selected_options: this.selectedItems });
                },

                handleSelectionChange() {
                    if (this.isMultipleMode) {
                        // Add the selected item to the array if not already present
                        if (this.selectedValue?.id && !this.selectedItems.some(item => item.id === this.selectedValue.id)) {
                            this.selectedItems.push(this.selectedValue);
                            this.updateProperty(this.selectedItems);
                            this.$dispatch('value-changed', { selected_options: this.selectedItems });
                        }

                        // Clear the input after selection in multiple mode
                        this.selectedValue = {};
                        this.$refs.comboboxInput.value = '';
                        this.$refs.comboboxInput.focus();
                    } else {
                        // Update the property with the new selection for single mode
                        this.updateProperty(this.selectedValue);
                        this.$dispatch('value-changed', { selected_option: this.selectedValue });
                    }
                },

                // Initialize the component
                init() {
                    // Watch for changes to the property value and sync with selectedValue/selectedItems
                    this.$watch(() => this.getPropertyValueByPath(this.path), (newValue) => {
                        if (this.isMultipleMode) {
                            this.selectedItems = this.format(newValue);
                        } else {
                            this.selectedValue = this.format(newValue);
                        }
                    });

                    // Initialize from current property value
                    const currentValue = this.displayValue;
                    if (this.isMultipleMode) {
                        this.selectedItems = currentValue;
                    } else {
                        this.selectedValue = currentValue;
                    }

                    // Watch selectedValue changes and update property (single mode)
                    this.$watch('selectedValue', (newValue) => {
                        if (!this.isMultipleMode) {
                            this.updateProperty(newValue);
                        }
                    });

                    // Watch selectedItems changes and update property (multiple mode)
                    this.$watch('selectedItems', (newValue) => {
                        if (this.isMultipleMode) {
                            this.updateProperty(newValue);
                        }
                    });
                }
            }));
        });
    </script>
    </cf_once>

    </cfoutput>

<cfelseif thisTag.executionMode EQ "end">
    <!--- not required --->
</cfif>
