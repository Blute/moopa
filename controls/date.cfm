<cfif thisTag.executionMode EQ "start">

    <cfparam name="attributes.model" default="" />
    <cfparam name="attributes.class" default="input" />
    <cfparam name="attributes.placeholder" default="" />
    <cfparam name="attributes.id" default="" />
    <cfparam name="attributes.show_quick_options" default="true" />

    <cfoutput>
        <div
            x-data="control_date"
            x-modelable="value"
            x-model="#attributes.model#"
            class="join"
        >
            <input
                class="#attributes.class# join-item"
                type="date"
                :value="formatValue()"
                @focus="$el.dataset.initial = $el.value"
                @blur="if($el.dataset.initial !== $el.value) { changeValue($el.value) }"
                placeholder="#attributes.placeholder#"
                <cfif len(attributes.id)>id="#attributes.id#"</cfif>
            >
            <cfif attributes.show_quick_options>
                <div class="dropdown dropdown-end">
                    <button class="btn join-item" type="button" tabindex="0"><i class="fal fa-chevron-down"></i></button>
                    <ul tabindex="0" class="dropdown-content menu bg-base-100 rounded-box z-10 w-40 p-2 shadow">
                        <li><button type="button" @click="setDate(0, 'day')">Today</button></li>
                        <li><button type="button" @click="setDate(1, 'day')">Tomorrow</button></li>
                        <li><button type="button" @click="setDate(1, 'week')">Next Week</button></li>
                        <li><button type="button" @click="setDate(1, 'month')">Next Month</button></li>
                    </ul>
                </div>
            </cfif>
        </div>

        <cf_once id="control_date_script" position="body">
            <script defer>
                document.addEventListener("alpine:init", () => {
                    Alpine.data("control_date", () => ({
                        value: '',

                        formatValue() {
                            if (!this.value) return '';
                            // Handle ISO date format, return YYYY-MM-DD for date input
                            if (typeof this.value === 'string' && this.value.match(/^\d{4}-\d{2}-\d{2}/)) {
                                return this.value.split('T')[0];
                            }
                            const date = new Date(this.value);
                            if (isNaN(date.getTime())) return '';
                            return date.toISOString().split('T')[0];
                        },

                        changeValue(inputValue) {
                            if (!inputValue) {
                                this.value = '';
                                return;
                            }
                            // Validate YYYY-MM-DD format
                            if (!/^\d{4}-\d{2}-\d{2}$/.test(inputValue)) {
                                this.value = '';
                                return;
                            }
                            this.value = inputValue;
                        },

                        setDate(count, unit) {
                            const today = new Date();
                            const d = new Date(Date.UTC(today.getFullYear(), today.getMonth(), today.getDate()));

                            if (unit === 'day') d.setUTCDate(d.getUTCDate() + count);
                            else if (unit === 'week') d.setUTCDate(d.getUTCDate() + (count * 7));
                            else if (unit === 'month') d.setUTCMonth(d.getUTCMonth() + count);

                            const year = d.getUTCFullYear();
                            const month = String(d.getUTCMonth() + 1).padStart(2, '0');
                            const day = String(d.getUTCDate()).padStart(2, '0');
                            this.value = `${year}-${month}-${day}`;
                        }
                    }));
                });
            </script>
        </cf_once>
    </cfoutput>

<cfelseif thisTag.executionMode EQ "end">
    <!--- not required --->
</cfif>
