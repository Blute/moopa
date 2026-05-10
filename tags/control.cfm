<!---
SINGLE CONTROL TAG - Pure attribute-driven rendering

Renders a single form control with optional label wrapper.
Control templates are resolved from loaded Moopa packages, with app/shared
packages overriding core Moopa controls.
--->

<cfif not thistag.HasEndTag>
    <cfabort showerror="Control must have an end tag...">
</cfif>

<cfif thisTag.executionMode EQ "start">

    <!--- Core attributes --->
    <cfparam name="attributes.control" type="string" default="text">
    <cfparam name="attributes.label" type="string" default="">
    <cfparam name="attributes.model" type="string" default="">

    <!--- Layout and styling --->
    <cfparam name="attributes.label_position" type="string" default="top">
    <cfparam name="attributes.class" type="string" default="fieldset">

    <!--- Common control attributes that get passed through --->
    <cfparam name="attributes.id" type="string" default="">
    <cfparam name="attributes.placeholder" type="string" default="">
    <cfparam name="attributes.required" type="boolean" default="false">
    <cfparam name="attributes.readonly" type="boolean" default="false">
    <cfparam name="attributes.disabled" type="boolean" default="false">
    <cfparam name="attributes.multiple" default="">
    <cfparam name="attributes.route" type="string" default="">

    <!--- Normalize control type: strip control_ and input_ prefixes if present. --->
    <cfset control_type = attributes.control />
    <cfif control_type.startsWith("control_")>
        <cfset control_type = control_type.replaceFirst("control_", "") />
    </cfif>
    <cfif control_type.startsWith("input_")>
        <cfset control_type = control_type.replaceFirst("input_", "") />
    </cfif>
    <cfif control_type EQ "datetime_local">
        <cfset control_type = "datetime" />
    </cfif>

    <!--- Build control attributes (exclude layout-specific attrs). --->
    <cfset control_attrs = {} />
    <cfloop collection="#attributes#" item="attr_name">
        <cfif !listFindNoCase("label_position,class,label,control", attr_name)>
            <cfif isSimpleValue(attributes[attr_name]) AND len(attributes[attr_name])>
                <cfset control_attrs[attr_name] = attributes[attr_name] />
            <cfelseif NOT isSimpleValue(attributes[attr_name])>
                <cfset control_attrs[attr_name] = attributes[attr_name] />
            </cfif>
        </cfif>
    </cfloop>

    <!--- Generate unique ID if not provided. --->
    <cfif not len(control_attrs.id ?: "")>
        <cfset control_attrs.id = "ctrl_#createUUID()#" />
    </cfif>

    <!---
        Determine control template path.
        Package-oriented projects resolve in reverse package order so the current
        app overrides shared/domain packages, which override core Moopa controls.
    --->
    <cfset control_template = "" />

    <cfif NOT (isDefined("application.moopa_packages") AND isArray(application.moopa_packages))>
        <cfthrow message="Cannot render control '#control_type#': application.moopa_packages is not initialized." />
    </cfif>

    <cfloop from="#arrayLen(application.moopa_packages)#" to="1" step="-1" index="package_index">
        <cfset control_package = application.moopa_packages[package_index] />
        <cfif isArray(control_package.load ?: "")
            AND arrayFindNoCase(control_package.load, "controls")
            AND ((control_package.kind ?: "") NEQ "app" OR (control_package.app_name ?: control_package.name) EQ (application.app_name ?: "project"))>

            <cfset candidate_template = "#control_package.path#/controls/#control_type#.cfm" />
            <cfif fileExists(expandPath(candidate_template))>
                <cfset control_template = candidate_template />
                <cfbreak />
            </cfif>
        </cfif>
    </cfloop>

    <cfif !len(control_template)>
        <cfthrow message="No control template found for control '#control_type#'. Add '#control_type#.cfm' to a package controls directory loaded by application.moopa_packages." />
    </cfif>

    <cfoutput>

    <!--- Render the control with proper label positioning. --->
    <cfif len(attributes.label)>
        <cfif attributes.label_position EQ "left">
            <div class="flex items-center gap-4">
                <label for="#control_attrs.id#" class="w-1/4">#attributes.label#</label>
                <div class="flex-1">
                    <cfmodule
                        template="#control_template#"
                        attributecollection="#control_attrs#"
                    />
                </div>
            </div>
        <cfelse>
            <fieldset class="#attributes.class#">
                <legend class="fieldset-legend">#attributes.label#</legend>
                <cfmodule
                    template="#control_template#"
                    attributecollection="#control_attrs#"
                />
            </fieldset>
        </cfif>
    <cfelse>
        <cfmodule
            template="#control_template#"
            attributecollection="#control_attrs#"
        />
    </cfif>

    </cfoutput>

</cfif>

<cfif thisTag.executionMode EQ "end">

    <cfif len(thisTag.generatedContent)>
        <cfset attributes.text = thisTag.generatedContent />
        <cfset thisTag.generatedContent = "" />
    </cfif>

</cfif>
