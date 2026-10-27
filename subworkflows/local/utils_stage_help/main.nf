nextflow.enable.types = true

//
// Shared pieces of the stage pipelines: the --help message and the input check.
// STAGE_HELP prints the help message of a stage pipeline and exits.
// Stage pipelines call it from their entry workflow, so --help works when a stage is run on its own.
// When the stage is included by another pipeline, help is false and nothing happens.
//

include { paramsHelp } from 'plugin/nf-schema'

workflow STAGE_HELP {

    take:
    help             : Boolean // show help message
    help_full        : Boolean // show full help message
    parameters_schema: String  // path to the JSON schema of the stage parameters
    command          : String  // an example command of the stage

    main:
    if ( help || help_full ) {
        def message = paramsHelp(
            [
                command         : command,
                fullHelp        : help_full,
                parametersSchema: parameters_schema,
            ],
            ""
        )
        log.info message
        exit(0, '')
    }
}

//
// Check that a stage got its input from exactly one of the samplesheet or the records param (named by given_name)
//
def checkStageInput(samplesheet, given, given_name: String) {
    if ( samplesheet && given ) {
        error "Provide either --samplesheet or --${given_name}, not both"
    }
    if ( !samplesheet && !given ) {
        error "Missing required parameter --samplesheet"
    }
}
