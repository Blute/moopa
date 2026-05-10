<cfif thisTag.executionMode EQ "start">

    <cfparam name="attributes.id" default="#createUniqueID()#" />
    <cfparam name="attributes.model" default="" />
    <cfparam name="attributes.class" default="input" />
    <cfparam name="attributes.placeholder" default="Tap to select..." />
    <cfparam name="attributes.label" default="" />
    <cfparam name="attributes.startYear" default="1910" />

    <cfoutput>
    <div
        x-data="dobPicker({ startYear: #attributes.startYear# })"
        x-modelable="value"
        x-model="#attributes.model#"
        x-cloak
        class="join w-full"
    >
        <label class="input join-item flex-1 min-w-0 flex items-center gap-2 cursor-pointer" @click="openPicker()">
            <input
                type="text"
                id="#attributes.id#"
                readonly
                :value="formattedDate()"
                placeholder="#attributes.placeholder#"
                class="grow bg-transparent border-none outline-none cursor-pointer"
            >
        </label>
        <!-- Clear button -->
        <button
            x-show="value"
            x-cloak
            type="button"
            @click.stop="clearDate()"
            class="btn btn-square join-item"
            title="Clear date"
        >
            <i class="hgi-stroke hgi-cancel-01"></i>
        </button>

        <!-- DaisyUI Dialog Modal -->
        <dialog x-ref="dobModal" class="modal" @close="showPicker = false">
            <div class="modal-box max-w-xs p-0 overflow-hidden">

                <!-- Header -->
                <div class="flex items-center px-2 py-2 border-b border-base-200 bg-base-200/50">
                    <button type="button" @click="goBack()" :disabled="view === 'decades'" class="btn btn-ghost btn-xs btn-square disabled:opacity-0">
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"></path>
                        </svg>
                    </button>
                    <div class="flex-1 text-center">
                        <span class="font-semibold text-sm text-base-content" x-text="headerText"></span>
                    </div>
                    <form method="dialog">
                        <button type="submit" class="btn btn-ghost btn-xs btn-square">
                            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                            </svg>
                        </button>
                    </form>
                </div>

                <!-- Scrollable List Area -->
                <div data-simplebar class="max-h-64 bg-base-100">

                    <!-- VIEW 1: Decades (vertical list) -->
                    <div x-show="view === 'decades'" class="flex flex-col p-1">
                        <template x-for="decade in decades" :key="decade">
                            <button type="button" @click="selectDecade(decade)" class="flex items-center justify-between px-3 py-1.5 text-sm rounded hover:bg-primary hover:text-primary-content transition-colors group">
                                <span class="font-medium" x-text="formatDecadeLabel(decade)"></span>
                                <span class="text-xs text-base-content/40 group-hover:text-primary-content/60" x-text="decade + '-' + (decade + 9)"></span>
                            </button>
                        </template>
                    </div>

                    <!-- VIEW 2: Years (compact grid) -->
                    <div x-show="view === 'years'" class="grid grid-cols-5 gap-1 p-2">
                        <template x-for="year in yearsInDecade" :key="year">
                            <button type="button" @click="selectYear(year)" class="px-2 py-2 text-sm font-medium text-base-content rounded hover:bg-primary hover:text-primary-content transition-colors" x-text="year"></button>
                        </template>
                    </div>

                    <!-- VIEW 3: Months (compact grid) -->
                    <div x-show="view === 'months'" class="grid grid-cols-3 gap-1 p-2">
                        <template x-for="(month, index) in months" :key="index">
                            <button type="button" @click="selectMonth(index)" class="px-2 py-2 text-sm font-medium text-base-content rounded hover:bg-primary hover:text-primary-content transition-colors" x-text="month.slice(0,3)"></button>
                        </template>
                    </div>

                    <!-- VIEW 4: Days Grid -->
                    <div x-show="view === 'days'" class="p-2">
                        <div class="grid grid-cols-7 mb-2">
                            <template x-for="day in ['S','M','T','W','T','F','S']">
                                <span class="text-xs font-bold text-center text-base-content/50" x-text="day"></span>
                            </template>
                        </div>
                        <div class="grid grid-cols-7 gap-0.5">
                            <template x-for="blank in blankDays"><div></div></template>
                            <template x-for="day in daysInMonth">
                                <button type="button" @click="selectDay(day)" class="h-8 w-8 mx-auto flex items-center justify-center text-sm rounded-full text-base-content hover:bg-primary hover:text-primary-content transition-colors" x-text="day"></button>
                            </template>
                        </div>
                    </div>

                </div>
            </div>
            <form method="dialog" class="modal-backdrop"><button type="submit">close</button></form>
        </dialog>
    </div>
    </cfoutput>

<cfelseif thisTag.executionMode EQ "end">
    <!--- not required --->
</cfif>
