//
// Runs the --help of a pipeline script and returns the problems with its message: every --flag that the message names
// is declared in the schema of the pipeline, and --help <parameter> describes a parameter. nf-test does not capture
// the help message of a pipeline test, so the pipeline is run as a process of its own. A flag of another tool that
// a description names, such as --group-samples of bcftools, has a hyphen and is not checked. The tools are on the PATH
// of nf-test, as nf-test is run with pixi
//

def runHelp(script, args) {
    def command = [ 'nextflow', 'run', script, '-output-format', 'none' ] + args
    def process = new ProcessBuilder(command).redirectErrorStream(true).start()
    def output = process.inputStream.text
    process.waitFor()
    return [ exit: process.exitValue(), output: output.replaceAll(/\u001B\[[0-9;]*m/, '') ]
}

def helpFlagsDiff(script, schema_json, parameter) {
    def problems = []
    def declared = [] as Set
    new groovy.json.JsonSlurper().parseText(new File(schema_json).text).get('$defs', [:]).each { _group, definition ->
        declared.addAll(definition.get('properties', [:]).keySet())
    }
    def help = runHelp(script, [ '--help' ])
    if ( help.exit != 0 ) {
        problems << "${script} --help exits with ${help.exit}".toString()
    }
    def flags = (help.output =~ /(?<![\w-])--([a-zA-Z]\w*)(?![\w-])/).collect { m -> m[1] } as Set
    if ( flags.isEmpty() ) {
        problems << "${script} --help names no flag".toString()
    }
    flags.findAll { flag -> !(flag in declared) }.each { flag ->
        problems << "${script} --help names --${flag}, which is not in its schema".toString()
    }
    def one = runHelp(script, [ '--help', parameter ])
    if ( one.exit != 0 || !one.output.contains("--${parameter}") ) {
        problems << "${script} --help ${parameter} exits with ${one.exit} and does not describe --${parameter}".toString()
    }
    return problems
}
