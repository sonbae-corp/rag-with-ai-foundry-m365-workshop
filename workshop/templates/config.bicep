var conf = loadYamlContent('config.yaml')

@export()
var global = conf.global

@export()
var tenant = conf.tenants[subscription().tenantId]

@export()
var version = loadJsonContent('./version.json').version
