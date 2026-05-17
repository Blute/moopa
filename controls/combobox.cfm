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
        <cfset request_endpoint = serializeJSON(signed_endpoint) />
    <cfelse>
        <cfset request_endpoint = serializeJSON({endpoint: attributes.endpoint}) />
    </cfif>

    <cfoutput>
    <div
        x-data="moopaCombobox({
            request_endpoint: #encodeForHTMLAttribute(request_endpoint)#,
            placeholder: '#encodeForJavaScript(attributes.placeholder)#',
            multiple: #encodeForJavaScript(attributes.multiple)#
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
                            <i class="hgi-stroke hgi-cancel-01 text-xs"></i>
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
                    <i class="hgi-stroke hgi-cancel-01"></i>
                </button>
            </template>
            <template x-if="!loading && !hasSelection()">
                <button
                    type="button"
                    class="btn btn-ghost btn-xs btn-circle"
                    @click.stop.prevent="togglePopover()"
                    tabindex="-1"
                >
                    <i class="hgi-stroke hgi-arrow-down-01"></i>
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
                                class="hgi-stroke hgi-tick-02 text-xs w-4"
                                :class="{'invisible': !isOptionSelected(option)}"
                            ></i>
                            <span class="truncate" x-text="option.label"></span>
                        </a>
                    </li>
                </template>
            </ul>
        </div>
    </div>

    </cfoutput>

<cfelseif thisTag.executionMode EQ "end">
    <!--- not required --->
</cfif>
