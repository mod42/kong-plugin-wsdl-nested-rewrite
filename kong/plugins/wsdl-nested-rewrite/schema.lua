local typedefs = require "kong.db.schema.typedefs"

local PLUGIN_NAME = "wsdl-nested-rewrite"

local schema = {
    name = PLUGIN_NAME,
    fields = {{
        consumer = typedefs.no_consumer
    }, {
        protocols = typedefs.protocols_http
    }, {
        config = {
            type = "record",
            fields = {{
                secret = {
                    type = "string",
                    default = "MyBestSecret",
                    required = true
                }
            }, {
                cache_ttl = {
                    type = "integer",
                    default = 3600,
                    required = true
                }
            }, {
                external_host_name_url = {
                    type = "string",
                    required = false
                }
            }},
            entity_checks = {}
        }
    }}
}