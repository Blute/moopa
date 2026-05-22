<cfcomponent displayName="db_schema_normalizer" output="false" hint="Normalizes Moopa table definitions into the runtime schema metadata used by the db facade.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfreturn this />
    </cffunction>

    <cffunction name="formatLabelFromFieldName" access="private">
        <cfargument name="field_name" />
        <!---   = "this_is_a_sample_string"> --->

        <cfset stringWithSpaces = reReplace(field_name, "_", " ", "all")>
        <cfset wordsArray = listToArray(stringWithSpaces, " ")>

        <cfset formattedLabel = "">
        <cfloop array="#wordsArray#" index="word">
            <cfif len(word) GT 1>
                <cfset formattedLabel = formattedLabel & ucase(left(word, 1)) & right(word, len(word) - 1) & " ">
            <cfelse>
                <cfset formattedLabel = formattedLabel & ucase(word) & " ">
            </cfif>
        </cfloop>

        <cfreturn trim(formattedLabel) />
    </cffunction>





    <cffunction name="normalize" returnType="struct" hint="Normalize table definitions into the runtime codeSchema shape expected by db.cfc and schema sync.">
        <cfargument name="codeSchemaInput" type="struct" required="true">
        <cfargument name="searchableTables" type="struct" required="true">

        <cfset codeSchemaOutput = {}>

        <cfloop collection="#arguments.codeSchemaInput#" item="table" index="table_key">
            <cfif not structKeyExists(table, "table_name")>
              <cfset table.table_name = table_key>
            </cfif>
            <cfif not structKeyExists(table, "title")>
              <cfset table.title = table.table_name>
            </cfif>
            <cfif not structKeyExists(table, "title_plural")>
              <cfset table.title_plural = "#table.title#s">
            </cfif>

            <cfset table.item_label_template = (table.item_label_template?:'`#table.table_name# ${item.id}`')>
            <cfset table.label_generation_expression = (table.label_generation_expression?:"'#table.table_name#: ' || COALESCE(id::text, '')")>



            <cfif not structKeyExists(table, "searchable_fields")>
                <cfset table.searchable_fields = "">
            </cfif>


          <cfif not structKeyExists(table, "add_system_fields")>
            <cfset table.add_system_fields = true />
          </cfif>


          <cfif !len(table.order_by?:'')>
            <cfif table.add_system_fields>
                <cfset table.order_by = "created_at desc">
            <cfelse>
                <cfset table.order_by = "">
            </cfif>
          </cfif>


          <cfif not structKeyExists(table, "primary_keys")>
            <cfset table.primary_keys = []>
          </cfif>

          <cfif not structKeyExists(table, "indexes")>
            <cfset table.indexes = {}>
          </cfif>

          <cfif not structKeyExists(table, "foreign_keys")>
            <cfset table.foreign_keys = {}>
          </cfif>




          <!--- ADD SYSTEM FIELDS --->

            <cfif !structKeyExists(table.fields,'id')>
                <cfset table.fields['id'] = {
                                                "type": "uuid",
                                                "primary_key": true,
                                                "is_system": true,
                                                "default": 'uuid_generate_v7()'} />
            </cfif>

            <cfif !structKeyExists(table.fields,'label')>
                <cfset table.fields['label'] = {
                                                "type": "varchar",
                                                "is_system": true,
                                                "generation_expression": "#table.label_generation_expression#"} />
            </cfif>


            <cfif !structKeyExists(table.fields,'created_at')>
                <cfset table.fields['created_at'] = {
                                                        "type": "timestamptz",
                                                        "is_system": true,
                                                        "default": 'now()',
                                                        "html": {
                                                            "type": "input_date",
                                                            "display_format": "dd mmm yyyy"
                                                        }
                                                    }  />
            </cfif>


            <cfif !structKeyExists(table.fields,'last_updated_at')>
                <cfset table.fields['last_updated_at'] = {
                                                        "type": "timestamptz",
                                                        "is_system": true,
                                                        "default": 'now()',
                                                        "html": {
                                                            "type": "input_date",
                                                            "display_format": "dd mmm yyyy"
                                                        }
                                                    }  />
            </cfif>


            <cfif !structKeyExists(table.fields,'created_by')>
                <cfset table.fields['created_by'] = {
                                                        "type": "uuid",
                                                        "is_system": true,
                                                        "index": true,
                                                        "foreign_key_table": "moo_profile",
                                                        "foreign_key_field": "id",
                                                        "foreign_key_onDelete": "SET NULL",
                                                        "foreign_key_onUpdate": "NO ACTION",
                                                        "html": {
                                                            "type": "input_many_to_one"
                                                        }
                                                    }  />
            </cfif>


            <cfif !structKeyExists(table.fields,'last_updated_by')>
                <cfset table.fields['last_updated_by'] = {
                                                        "type": "uuid",
                                                        "is_system": true,
                                                        "index": true,
                                                        "foreign_key_table": "moo_profile",
                                                        "foreign_key_field": "id",
                                                        "foreign_key_onDelete": "SET NULL",
                                                        "foreign_key_onUpdate": "NO ACTION",
                                                        "html": {
                                                            "type": "input_many_to_one"
                                                        }
                                                    }  />
            </cfif>




            <cfloop collection="#table.fields#" item="field" index="field_name">

                <cfset field.name = field_name />


                <cfif !structKeyExists(field, "label")>
                    <cfset field.label = formatLabelFromFieldName(field_name) />
                </cfif>

                <cfif !structKeyExists(field, "type")>
                    <cfset field.type = "varchar" />
                </cfif>

                <cfif !structKeyExists(field, "cfsqltype")>
                    <cfset field.cfsqltype = "varchar" />
                </cfif>

                <cfif !structKeyExists(field, "searchable")>
                    <cfset field.searchable = false />
                </cfif>

                <cfif !structKeyExists(field, "condensed")>
                    <cfset field.condensed = false />
                </cfif>
                <cfif !structKeyExists(field, "sensitive")>
                    <cfset field.sensitive = false />
                </cfif>

                <cfif not structKeyExists(field, "is_nullable")>
                    <cfif structKeyExists(field, "nullable")>
                        <cfset field.is_nullable = field.nullable>
                    <cfelseif (field.primary_key?:false) OR arrayFind(table.primary_keys,field.name)>
                        <cfset field.is_nullable = false>
                    <cfelse>
                        <cfset field.is_nullable = true>
                    </cfif>
                </cfif>

                <cfif not structKeyExists(field, "default")>
                    <cfset field.default = ""> <!--- Implys no default set --->
                </cfif>

                <cfset field.sql_select_simple = "#table.table_name#.#field_name# AS #field_name#">

                <cfif !structKeyExists(field, "html")>
                    <cfset field.html = { }>
                </cfif>

                <!--- Explicit UI metadata must win over schema-derived control defaults.
                      Legacy and project table definitions commonly use html.type="file",
                      "email", "tel", etc. If we eagerly default uuid FK fields to combobox,
                      file fields such as moo_profile.profile_picture_id render as searchable
                      foreign-key dropdowns and call endpoints that do not exist. --->
                <cfif !structKeyExists(field.html, "control") AND len(field.html.type ?: "")>
                    <cfset field.html.control = "control_#replaceNoCase(field.html.type, 'input_', '')#" />
                </cfif>

                <cfswitch expression="#field.type#">
                    <cfcase value="numeric">
                        <cfset field.html.control = (field.html.control?:'control_number') />
                        <cfif not structKeyExists(field, "precision")>
                            <cfset field.precision = 18>
                        </cfif>

                        <cfif not structKeyExists(field, "scale")>
                            <cfset field.scale = 4>
                        </cfif>


                    </cfcase>

                    <cfcase value="varchar">
                        <cfset field.html.control = (field.html.control?:'control_text') />
                        <cfif not structKeyExists(field, "max_length")>
                            <cfset field.max_length = 255>
                        </cfif>
                    </cfcase>
                    <cfcase value="uuid">

                        <cfset field.cfsqltype = "other" />
                        <cfset field.foreign_key_field = (field.foreign_key_field?:'id') />
                        <cfset field.foreign_key_onDelete = (field.foreign_key_onDelete?:'NO ACTION') />
                        <cfset field.foreign_key_onUpdate = (field.foreign_key_onUpdate?:'NO ACTION') />

                        <cfif !(field.primary_key?:false)>
                            <cfset field.index = (field.index?:true) />
                            <cfset field.html.control = (field.html.control?:'control_combobox') />
                        </cfif>

                        <cfset field.sql_select_simple = "#table.table_name#.#field_name#::text as #field_name#">
                    </cfcase>

                    <cfcase value="jsonb">
                        <cfset field.html.control = (field.html.control?:'control_textarea') />
                        <cfset field.sql_select_simple = "#table.table_name#.#field_name#::jsonb as #field_name#">
                    </cfcase>

                    <cfcase value="relation">
                        <cfset field.html.control = (field.html.control?:'') />
                        <!--- not a field that gets deployed --->
                        <cfset field.sql_select_simple = "">
                    </cfcase>

                    <cfcase value="tsvector">
                        <cfset field.html.control = (field.html.control?:'') />
                        <cfset field.sql_select_simple = "">
                    </cfcase>

                    <cfcase value="date">
                        <cfset field.cfsqltype = "date" />
                        <cfset field.html.control = (field.html.control?:'control_date') />
                    </cfcase>

                    <cfcase value="timestamptz">
                        <cfset field.cfsqltype = "timestamp" />
                        <cfset field.html.control = (field.html.control?:'control_datetime') />
                    </cfcase>

                    <cfcase value="text">
                        <cfset field.html.control = (field.html.control?:'control_textarea') />
                    </cfcase>


                    <cfcase value="int2,int4,int8,smallserial,serial,bigserial">
                        <cfset field.cfsqltype = "numeric" />
                        <cfset field.html.control = (field.html.control?:'control_number') />
                    </cfcase>

                    <cfcase value="bool,boolean">
                        <cfset field.cfsqltype = "boolean" />
                        <cfset field.html.control = (field.html.control?:'control_switch') />
                    </cfcase>

                    <cfcase value="geometry">
                        <cfset field.html.control = (field.html.control?:'control_text') />
                        <cfset field.cfsqltype = "other" />

                        <!--- Set default geometry type if not specified --->
                        <cfif not structKeyExists(field, "geometry_type")>
                            <cfset field.geometry_type = "GEOMETRY">
                        </cfif>

                        <!--- Set default SRID if not specified --->
                        <cfif not structKeyExists(field, "srid")>
                            <cfset field.srid = 4326> <!--- WGS84 default --->
                        </cfif>

                        <!--- Validate geometry type --->
                        <cfset valid_geometry_types = "GEOMETRY,POINT,LINESTRING,POLYGON,MULTIPOINT,MULTILINESTRING,MULTIPOLYGON,GEOMETRYCOLLECTION">
                        <cfif not listFindNoCase(valid_geometry_types, field.geometry_type)>
                            <cfthrow message="Invalid geometry type: #field.geometry_type#. Valid types: #valid_geometry_types#">
                        </cfif>

                        <!--- Generate proper SQL select for geometry fields --->
                        <cfset field.sql_select_simple = "ST_AsText(#table.table_name#.#field_name#) as #field_name#">
                    </cfcase>

                    <!--- Keep backward compatibility for legacy point/polygon definitions --->
                    <cfcase value="point,polygon">
                        <cfset field.html.control = (field.html.control?:'control_text') />
                        <cfset field.cfsqltype = "other" />
                    </cfcase>

                    <cfcase value="many_to_many">
                        <cfset field.html.control = (field.html.control?:'control_combobox') />
                        <cfset field.html.multiple = true />
                        <cfif not structKeyExists(field, "foreign_key_field")>
                            <cfset field.foreign_key_field = "id">
                        </cfif>


                        <!--- We will populate this after all the primary tables are built so that we know all the fields that have been sanitized --->
                        <cfset field.sql_select_simple = "">



                        <cfset field.bridgingTableName = "#table.table_name#_#field.name#">
                        <cfset stBridgingTable = {
                            "table_name": field.bridgingTableName,
                            "fields": {
                                "primary_id": {
                                    "name": "primary_id",
                                    "label": "#formatLabelFromFieldName('primary_id')#",
                                    "type": "uuid",
                                    "foreign_key_table": table.table_name,
                                    "foreign_key_fields": "id",
                                    "is_nullable": false
                                },
                                "foreign_id": {
                                    "name": "foreign_id",
                                    "label": "#formatLabelFromFieldName('foreign_id')#",
                                    "type": "uuid",
                                    "foreign_key_table": field.foreign_key_table,
                                    "foreign_key_field": field.foreign_key_field,
                                    "is_nullable": false
                                },
                                "sequence": {
                                    "name": "sequence",
                                    "label": "Sequence",
                                    "type": "int4",
                                    "is_nullable": false,
                                    "default": 999
                                }
                            },
                            "indexes": {},
                            "primary_keys":["primary_id", "foreign_id"],
                            "foreign_keys": {
                                "fk_#field.bridgingTableName#_primary_id": {
                                    "field_name": "primary_id",
                                    "foreign_key_table": table.table_name,
                                    "foreign_key_field": "id",
                                    "onDelete": 'CASCADE',
                                    "onUpdate": 'NO ACTION'
                                },
                                "fk_#field.bridgingTableName#_foreign_id": {
                                    "field_name": "foreign_id",
                                    "foreign_key_table": field.foreign_key_table,
                                    "foreign_key_field": field.foreign_key_field,
                                    "onDelete": 'NO ACTION',
                                    "onUpdate": 'NO ACTION'
                                }
                            }
                        }>

                        <cfset codeSchemaOutput[field.bridgingTableName] = stBridgingTable>



                    </cfcase>

                    <cfdefaultcase>
                        <cfthrow message="Unsupported data type: #field.type#">
                    </cfdefaultcase>
                </cfswitch>


                <cfset field.sql_select_expanded = field.sql_select_simple>
                <cfset field.sql_select_condensed = field.sql_select_simple>


                <cfif structKeyExists(field, "index")>
                    <cfset indexName = "idx_#table.table_name#_#field.name#" />

                    <cfif isStruct(field.index)>
                        <cfset indexInfo = {
                            "name": indexName,
                            "type": field.index.type,
                            "fields": field.name,
                            "unique": field.index.unique?:false
                        } />

                        <cfif NOT structKeyExists(table.indexes, indexInfo.name)>
                            <cfset table.indexes[indexInfo.name] = indexInfo>
                        </cfif>
                    <cfelseif isBoolean(field.index) AND field.index>
                        <cfset indexInfo = {
                            "name": indexName,
                            "type": "btree",
                            "fields": field.name,
                            "unique": false
                        } />

                        <cfif NOT structKeyExists(table.indexes, indexInfo.name)>
                            <cfset table.indexes[indexInfo.name] = indexInfo>
                        </cfif>

                    </cfif>

                    <cfset structDelete(field, "index")>
                </cfif>


                <cfif (field.primary_key?:false)>

                    <cfif !arrayFind(table.primary_keys, field.name)>
                        <cfset arrayAppend(table.primary_keys, field.name)>
                    </cfif>

                    <cfset structDelete(field, "primary_key")>
                </cfif>


                <cfif field.type EQ "uuid" AND len(field.foreign_key_table?:'') AND len(field.foreign_key_field?:'') >
                    <cfset fkeyInfo = {
                        name: "fk_#table.table_name#_#field.name#",
                        field_name: field.name,
                        foreign_key_table: field.foreign_key_table,
                        foreign_key_field: field.foreign_key_field,
                        onDelete: field.foreign_key_onDelete,
                        onUpdate: field.foreign_key_onUpdate
                    }>

                    <cfset table.foreign_keys[fkeyInfo.name] = fkeyInfo>
                </cfif>



            </cfloop>



            <!--- Collect searchable fields for pg_trgm trigram search --->
            <!--- Table-level searchable_fields is the preferred API; field.searchable remains supported. --->
            <!--- JSONB fields are tracked but skipped when building the search_text column. --->
            <cfset declared_searchable_fields = table.searchable_fields ?: "" />
            <cfset table.searchable_fields = "" />
            <cfset searchable_field_configs = {} />

            <cfloop list="#declared_searchable_fields#" item="searchable_field_name">
                <cfset searchable_field_name = trim(searchable_field_name) />
                <cfif len(searchable_field_name)>
                    <cfif NOT structKeyExists(table.fields, searchable_field_name)>
                        <cfthrow message="Table #table.table_name# searchable_fields references unknown field: #searchable_field_name#" />
                    </cfif>
                    <cfif NOT listFindNoCase(table.searchable_fields, searchable_field_name)>
                        <cfset table.searchable_fields = listAppend(table.searchable_fields, searchable_field_name) />
                        <cfset searchable_field_configs[searchable_field_name] = { "field_type": table.fields[searchable_field_name].type } />
                    </cfif>
                </cfif>
            </cfloop>

            <cfloop collection="#table.fields#" item="field" index="field_name">
                <cfif structKeyExists(field, "searchable")>
                    <cfset include_searchable_field = false />

                    <cfif isBoolean(field.searchable)>
                        <cfset include_searchable_field = field.searchable />
                    <cfelseif isSimpleValue(field.searchable)>
                        <cfset include_searchable_field = len(trim(field.searchable)) GT 0 />
                    <cfelseif isStruct(field.searchable)>
                        <cfset include_searchable_field = true />
                    <cfelse>
                        <cfthrow message="Table #table.table_name# field #field_name# has unsupported searchable metadata." />
                    </cfif>

                    <cfif include_searchable_field AND NOT listFindNoCase(table.searchable_fields, field_name)>
                        <cfset table.searchable_fields = listAppend(table.searchable_fields, field_name) />
                        <cfset searchable_field_configs[field_name] = { "field_type": field.type } />
                    </cfif>
                </cfif>
            </cfloop>

            <cfif len(table.searchable_fields)>

                <cfset arguments.searchableTables[table.table_name] = {
                    'table_name': table.table_name,
                    'searchable_fields': table.searchable_fields,
                    'field_configs': searchable_field_configs
                } />

                <!--- Build search_text generated column using pg_trgm trigram similarity --->
                <!--- This concatenates all searchable fields into a single text column for efficient searching --->
                <!--- JSONB fields are skipped - use generated columns or searchable with json_path to extract text --->
                <cfset search_text_parts = [] />
                <cfloop list="#table.searchable_fields#" item="searchable_field_name">
                    <cfset field_config = searchable_field_configs[searchable_field_name] />
                    <cfset field_type = field_config.field_type ?: "varchar" />
                    <cfset field_def = table.fields[searchable_field_name] />

                    <!--- Skip JSONB fields - these should have separate generated columns for searching --->
                    <cfif field_type EQ "jsonb">
                        <cfcontinue />
                    </cfif>

                    <!--- If the field has a generation_expression, use that expression directly --->
                    <!--- This avoids PostgreSQL error: cannot reference another generated column --->
                    <cfif len(field_def.generation_expression?:'')>
                        <cfset arrayAppend(search_text_parts, "COALESCE((#field_def.generation_expression#)::text, '')") />
                    <cfelse>
                        <!--- Regular field - reference by name --->
                        <cfset arrayAppend(search_text_parts, "COALESCE(#searchable_field_name#::text, '')") />
                    </cfif>
                </cfloop>

                <!--- Only create search_text if we have searchable text fields --->
                <cfif arrayLen(search_text_parts)>
                    <!--- Build the generation expression: COALESCE(f1,'') || ' ' || COALESCE(f2,'') ... --->
                    <cfset search_text_expression = arrayToList(search_text_parts, " || ' ' || ") />

                    <!--- Add search_text as a generated column --->
                    <!--- All field properties must be set since this is added after the field processing loop --->
                    <cfset table.fields['search_text'] = {
                        "name": "search_text",
                        "label": "Search Text",
                        "type": "text",
                        "cfsqltype": "varchar",
                        "is_system": true,
                        "is_nullable": true,
                        "searchable": false,
                        "default": "",
                        "sql_select_simple": "",
                        "html": {},
                        "generation_expression": "#search_text_expression#"
                    } />

                    <!--- Add GIN index with gin_trgm_ops for trigram similarity search --->
                    <cfset table.indexes['#table.table_name#_search_trgm_idx'] = {
                        "name": "#table.table_name#_search_trgm_idx",
                        "type": "gin",
                        "fields": "search_text",
                        "unique": false
                    } />
                </cfif>

            </cfif>

            <!--- Build condensed/sensitive field lists for FK/M2M/relation SQL generation --->
            <cfset table._condensed_fields = "" />
            <cfset table._sensitive_fields = "" />
            <cfloop collection="#table.fields#" item="f" index="fn">
                <cfif f.condensed ?: false>
                    <cfset table._condensed_fields = listAppend(table._condensed_fields, fn) />
                </cfif>
                <cfif f.sensitive ?: false>
                    <cfset table._sensitive_fields = listAppend(table._sensitive_fields, fn) />
                </cfif>
            </cfloop>
            <!--- Ensure id is always in condensed --->
            <cfif len(table._condensed_fields) AND !listFindNoCase(table._condensed_fields, "id")>
                <cfset table._condensed_fields = listPrepend(table._condensed_fields, "id") />
            </cfif>

            <cfloop collection="#table.indexes#" item="index" index="index_name">
                <cfif !len(index.name?:'')>
                    <cfset index.name = index_name />
                </cfif>
                <cfif !len(index.type?:'')>
                    <cfset index.type = "btree" />
                </cfif>
                <cfif !len(index.unique?:'')>
                    <cfset index.unique = false />
                </cfif>

            </cfloop>



            <cfset codeSchemaOutput[table_key] = table />

        </cfloop>

        <!--- We need to populate all the many_to_many fields with their sql_select_simple not that all the primary tables are built so that we know all the fields that have been sanitized --->
        <cfloop collection="#arguments.codeSchemaInput#" item="table" index="table_key">
            <cfloop collection="#table.fields#" item="field" index="field_name">



                <cfif field.type EQ "many_to_many">

                    <!--- This helps us to convert the sql_select_simple values to be used in the json_agg function like:
                    SELECT json_agg(
                            json_build_object('id', #field.foreign_key_table#.id)
                        )
                     --->
                    <cfset json_build_object_field_list = "" />
                    <cfloop collection="#arguments.codeSchemaInput[field.foreign_key_table].fields#" item="foreign_table_field" index="foreign_table_field_name">
                        <cfif len(foreign_table_field['sql_select_simple'])>
                            <!--- Skip sensitive fields from expanded view --->
                            <cfif listFindNoCase(arguments.codeSchemaInput[field.foreign_key_table]._sensitive_fields ?: "", foreign_table_field_name)>
                                <cfcontinue />
                            </cfif>
                            <cfset json_build_object_field_sql_select_simple = rereplace(foreign_table_field['sql_select_simple'], "(?i)\bas\b.*", "", "ALL") /> <!--- Strip the "as fieldname" from the end of the sql_select_simple --->
                            <cfset json_build_object_field_list = listAppend(json_build_object_field_list, "'#foreign_table_field_name#', #json_build_object_field_sql_select_simple#") />
                        </cfif>
                    </cfloop>
                    <cfsavecontent variable="field.sql_select_expanded">
                    <cfoutput>
                        coalesce((
                            SELECT jsonb_agg(
                                jsonb_build_object(#json_build_object_field_list#)
                                ORDER BY #field.bridgingTableName#.sequence
                            )
                            FROM #field.bridgingTableName#
                            LEFT JOIN #field.foreign_key_table# ON #field.foreign_key_table#.id = #field.bridgingTableName#.foreign_id
                            WHERE #field.bridgingTableName#.primary_id = #table.table_name#.id

                        ),'[]')::jsonb AS #field_name#
                    </cfoutput>
                    </cfsavecontent>
                    <!--- Build condensed pairs from _condensed_fields, fall back to id,label --->
                    <cfset condensed_fields = arguments.codeSchemaInput[field.foreign_key_table]._condensed_fields ?: "" />
                    <cfif !len(condensed_fields)>
                        <cfset condensed_pairs = "'id',id,'label',label" />
                    <cfelse>
                        <cfset condensed_pairs = "" />
                        <cfloop list="#condensed_fields#" item="cf">
                            <cfset condensed_pairs = listAppend(condensed_pairs, "'#cf#',#cf#") />
                        </cfloop>
                    </cfif>
                    <cfsavecontent variable="field.sql_select_condensed">
                    <cfoutput>
                        coalesce((
                            SELECT jsonb_agg(
                                jsonb_build_object(#condensed_pairs#)
                                ORDER BY #field.bridgingTableName#.sequence
                            )
                            FROM #field.bridgingTableName#
                            LEFT JOIN #field.foreign_key_table# ON #field.foreign_key_table#.id = #field.bridgingTableName#.foreign_id
                            WHERE #field.bridgingTableName#.primary_id = #table.table_name#.id

                        ),'[]')::jsonb AS #field_name#
                    </cfoutput>
                    </cfsavecontent>

                </cfif>

                <!---  --->
                <cfif field.type EQ "uuid">


                     <cfif len(field.foreign_key_table?:'')>
                        <cftry>
                        <cfset json_build_object_field_list = "" />
                        <cfloop collection="#arguments.codeSchemaInput[field.foreign_key_table].fields#" item="foreign_table_field" index="foreign_table_field_name">

                            <cfif len(foreign_table_field['sql_select_simple'])>
                                <!--- when building a query for a uuid field, any many_to_many properties should be ignored and any uuid properties should just be the id and not the expanded.  --->

                                <cfif foreign_table_field.type EQ "many_to_many">
                                    <cfcontinue />
                                </cfif>

                                <!--- Skip sensitive fields from expanded view --->
                                <cfif listFindNoCase(arguments.codeSchemaInput[field.foreign_key_table]._sensitive_fields ?: "", foreign_table_field_name)>
                                    <cfcontinue />
                                </cfif>

                                <!--- <cfif foreign_table_field.type EQ "uuid">
                                    <cfset json_build_object_field_list = listAppend(json_build_object_field_list, "'#foreign_table_field_name#', #foreign_table_field_name#::text") />
                                    <cfcontinue />
                                </cfif> --->
                                <cfset json_build_object_field_sql_select_simple = foreign_table_field['sql_select_simple'] />
                                <cfset json_build_object_field_sql_select_simple = rereplace(json_build_object_field_sql_select_simple, "(?i)\bas\b.*", "", "ALL") /> <!--- Strip the "as fieldname" from the end of the sql_select_simple --->
                                <cfset json_build_object_field_sql_select_simple = replaceNoCase(json_build_object_field_sql_select_simple, "#field.foreign_key_table#.", "", "ALL") /> <!--- Strip the "[table_name]." from the beginning of the sql_select_simple. We need to do this in case we are related to iteslf --->
                                <cfset json_build_object_field_list = listAppend(json_build_object_field_list, "'#foreign_table_field_name#', #json_build_object_field_sql_select_simple#") />

                            </cfif>
                        </cfloop>
                        <cfsavecontent variable="field.sql_select_expanded">
                        <cfoutput>
                            coalesce((
                                SELECT json_build_object(#json_build_object_field_list#)
                                FROM #field.foreign_key_table# as sub
                                WHERE sub.id = #table.table_name#.#field.name#
                            ),'{}')::jsonb AS #field.name#
                        </cfoutput>
                        </cfsavecontent>
                        <!--- Build condensed pairs from _condensed_fields, fall back to id,label --->
                        <cfset condensed_fields = arguments.codeSchemaInput[field.foreign_key_table]._condensed_fields ?: "" />
                        <cfif !len(condensed_fields)>
                            <cfset condensed_pairs = "'id',id,'label',label" />
                        <cfelse>
                            <cfset condensed_pairs = "" />
                            <cfloop list="#condensed_fields#" item="cf">
                                <cfset condensed_pairs = listAppend(condensed_pairs, "'#cf#',#cf#") />
                            </cfloop>
                        </cfif>
                        <cfsavecontent variable="field.sql_select_condensed">
                        <cfoutput>
                            coalesce((
                                SELECT json_build_object(#condensed_pairs#)
                                FROM #field.foreign_key_table# as sub
                                WHERE sub.id = #table.table_name#.#field.name#
                            ),'{}')::jsonb AS #field.name#
                        </cfoutput>
                        </cfsavecontent>
                        <cfcatch>
                            <!--- May not exist yet. This often happens when deploying multiple tables at the same time --->
                            <!--- <cfdump var="#table#" label="#field_name#" expand="true">
                            <cfdump var="#cfcatch#" label="cfcatch" expand="true"><cfabort> --->
                        </cfcatch>
                        </cftry>


                    </cfif>
                </cfif>

                <cfif field.type EQ "relation">

                    <!--- This helps us to convert the sql_select_simple values to be used in the json_agg function like:
                    SELECT json_agg(
                            json_build_object('id', #field.foreign_key_table#.id)
                        )
                     --->

                     <cfif len(field.foreign_key_table?:'') AND  len(field.foreign_key_field?:'')>
                        <cftry>


                        <cfset json_build_object_field_list = "" />
                        <cfloop collection="#arguments.codeSchemaInput[field.foreign_key_table].fields#" item="foreign_table_field" index="foreign_table_field_name">

                            <cfif len(foreign_table_field['sql_select_simple'])>
                                <!--- Skip sensitive fields from expanded view --->
                                <cfif listFindNoCase(arguments.codeSchemaInput[field.foreign_key_table]._sensitive_fields ?: "", foreign_table_field_name)>
                                    <cfcontinue />
                                </cfif>
                                <cfset json_build_object_field_list = listAppend(json_build_object_field_list, foreign_table_field['sql_select_simple']) />
                            </cfif>

                        </cfloop>


                        <cfsavecontent variable="field.sql_select_expanded">
                            <cfoutput>
                            coalesce((
                                SELECT jsonb_agg(to_jsonb(sq.*))
                                FROM (
                                    SELECT #json_build_object_field_list#
                                    FROM #field.foreign_key_table#
                                    WHERE #field.foreign_key_table#.#field.foreign_key_field# = #table.table_name#.id
                                    ORDER BY #arguments.codeSchemaInput[field.foreign_key_table].order_by#
                                ) AS sq
                            ),'[]')::jsonb AS #field_name#
                        </cfoutput>
                        </cfsavecontent>
                        <!--- Build condensed field list from _condensed_fields, fall back to id,label --->
                        <cfset condensed_fields = arguments.codeSchemaInput[field.foreign_key_table]._condensed_fields ?: "" />
                        <cfif !len(condensed_fields)>
                            <cfset condensed_field_list = "id,label" />
                        <cfelse>
                            <cfset condensed_field_list = condensed_fields />
                        </cfif>
                        <cfsavecontent variable="field.sql_select_condensed">
                            <cfoutput>
                            coalesce((
                                SELECT jsonb_agg(to_jsonb(sq.*))
                                FROM (
                                    SELECT #condensed_field_list#
                                    FROM #field.foreign_key_table#
                                    WHERE #field.foreign_key_table#.#field.foreign_key_field# = #table.table_name#.id
                                    ORDER BY #arguments.codeSchemaInput[field.foreign_key_table].order_by#
                                ) AS sq
                            ),'[]')::jsonb AS #field_name#
                        </cfoutput>
                        </cfsavecontent>
                        <!--- <cfdump var="#json_build_object_field_list#" label="" expand="true">
                        <cfdump var="#field.sql_select_expanded#" label="" expand="true">

                        <cfdump var="#field.sql_select_expanded_v2#" label="" expand="true">

                        <cfabort> --->
                        <cfcatch>
                            <cfdump var="#table#" label="#field_name#" expand="true">
                            <cfdump var="#cfcatch#" label="cfcatch" expand="true"><cfabort>
                        </cfcatch>
                        </cftry>

                    </cfif>
                </cfif>

            </cfloop>
        </cfloop>


        <cfreturn codeSchemaOutput>
    </cffunction>

</cfcomponent>
