//
// Checks that the places that describe the same thing agree: the root schema and the stage schemas, the pinned
// versions, the parameter names of the docs and the columns of the samplesheet. Each function returns a list of
// problems, empty when the places agree.
//

include { schemaProperties } from './schema_params'

// Every parameter of a stage is the same parameter of the root pipeline, as --x or --enable_x: same type, default,
// choices and limits. stage_only lists the parameters that the root pipeline has no counterpart for, such as the
// channel inputs of a stage. A boolean that is false by default has no default in the schema. The keys that make
// nf-schema check a file (exists, mimetype, schema) are not compared: a stage schema only prints the help
def rootStageDiff(root_json, stage_json, stage_only) {
    def root = schemaProperties(new File(root_json).text)
    def stage = schemaProperties(new File(stage_json).text)
    def problems = []
    stage.each { name, prop ->
        // --samplesheet is the common input of the stages, which BioVAT calls --input
        if ( name in [ 'help', 'helpFull', 'showHidden', 'samplesheet' ] ) {
            return
        }
        def root_name = root.containsKey(name) ? name : "enable_${name}".toString()
        if ( !root.containsKey(root_name) ) {
            if ( !(name in stage_only) ) {
                problems << "--${name} of the stage has no counterpart in the root schema (--${name} or --enable_${name}) and is not listed as stage only".toString()
            }
            return
        }
        if ( name in stage_only ) {
            problems << "--${name} is listed as stage only, but the root schema has --${root_name}".toString()
        }
        def root_prop = root[root_name]
        [ 'type', 'enum', 'pattern', 'minimum', 'maximum', 'format' ].each { key ->
            if ( prop.get(key) != root_prop.get(key) ) {
                problems << "--${name}: ${key} is ${prop.get(key)} in the stage and ${root_prop.get(key)} in the root (--${root_name})".toString()
            }
        }
        def stage_default = prop.get('default') == false ? null : prop.get('default')
        def root_default = root_prop.get('default') == false ? null : root_prop.get('default')
        if ( stage_default != root_default ) {
            problems << "--${name}: default is ${prop.get('default')} in the stage and ${root_prop.get('default')} in the root (--${root_name})".toString()
        }
    }
    return problems
}

// The nf-schema plugin is pinned in three configs and nf-test in the CI workflow and in pixi.toml
def pinsDiff(project_dir) {
    def problems = []
    def versions = [ 'nextflow.config', 'conf/stage.config', 'examples/chaining/nextflow.config' ].collectEntries { path ->
        def m = new File("${project_dir}/${path}").text =~ /nf-schema@([\d.]+)/
        [ (path): m.find() ? m.group(1) : null ]
    }
    if ( versions.values().any { v -> v == null } || (versions.values() as Set).size() != 1 ) {
        problems << "nf-schema is not pinned to one version in nextflow.config, conf/stage.config and examples/chaining/nextflow.config: ${versions}".toString()
    }
    def ci_match = new File("${project_dir}/.github/workflows/nf-test.yml").text =~ /NFT_VER:\s*"([\d.]+)"/
    def pixi_match = new File("${project_dir}/pixi.toml").text =~ /nf-test\s*=\s*">=([\d.]+)/
    def ci_version = ci_match.find() ? ci_match.group(1) : null
    def pixi_version = pixi_match.find() ? pixi_match.group(1) : null
    if ( ci_version == null || ci_version != pixi_version ) {
        problems << "nf-test is ${ci_version} in the CI workflow and ${pixi_version} in pixi.toml".toString()
    }
    return problems
}

// The parameters that the README and docs/usage.md name with -- and the keys of assets/nf-params.yml exist in the root
// schema or in the schema of a stage.
// other_flags lists the -- words that are flags of other tools or of Nextflow
def docNamesDiff(project_dir, other_flags) {
    def schema_jsons = [ "${project_dir}/nextflow_schema.json" ] + new File("${project_dir}/pipelines").listFiles().collect { dir -> "${dir}/nextflow_schema.json".toString() }.findAll { path -> new File(path).exists() }
    def known = schema_jsons.collectMany { path -> schemaProperties(new File(path).text).keySet() as List } as Set
    def problems = []
    [ 'README.md', 'docs/usage.md' ].each { path ->
        def names = (new File("${project_dir}/${path}").text =~ /(?<![\w-])--([a-zA-Z]\w*)/).collect { m -> m[1] } as Set
        names.findAll { n -> !(n in known) && !(n in other_flags) }.each { n ->
            problems << "${path} names --${n}, which is not a parameter in any schema".toString()
        }
    }
    (new File("${project_dir}/assets/nf-params.yml").text =~ /(?m)^#?\s*([A-Za-z_]\w*):/).collect { m -> m[1] }.each { key ->
        if ( !(key in known) ) {
            problems << "assets/nf-params.yml has the key ${key}, which is not a parameter in any schema".toString()
        }
    }
    return problems
}

// The columns of the samplesheet: assets/schema_input.json is the source. The column table of docs/usage.md lists the
// same columns, the example header of the README and docs/usage.md uses only them, and the Sample record of
// types/samplesheet.nf has no other fields. record_not_in_schema lists the columns the record leaves out on purpose
def samplesheetColumnsDiff(project_dir, record_not_in_schema) {
    def problems = []
    def schema = new groovy.json.JsonSlurper().parseText(new File("${project_dir}/assets/schema_input.json").text)
    def columns = schema.items.properties.keySet() as List
    def usage = new File("${project_dir}/docs/usage.md").text
    def table = (usage =~ /(?m)^\| `(\w+)`\s*\|/).collect { m -> m[1] }
    def first_table = table.takeWhile { c -> c != 'population' }
    if ( (first_table as Set) != (columns as Set) ) {
        problems << "docs/usage.md lists the columns ${first_table} and assets/schema_input.json has ${columns}".toString()
    }
    [ 'README.md', 'docs/usage.md' ].each { path ->
        def header = (new File("${project_dir}/${path}").text =~ /(?m)^(sample,library_id,[\w,]+)$/).collect { m -> m[1].split(',') as List }
        header.each { h ->
            def unknown = h - columns
            if ( !unknown.isEmpty() ) {
                problems << "${path} has the samplesheet header ${h.join(',')}, with columns that the schema does not have: ${unknown}".toString()
            }
        }
        if ( header.isEmpty() ) {
            problems << "${path} has no samplesheet header example".toString()
        }
    }
    def record = new File("${project_dir}/types/samplesheet.nf").text =~ /(?s)record Sample \{(.*?)\}/
    def fields = record.find() ? (record.group(1) =~ /(?m)^\s*(\w+)\s*:/).collect { m -> m[1] } : []
    if ( ((fields as Set) + (record_not_in_schema as Set)) != (columns as Set) ) {
        problems << "The Sample record has the fields ${fields}, the schema the columns ${columns} (left out on purpose: ${record_not_in_schema})".toString()
    }
    return problems
}
