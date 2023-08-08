local aes = require 'resty.aes'
local str = require "resty.string"

local plugin = {
    PRIORITY = 1010, -- set the plugin priority, which determines plugin execution order
    VERSION = "0.1"
}

function plugin:access(plugin_conf)

    local originalReqPath = kong.request.get_path()
    local arg = kong.request.get_query_arg("orig")

    if arg then
        local newPath = ngx.decode_base64(arg)
        -- original endpoint is base64 encoded in the URL
        kong.service.request.set_path(newPath)
        kong.service.request.set_raw_query("")
        kong.log.info("newPath: " .. newPath)

    end
   -- kong.service.request.set_header("accept-encoding", "gzip;q=0")
end

-- this will only check if there is a cached version - otherwise the actual work will be later done on response phase
function check_cache(plugin_conf)
    return nil
end

function plugin:header_filter(plugin_conf)
    if kong.response.get_source() == "exit" then
        kong.log("There was an early exit while processing the request")
        return
    end
    kong.response.clear_header("Content-Length")
    -- kong.response.clear_header("Content-Encoding")
end

function plugin:body_filter(plugin_conf)
    kong.log("Start body_filter")
    if kong.response.get_source() == "exit" then
        kong.log("There was an early exit while processing the request")
        return
    end
    local opts = {
        ttl = plugin_conf.cache_ttl
    }
    local body = kong.response.get_raw_body()
    if body == nil then
        kong.log("Abbruch")
        return
    end
    kong.log("Start body work")
    local wsdl_cache_key = generate_cache_key(kong.request.get_path())

    local rewritten_wsdl, err = kong.cache:get(wsdl_cache_key, opts, rewrite_wsdl, plugin_conf, body)
    if err then
        kong.log.info(err)
    end
    kong.response.set_raw_body(rewritten_wsdl)
end

function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            if type(k) ~= 'number' then
                k = '"' .. k .. '"'
            end
            s = s .. '[' .. k .. '] = ' .. dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

function getExternalHost()
    local externalHostNameUrl = plugin_conf.external_host_name_url
    if externalHostNameUrl == nil then
        externalHostNameUrl = kong.request.get_scheme() .. "://" .. kong.request.get_host() .. ":" ..
                                  kong.request.get_port()
    end
    return externalHostNameUrl
end

function rewrite_wsdl(plugin_conf, body)
    local xmlua = require("xmlua")
    local str = require "resty.string"
    -- Parses XML
    if body then
        local soapMessage = xmlua.XML.parse(body)
        -- Find all <xsd:import> elements using the xpath expression
        local xsd_import_elements = soapMessage:search("//xsd:import", namespaces)

        -- local externalHostNameUrl = getExternalHost()
        local externalHostNameUrl = plugin_conf.external_host_name_url
        if externalHostNameUrl == nil then
            externalHostNameUrl = kong.request.get_scheme() .. "://" .. kong.request.get_host() .. ":" ..
                                      kong.request.get_port()
        end

        local queue = require "kong.tools.queue"

        -- Loop over each <xsd:import> element
        for _, xsd_import_element in ipairs(xsd_import_elements) do
            local namespace = xsd_import_element:get_attribute("namespace")
            local schemaLocation = xsd_import_element:get_attribute("schemaLocation")
            kong.log("start with: " .. namespace)
            kong.log.debug("Namespace: " .. namespace)
            kong.log.debug("Schema Location:" .. schemaLocation)
            local searchString = "/namespace/"
            local startIndex, endIndex = namespace:find(searchString)
            local namespace_name = namespace:sub(endIndex + 1)
            local ServiceStart = schemaLocation:find("/service")
            local namespacePath = schemaLocation:sub(ServiceStart)
            -- store the original endpoint in a query parameter
            local baseOrigLocation = ngx.encode_base64(namespacePath)
            kong.log("encrypted " .. baseOrigLocation)

            if string.find(kong.request.get_path(), "/namespace/") then
                local rawPath = kong.request.get_raw_path()
                local startIndex, endIndex = rawPath:find(searchString)
                local newNamespacePath = rawPath:sub(0, endIndex)

                kongSchemaLocation = externalHostNameUrl .. newNamespacePath .. namespace_name .. "?orig=" ..
                                         baseOrigLocation
                kong.log("kongSchemaLocation: " .. kongSchemaLocation)
            else
                kongSchemaLocation = externalHostNameUrl .. kong.request.get_raw_path() .. "/namespace/" ..
                                         namespace_name .. "?orig=" .. baseOrigLocation

                local xsd_soapbind_elements = soapMessage:search("//soapbind:address", namespaces)
                -- Loop over each <soapbind:address> element
                for _, xsd_soapbind_element in ipairs(xsd_soapbind_elements) do
                    local location = xsd_soapbind_element:get_attribute("location")

                    kong.log.debug("Location: " .. location)
                    xsd_soapbind_element:set_attribute("location", externalHostNameUrl .. kong.request.get_raw_path())

                end
            end
            -- local kongSchemaLocation = externalHostNameUrl .. kong.request.get_raw_path() .. "/namespace/" .. namespace_name
            xsd_import_element:set_attribute("schemaLocation", kongSchemaLocation)
            -- xsd_import_element:set_attribute("origSchemaLocation", schemaLocation )

            local handler_conf = {
                kongSchemaLocation = kongSchemaLocation,
                origSchemaLocation = schemaLocation
            }

            local queue_conf = {
                name = "schemaUpdater",
                log_tag = "wsdl-nested-rewrite-queue",
                max_batch_size = 10,
                max_entries = 10000,
                max_bytes = nil,
                max_coalescing_delay = 1,
                initial_retry_delay = 0.01,
                max_retry_time = 60,
                max_retry_delay = 60
            }

            -- kong.log.debug("Adding " .. kongSchemaLocation .. " to queue")
            local ok, err = queue.enqueue(queue_conf, update_children, plugin_conf, handler_conf)
            if not ok then
                kong.log.err("Failed to enqueue log entry to log server: ", err)
            end
        end

        return soapMessage:to_xml()
    else
        return nil, "No body in response from service"
    end

end

function update_children(conf, entries)
    local http = require "resty.http"
    for _, entry in ipairs(entries) do
        kong.log.debug("wsdl Pinging " .. entry.kongSchemaLocation)
        local httpc = http.new()
        -- local res, err = httpc:request_uri(conf.kongSchemaLocation, {
        local res, err = httpc:request_uri("http://localhost:8000/empty", {
            method = "GET",
            headers = {
                --["accept-encoding"] = "gzip;q=0"
            },
            query = {},
            keepalive_timeout = 60,
            keepalive_pool = 10
        })
        if err then
            return nil, err
        end
        if not res.status == 200 then
            return nil, "Invalid wsdl data status code received: " .. res.status
        end
    end
    return true
end

function generate_cache_key(path)
    local resty_md5 = require "resty.md5"
    local md5 = resty_md5:new()
    if not md5 then
        kong.log.error("failed to create md5 object")
        return
    end

    local ok = md5:update(path)
    if not ok then
        kong.log.error("failed to create md5 object")
        return
    end

    local digest = md5:final()
    local wsdl_cache_key = "wsdl_" .. ngx.encode_base64(digest)
    return wsdl_cache_key
end

return plugin
