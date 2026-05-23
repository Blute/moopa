<cfcomponent displayName="registry_row_merger" output="false" hint="Merges duplicate route registry rows revealed by route URL canonicalization.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfreturn this />
    </cffunction>


    <cffunction name="mergeConflictsForUrl" access="public" returntype="void" output="false">
        <cfargument name="target_route_id" type="string" required="true" />
        <cfargument name="app_name" type="string" required="true" />
        <cfargument name="url" type="string" required="true" />

        <cfquery name="local.qConflictingRoutes">
            SELECT id::text AS id
            FROM moo_route
            WHERE app_name = <cfqueryparam cfsqltype="varchar" value="#arguments.app_name#" />
              AND url = <cfqueryparam cfsqltype="varchar" value="#arguments.url#" />
              AND id <> <cfqueryparam cfsqltype="other" value="#arguments.target_route_id#" />
        </cfquery>

        <cfloop query="local.qConflictingRoutes">
            <cfset merge(arguments.target_route_id, local.qConflictingRoutes.id) />
        </cfloop>
    </cffunction>


    <cffunction name="merge" access="public" returntype="void" output="false">
        <cfargument name="target_route_id" type="string" required="true" />
        <cfargument name="duplicate_route_id" type="string" required="true" />

        <cfif arguments.target_route_id EQ arguments.duplicate_route_id>
            <cfreturn />
        </cfif>

        <cfquery name="local.qMergeDuplicateRouteEndpoints">
            WITH endpoint_matches AS (
                SELECT duplicate_endpoint.id AS duplicate_endpoint_id,
                       target_endpoint.id AS target_endpoint_id
                FROM moo_route_endpoint duplicate_endpoint
                INNER JOIN moo_route_endpoint target_endpoint
                    ON target_endpoint.route_id = <cfqueryparam cfsqltype="other" value="#arguments.target_route_id#" />
                   AND target_endpoint.name = duplicate_endpoint.name
                WHERE duplicate_endpoint.route_id = <cfqueryparam cfsqltype="other" value="#arguments.duplicate_route_id#" />
            ), moved_permissions AS (
                UPDATE moo_route_permission permission
                SET route_id = <cfqueryparam cfsqltype="other" value="#arguments.target_route_id#" />,
                    endpoint_id = endpoint_matches.target_endpoint_id
                FROM endpoint_matches
                WHERE permission.route_id = <cfqueryparam cfsqltype="other" value="#arguments.duplicate_route_id#" />
                  AND permission.endpoint_id = endpoint_matches.duplicate_endpoint_id
                RETURNING permission.id
            ), deleted_duplicate_endpoints AS (
                DELETE FROM moo_route_endpoint endpoint
                USING endpoint_matches
                WHERE endpoint.id = endpoint_matches.duplicate_endpoint_id
                RETURNING endpoint.id
            ), adopted_endpoints AS (
                UPDATE moo_route_endpoint
                SET route_id = <cfqueryparam cfsqltype="other" value="#arguments.target_route_id#" />
                WHERE route_id = <cfqueryparam cfsqltype="other" value="#arguments.duplicate_route_id#" />
                RETURNING id
            )
            UPDATE moo_route_permission
            SET route_id = <cfqueryparam cfsqltype="other" value="#arguments.target_route_id#" />
            WHERE route_id = <cfqueryparam cfsqltype="other" value="#arguments.duplicate_route_id#" />
        </cfquery>

        <cfquery name="local.qMergeDuplicateRouteRoles">
            INSERT INTO moo_route_roles (primary_id, foreign_id)
            SELECT <cfqueryparam cfsqltype="other" value="#arguments.target_route_id#" />, foreign_id
            FROM moo_route_roles
            WHERE primary_id = <cfqueryparam cfsqltype="other" value="#arguments.duplicate_route_id#" />
            ON CONFLICT DO NOTHING;

            DELETE FROM moo_route_roles
            WHERE primary_id = <cfqueryparam cfsqltype="other" value="#arguments.duplicate_route_id#" />
        </cfquery>

        <cfquery name="local.qMergeDuplicateRouteProfiles">
            INSERT INTO moo_route_profiles (primary_id, foreign_id)
            SELECT <cfqueryparam cfsqltype="other" value="#arguments.target_route_id#" />, foreign_id
            FROM moo_route_profiles
            WHERE primary_id = <cfqueryparam cfsqltype="other" value="#arguments.duplicate_route_id#" />
            ON CONFLICT DO NOTHING;

            DELETE FROM moo_route_profiles
            WHERE primary_id = <cfqueryparam cfsqltype="other" value="#arguments.duplicate_route_id#" />
        </cfquery>

        <cfquery name="local.qMergeDuplicateRouteReferrers">
            INSERT INTO moo_route_referrers (primary_id, foreign_id)
            SELECT <cfqueryparam cfsqltype="other" value="#arguments.target_route_id#" />, foreign_id
            FROM moo_route_referrers
            WHERE primary_id = <cfqueryparam cfsqltype="other" value="#arguments.duplicate_route_id#" />
            ON CONFLICT DO NOTHING;

            DELETE FROM moo_route_referrers
            WHERE primary_id = <cfqueryparam cfsqltype="other" value="#arguments.duplicate_route_id#" />;

            UPDATE moo_route_referrers
            SET foreign_id = <cfqueryparam cfsqltype="other" value="#arguments.target_route_id#" />
            WHERE foreign_id = <cfqueryparam cfsqltype="other" value="#arguments.duplicate_route_id#" />
        </cfquery>

        <cfquery name="local.qDeleteDuplicateRoute">
            DELETE FROM moo_route
            WHERE id = <cfqueryparam cfsqltype="other" value="#arguments.duplicate_route_id#" />
        </cfquery>
    </cffunction>

</cfcomponent>
