<!---
TABLE CONTROLS TAG - Table metadata-driven control generation

Generates multiple form controls by reading field definitions from table metadata.
Delegates actual rendering to <cf_control>.
--->

<cfif not thistag.HasEndTag>
    <cfabort showerror="Table controls must have an end tag...">
</cfif>

<cfif thisTag.executionMode EQ "start">

    <!--- Required: table definition source --->
    <cfparam name="attributes.table_name" type="string" default="">
    <cfparam name="attributes.fields" type="string" default="">

    <!--- Optional: per-field config overrides --->
    <cfparam name="attributes.config" type="struct" default="#structNew()#">

    <!--- Model binding --->
    <cfparam name="attributes.model_record" type="string" default="current_record">

    <!--- Layout attributes (passed through to cf_control) --->
    <cfparam name="attributes.label_position" type="string" default="top">
    <cfparam name="attributes.class" type="string" default="fieldset">

    <cfif not len(attributes.table_name) OR not len(attributes.fields)>
        <cfabort showerror="table_controls requires both table_name and fields attributes">
    </cfif>

    <cfset table = application.lib.db.getTableDef(attributes.table_name) />

    <cfoutput>

    <cfloop list="#attributes.fields#" item="field_name">
        <cfset field_name = trim(field_name) />

        <cfif !structKeyExists(table.fields, field_name)>
            <cfthrow message="Cannot render table controls for '#attributes.table_name#': field '#field_name#' does not exist in the table definition." />
        </cfif>

        <!--- Start with table field metadata. --->
        <cfset field_def = table.fields[field_name] />
        <cfset control_attrs = duplicate(field_def.html ?: {}) />

        <!--- Field metadata can opt out of generated forms. --->
        <cfif control_attrs.hidden ?: false>
            <cfcontinue />
        </cfif>

        <!--- Set label from table definition unless the UI metadata overrides it. --->
        <cfset control_attrs.label = control_attrs.label ?: field_def.label ?: "" />

        <!--- Auto-generate model path. --->
        <cfset control_attrs.model = "#attributes.model_record#.#field_name#" />

        <!--- Determine control type from table definition. --->
        <cfif structKeyExists(control_attrs, "control")>
            <cfset control_attrs.control = replace(control_attrs.control, "control_", "") />
        <cfelseif structKeyExists(control_attrs, "type")>
            <cfset control_attrs.control = replace(control_attrs.type, "input_", "") />
        <cfelse>
            <cfset control_attrs.control = "text" />
        </cfif>

        <!--- Generate field ID. --->
        <cfset control_attrs.id = "#attributes.table_name#_#field_name#" />

        <!--- Apply any config overrides for this field. --->
        <cfif structKeyExists(attributes.config, field_name)>
            <cfset structAppend(control_attrs, attributes.config[field_name], true) />
        </cfif>

        <!--- Pass layout attributes. --->
        <cfset control_attrs.label_position = attributes.label_position />
        <cfset control_attrs.class = attributes.class />

        <!--- Delegate to cf_control for rendering. --->
        <cf_control attributecollection="#control_attrs#"></cf_control>

    </cfloop>

    </cfoutput>

</cfif>

<cfif thisTag.executionMode EQ "end">

    <cfif len(thisTag.generatedContent)>
        <cfset attributes.text = thisTag.generatedContent />
        <cfset thisTag.generatedContent = "" />
    </cfif>

</cfif>
