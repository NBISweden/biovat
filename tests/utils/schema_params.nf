//
// Compares the typed params block of a pipeline script with its nextflow_schema.json.
// nf-core pipelines schema build cannot do this, as it reads the params from `nextflow config`.
// The function returns a list of problems, empty when the schema matches the params block.
//

// With `strict` the schema must not document parameters that the params block does not declare. The root
// pipeline is not strict: its config declares parameters too, such as outdir and the institutional config options.
// `ignore` lists parameters left out of the comparison.
def schemaParamsDiff(main_nf, schema_json, strict, ignore) {
    def declared = paramsBlock(new File(main_nf).text)
    def documented = schemaProperties(new File(schema_json).text)
    def problems = []

    declared.each { name, param ->
        if ( name in ignore ) {
            return
        }
        def prop = documented[name]
        if ( prop == null ) {
            problems << "--${name} is in the params block but not in the schema".toString()
            return
        }
        def types = prop.type instanceof List ? prop.type : [ prop.type ]
        if ( !(param.json_type in types) ) {
            problems << "--${name} is ${param.type} in the params block (${param.json_type}) and ${types} in the schema".toString()
        }
        if ( param.has_default && prop.containsKey('default') && prop['default'] != param.value ) {
            problems << "--${name} defaults to ${param.value} in the params block and ${prop['default']} in the schema".toString()
        }
        // A boolean that is false by default has no default in the schema, as in the nf-core template
        def false_flag = param.json_type == 'boolean' && param.value == false
        if ( param.has_default && !prop.containsKey('default') && !false_flag ) {
            problems << "--${name} defaults to ${param.value} in the params block and has no default in the schema".toString()
        }
        if ( !param.has_default && prop.containsKey('default') ) {
            problems << "--${name} has no default in the params block and defaults to ${prop['default']} in the schema".toString()
        }
    }
    if ( strict ) {
        documented.keySet().each { name ->
            if ( !declared.containsKey(name) && !(name in ignore) ) {
                problems << "--${name} is in the schema but not in the params block".toString()
            }
        }
    }
    return problems
}

// name -> [type, json_type, has_default, value], from the lines of the params block
def paramsBlock(text) {
    def result = [:]
    def inside = false
    text.readLines().each { line ->
        if ( !inside ) {
            inside = line.startsWith('params {')
            return
        }
        if ( line.startsWith('}') ) {
            inside = false
            return
        }
        def m = line =~ /^\s+(\w+)\s*:\s*([^=\/]+?)\s*(?:=\s*('[^']*'|"[^"]*"|\S+))?\s*(?:\/\/.*)?$/
        if ( !m.matches() ) {
            return
        }
        def type = m.group(2).trim()
        def base = type.replaceAll(/\?$/, '')
        def json_type = base == 'Boolean' ? 'boolean' : base == 'Integer' ? 'integer' : base in [ 'Float', 'Number' ] ? 'number' : 'string'
        def raw = m.group(3)
        def value = raw
        if ( raw != null && raw.length() >= 2 && raw[0] in [ "'", '"' ] ) {
            value = raw.substring(1, raw.length() - 1)
        }
        else if ( json_type == 'boolean' && raw != null ) {
            value = raw == 'true'
        }
        else if ( json_type == 'integer' && raw != null ) {
            value = raw.toInteger()
        }
        result[m.group(1)] = [ type: type, json_type: json_type, has_default: raw != null, value: value ]
    }
    return result
}

// name -> property of the schema, over all the groups
def schemaProperties(text) {
    def schema = new groovy.json.JsonSlurper().parseText(text)
    def result = [:]
    schema.get('$defs', [:]).each { group, definition ->
        definition.get('properties', [:]).each { name, prop ->
            result[name] = prop
        }
    }
    return result
}
