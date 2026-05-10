<!---
GEOSCAPE ADDRESS CONTROL

Uses Geoscape Predictive Address API for Australian address autocomplete.
Uses daisyUI popover dropdown to avoid modal overflow issues.

USAGE:
<cf_control_address
    model="record.address"
    route="/api/geoscape"
    class="w-full"
    input_class="input w-full"
    placeholder="Search for address"
/>

The address object stored in the model will contain (from GET /v1/predictive/address/{id}):
{
    id: "GAACT717940975",           // Geoscape address identifier
    formatted_address: "...",       // Full formatted address string
    street_number: "113",           // Street number
    street_name: "CANBERRA",        // Street name
    street_type: "AVENUE",          // Street type
    locality_name: "GRIFFITH",      // Suburb/locality
    state_territory: "ACT",         // State/territory code
    postcode: "2603",               // Postcode
    latitude: -35.123,              // Latitude (if available)
    longitude: 149.123,             // Longitude (if available)
    cadastral_identifier: "...",    // Cadastral reference
    ... and more properties from Geoscape
}
--->

<cfif thisTag.executionMode EQ "start">

    <cfparam name="attributes.model" default="" />
    <cfparam name="attributes.class" default="w-full" />
    <cfparam name="attributes.input_class" default="input w-full" />
    <cfparam name="attributes.placeholder" default="Search for address" />
    <cfparam name="attributes.route" default="/api/geoscape" />
    <cfparam name="attributes.endpoint" default="search.address" />
    <cfparam name="attributes.detail_endpoint" default="detail.address" />

    <!--- Handle route signing --->
    <cfset signed_search = application.lib.auth.signedEndpoint(route=attributes.route, endpoint=attributes.endpoint) />
    <cfset signed_detail = application.lib.auth.signedEndpoint(route=attributes.route, endpoint=attributes.detail_endpoint) />
    <cfset search_endpoint = "{#signed_search#}" />
    <cfset detail_endpoint = "{#signed_detail#}" />

    <cfoutput>
    <div
        x-data="geoscapeAddress({
            search_endpoint: #search_endpoint#,
            detail_endpoint: #detail_endpoint#
        })"
        x-modelable="address"
        x-model="#attributes.model#"
        x-id="['addr-popover', 'addr-anchor']"
    >
        <!--- Selected address display --->
        <template x-if="hasAddress() && !isEditing">
            <div class="join w-full">
                <label class="input join-item flex-1 min-w-0 flex items-center gap-2 cursor-pointer">
                    <span class="truncate" x-text="getFormattedAddress()" @click="startEditing()"></span>
                </label>
                <button
                    class="btn btn-square join-item"
                    @click="clearAddress()"
                    type="button"
                    title="Clear address"
                >
                    <i class="fa-regular fa-xmark"></i>
                </button>
            </div>
        </template>

        <!--- Search input with popover dropdown --->
        <template x-if="!hasAddress() || isEditing">
            <div>
                <!--- Input acts as anchor for the popover --->
                <label
                    class="#attributes.input_class# flex items-center gap-2 pr-2"
                    :style="`anchor-name: --${$id('addr-anchor')}`"
                >
                    <template x-if="!loading">
                        <i class="fa-regular fa-magnifying-glass text-base-content/50"></i>
                    </template>
                    <template x-if="loading">
                        <span class="loading loading-spinner loading-sm"></span>
                    </template>
                    <input
                        x-ref="searchInput"
                        type="text"
                        x-model="searchQuery"
                        @input.debounce.300ms="performSearch()"
                        @focus="openPopover()"
                        @keydown.arrow-down.prevent="navigateDown()"
                        @keydown.arrow-up.prevent="navigateUp()"
                        @keydown.enter.prevent="selectHighlighted()"
                        @keydown.escape="closePopover()"
                        placeholder="#attributes.placeholder#"
                        class="grow bg-transparent border-none outline-none"
                        autocomplete="off"
                    />
                    <button
                        x-show="searchQuery.length > 0"
                        type="button"
                        class="btn btn-ghost btn-xs btn-circle"
                        @click="searchQuery = ''; suggestions = []; closePopover();"
                        tabindex="-1"
                    >
                        <i class="fa-regular fa-xmark"></i>
                    </button>
                </label>

                <!--- Popover dropdown (renders in top layer - no overflow issues) --->
                <div
                    :id="$id('addr-popover')"
                    x-ref="popover"
                    popover="manual"
                    class="dropdown bg-base-100 rounded-box shadow-lg border border-base-300 p-0 my-2 w-[var(--anchor-width)]"
                    :style="`position-anchor: --${$id('addr-anchor')}`"
                >
                    <!--- Loading state --->
                    <div x-show="loading && suggestions.length === 0" class="px-4 py-3 text-base-content/60">
                        <span class="loading loading-dots loading-sm"></span>
                        Searching...
                    </div>

                    <!--- Error state --->
                    <div x-show="error" class="px-4 py-3 text-error text-sm">
                        <i class="fa-regular fa-circle-exclamation mr-1"></i>
                        <span x-text="error"></span>
                    </div>

                    <!--- No results --->
                    <div x-show="!loading && !error && suggestions.length === 0 && searchQuery.length >= 3" class="px-4 py-3 text-base-content/60 text-sm">
                        No addresses found
                    </div>

                    <!--- Suggestions list --->
                    <ul x-show="suggestions.length > 0" class="menu menu-sm p-0 max-h-64 overflow-y-auto">
                        <template x-for="(suggestion, index) in suggestions" :key="suggestion.id || index">
                            <li>
                                <a
                                    @click="selectAddress(suggestion)"
                                    @mouseenter="highlightedIndex = index"
                                    :class="{'active': highlightedIndex === index}"
                                    class="flex items-center gap-2 py-2"
                                >
                                    <i class="fa-regular fa-location-dot text-base-content/50 flex-shrink-0"></i>
                                    <span x-text="suggestion.full"></span>
                                </a>
                            </li>
                        </template>
                    </ul>


                </div>
            </div>
        </template>

        <!--- Loading details indicator --->
        <div x-show="loadingDetails" x-cloak class="mt-2 flex items-center gap-2 text-sm text-base-content/60">
            <span class="loading loading-spinner loading-sm"></span>
            Fetching address details...
        </div>
    </div>
    </cfoutput>

<cfelseif thisTag.executionMode EQ "end">
    <!--- not required --->
</cfif>
