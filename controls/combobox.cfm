<cfif thisTag.executionMode EQ "start">

    <cfparam name="attributes.model" default="" />
    <cfparam name="attributes.class" default="w-full" />
    <cfparam name="attributes.input_class" default="input w-full" />
    <cfparam name="attributes.placeholder" default="Select..." />
    <cfparam name="attributes.route" default="" />
    <cfparam name="attributes.endpoint" default="" />
    <cfparam name="attributes.multiple" default="false" hint="Enable multiple selection mode" />

    <!--- Set default endpoint if not provided --->
    <cfif !len(attributes.endpoint)>
        <cfset attributes.endpoint = "search.#listLast(attributes.model, '.')#" />
    </cfif>

    <!--- Handle route signing if route is provided --->
    <cfif len(attributes.route?:'')>
        <cfset signed_endpoint = application.lib.auth.signedEndpoint(route=attributes.route, endpoint=attributes.endpoint) />
        <cfset request_endpoint = "{#signed_endpoint#}" />
    <cfelse>
        <cfset request_endpoint = "{endpoint:'#attributes.endpoint#'}" />
    </cfif>

    <cfoutput>
    <div
        x-data="moopaCombobox({
            request_endpoint: #request_endpoint#,
            placeholder: '#attributes.placeholder#',
            multiple: #attributes.multiple#
        })"
        x-modelable="value"
        x-model="#attributes.model#"
        x-id="['combo-popover', 'combo-anchor']"
        class="#attributes.class#"
    >
        <!--- Selected items display for multiple mode --->
        <template x-if="multiple && selectedItems.length > 0">
            <div class="flex flex-wrap gap-1 mb-2">
                <template x-for="(item, index) in selectedItems" :key="item.id">
                    <span class="badge badge-secondary gap-1">
                        <span x-text="item.label"></span>
                        <button
                            type="button"
                            class="btn btn-ghost btn-xs btn-circle"
                            @click.stop="removeSelectedItem(index)"
                            aria-label="Remove"
                        >
                            <i class="fa-regular fa-xmark text-xs"></i>
                        </button>
                    </span>
                </template>
            </div>
        </template>

        <!--- Input and trigger container --->
        <label
            class="#attributes.input_class# flex items-center gap-2 pr-1"
            :style="`anchor-name: --${$id('combo-anchor')}`"
        >
            <input
                x-ref="searchInput"
                type="text"
                :value="getDisplayValue()"
                @input.debounce.300ms="searchQuery = $event.target.value; performSearch()"
                @focus="handleFocus()"
                @blur="handleBlur()"
                @keydown.arrow-down.prevent="navigateDown()"
                @keydown.arrow-up.prevent="navigateUp()"
                @keydown.enter.prevent="selectHighlighted()"
                @keydown.escape="closePopover()"
                :placeholder="multiple && selectedItems.length > 0 ? 'Add another...' : placeholder"
                class="grow bg-transparent border-none outline-none"
                autocomplete="off"
            />
            <template x-if="loading">
                <span class="loading loading-spinner loading-sm"></span>
            </template>
            <template x-if="!loading && hasSelection()">
                <button
                    type="button"
                    class="btn btn-ghost btn-xs btn-circle"
                    @click.stop.prevent="clearSelection()"
                    tabindex="-1"
                >
                    <i class="fa-regular fa-xmark"></i>
                </button>
            </template>
            <template x-if="!loading && !hasSelection()">
                <button
                    type="button"
                    class="btn btn-ghost btn-xs btn-circle"
                    @click.stop.prevent="togglePopover()"
                    tabindex="-1"
                >
                    <i class="fa-regular fa-chevron-down"></i>
                </button>
            </template>
        </label>

        <!--- Popover dropdown --->
        <div
            :id="$id('combo-popover')"
            x-ref="popover"
            popover="manual"
            class="dropdown bg-base-100 rounded-box shadow-lg border border-base-300 p-0 my-1 w-[var(--anchor-width)]"
            :style="`position-anchor: --${$id('combo-anchor')}`"
        >
            <!--- Loading state --->
            <div x-show="loading && options.length === 0" class="px-4 py-3 text-base-content/60">
                <span class="loading loading-dots loading-sm"></span>
                Loading...
            </div>

            <!--- No results --->
            <div x-show="!loading && options.length === 0 && searchQuery.length > 0" class="px-4 py-3 text-base-content/60 text-sm">
                No results found
            </div>

            <!--- Options list --->
            <ul x-show="filteredOptions.length > 0" class="menu menu-sm p-0 max-h-64 overflow-y-auto">
                <template x-for="(option, index) in filteredOptions" :key="option.id">
                    <li>
                        <a
                            @click="selectOption(option)"
                            @mouseenter="highlightedIndex = index"
                            :class="{'active': highlightedIndex === index}"
                            class="flex items-center gap-2 py-2"
                        >
                            <i
                                class="fa-solid fa-check text-xs w-4"
                                :class="{'invisible': !isOptionSelected(option)}"
                            ></i>
                            <span class="truncate" x-text="option.label"></span>
                        </a>
                    </li>
                </template>
            </ul>
        </div>
    </div>

    <cf_once id="moopa_combobox_script" position="body">
    <script defer>
    document.addEventListener('alpine:init', () => {
        Alpine.data('moopaCombobox', (config) => ({
            request_endpoint: config.request_endpoint,
            placeholder: config.placeholder,
            multiple: config.multiple || false,

            // The value exposed via x-modelable - synced with parent via x-model
            value: null,

            // Internal state
            searchQuery: '',
            selectedItems: [],
            options: [],
            highlightedIndex: -1,
            loading: false,
            isOpen: false,
            isEditing: false,

            getDisplayValue() {
                // When editing/searching, show the search query
                if (this.isEditing) {
                    return this.searchQuery;
                }
                // Otherwise show the selected value's label (single mode only)
                if (!this.multiple && this.value?.label) {
                    return this.value.label;
                }
                return '';
            },

            handleFocus() {
                this.isEditing = true;
                // If there's a selected value, pre-fill search with its label
                if (!this.multiple && this.value?.label) {
                    this.searchQuery = this.value.label;
                    this.$nextTick(() => this.$refs.searchInput?.select());
                }
                this.performSearch();
            },

            handleBlur() {
                // Small delay to allow click events on options to fire first
                setTimeout(() => {
                    this.isEditing = false;
                    this.searchQuery = '';
                }, 150);
            },

            hasSelection() {
                if (this.multiple) {
                    return this.selectedItems.length > 0;
                }
                return this.value?.id;
            },

            get filteredOptions() {
                if (!this.multiple) {
                    return this.options;
                }
                const selectedIds = this.selectedItems.map(item => item.id);
                return this.options.filter(option => !selectedIds.includes(option.id));
            },

            isOptionSelected(option) {
                if (this.multiple) {
                    return this.selectedItems.some(item => item.id === option.id);
                }
                return this.value?.id === option.id;
            },

            openPopover() {
                if (this.options.length > 0 || this.loading) {
                    this.$refs.popover?.showPopover();
                    this.isOpen = true;
                }
            },

            closePopover() {
                this.$refs.popover?.hidePopover();
                this.isOpen = false;
                this.highlightedIndex = -1;
            },

            togglePopover() {
                if (this.isOpen) {
                    this.closePopover();
                } else {
                    this.performSearch();
                    this.$refs.searchInput?.focus();
                }
            },

            async performSearch() {
                this.loading = true;
                this.openPopover();

                try {
                    const params = { ...this.request_endpoint, q: this.searchQuery };
                    const response = await req(params);
                    this.options = response || [];
                    this.highlightedIndex = this.options.length > 0 ? 0 : -1;
                    if (this.options.length > 0) {
                        this.openPopover();
                    }
                } catch (error) {
                    console.error('Error searching:', error);
                    this.options = [];
                } finally {
                    this.loading = false;
                }
            },

            navigateDown() {
                if (this.highlightedIndex < this.filteredOptions.length - 1) {
                    this.highlightedIndex++;
                }
            },

            navigateUp() {
                if (this.highlightedIndex > 0) {
                    this.highlightedIndex--;
                }
            },

            selectHighlighted() {
                if (this.highlightedIndex >= 0 && this.highlightedIndex < this.filteredOptions.length) {
                    this.selectOption(this.filteredOptions[this.highlightedIndex]);
                }
            },

            selectOption(option) {
                if (this.multiple) {
                    if (!this.selectedItems.some(item => item.id === option.id)) {
                        this.selectedItems.push(option);
                        this.value = [...this.selectedItems];
                        this.$dispatch('change', { value: this.value });
                    }
                    this.searchQuery = '';
                    this.$refs.searchInput?.focus();
                } else {
                    this.value = option;
                    this.searchQuery = '';
                    this.isEditing = false;
                    this.closePopover();
                    this.$dispatch('change', { value: this.value });
                }
            },

            clearSelection() {
                if (this.multiple) {
                    this.selectedItems = [];
                    this.value = [];
                } else {
                    this.value = null;
                }
                this.searchQuery = '';
                this.isEditing = true;
                this.$refs.searchInput?.focus();
                this.$dispatch('change', { value: this.value });
            },

            removeSelectedItem(index) {
                this.selectedItems.splice(index, 1);
                this.value = [...this.selectedItems];
                this.$dispatch('change', { value: this.value });
            },

            init() {
                // Initialize internal state from the bound value
                if (this.multiple) {
                    this.selectedItems = Array.isArray(this.value) ? [...this.value] : [];
                }

                // Watch for external changes to value (from parent via x-model)
                this.$watch('value', (newValue) => {
                    if (this.multiple) {
                        const newItems = Array.isArray(newValue) ? newValue : [];
                        if (JSON.stringify(this.selectedItems) !== JSON.stringify(newItems)) {
                            this.selectedItems = [...newItems];
                        }
                    }
                });

                // Close popover when clicking outside
                document.addEventListener('click', (e) => {
                    if (this.$refs.popover && !this.$el.contains(e.target)) {
                        this.closePopover();
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
