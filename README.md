# Kong plugin for WSDL rewrite

# About

This Kong 🦍 plugin is for concept purposes and not for production use. The plugin requests
wsdl document calls to backend systems and rewrite the urls to point to the Kong Gateway instead
of the original backend host. This is also done for the embedded xsds.

## Configuration parameters

|FORM PARAMETER|REQUIRED|DEFAULT|DESCRIPTION|
|:----|:------|:------|:------|
|config.Secret|false|MyBestSecret|for future extension|
|config.cache_ttl|false|3600|Time in seconds we cache the transformed WSDL exchange|
|config.ExternalHostNameUrl|false||required if the gateway is not able to get the hostname e.g. behind LB|

## Additional libraries needed
none

