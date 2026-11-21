<cfcomponent>
    <!--- A stored file published at an address on one of the project's sites, because a field of a record publishes its
          files (a table definition's publish setting; docs/object-storage.md: Publishing a table's files). Written only
          by published_files (syncRecord, syncAll): one row per address, saying which record, field and file put it there
          and which stored copy it is, so a save copies only what changed. Pages read it to link a file at its address,
          once its path is set. The row is claimed before the copy and kept until the copy is gone, so no public copy is
          ever without one; its unique object_key settles which record an address belongs to.

          Not in tables/: a project gets this table only when one of its fields publishes files (lib/db.cfc, init). --->
    <cffunction name="init">
        <cfset this.definition = {
            "title": "Published File",
            "title_plural": "Published Files",
            "label_generation_expression": "COALESCE(address::text, id::text)",
            "order_by": "site, address",
            "fields": {
                <!--- The key in the store: public/<site>/<address without its leading slash>. --->
                "object_key": { "type": "varchar", "max_length": 1024, "nullable": false, "index": { "type": "btree", "unique": true } },
                "site": { "type": "varchar", "max_length": 63, "nullable": false, "condensed": true },
                <!--- The address on the site: /datasheets/product.pdf. --->
                "address": { "type": "varchar", "max_length": 1024, "nullable": false, "condensed": true },
                <!--- The record and field that publish it. --->
                "table_name": { "type": "varchar", "max_length": 63, "nullable": false, "index": true },
                "record_id": { "type": "uuid", "nullable": false, "index": true },
                "field": { "type": "varchar", "max_length": 63, "nullable": false },
                <!--- The file, and the stored copy it was published from: another path means the file was replaced. Empty
                      while the address is being published or unpublished: pages link an address only once its path is
                      set, and an empty one is finished by the next sync. --->
                "moo_file_id": { "type": "uuid", "nullable": false, "index": true },
                "path": { "type": "varchar", "max_length": 2048, "nullable": false },
                <!--- The copy's ETag, as the store gave it: syncAll republishes a copy that is missing or not this one. --->
                "etag": { "type": "varchar", "max_length": 200 }
            }
        } />
        <cfreturn this />
    </cffunction>
</cfcomponent>
