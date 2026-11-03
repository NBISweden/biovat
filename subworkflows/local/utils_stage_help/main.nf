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

//
// Stop with a message from inside an operator closure. Nextflow reports an error raised there as "Unexpected error
// [InvocationTargetException]" and leaves the message in .nextflow.log, so the message is logged first
//
def stageError(message) {
    log.error(message)
    error message
}

//
// stageError with the red ERROR prefix of the messages about the input
//
def inputError(message) {
    stageError("\033[0;91mERROR\033[0m: ${message}")
}

//
// Log the message of the root cause of an exception caught in an operator closure, where Nextflow wraps the error
// in exceptions that have no message of their own
//
def logRootCause(e: Throwable) {
    def cause: Throwable = org.apache.commons.lang3.exception.ExceptionUtils.getRootCause(e) ?: e
    log.error(cause.getMessage())
}

//
// Check the sample, library and flowcell names and the platform of a samplesheet row, as assets/schema_input.json does
// for --input. The CSV of a stage or the channel of a pipeline is only checked for types by Nextflow, so a name with a
// space or a full stop, or a platform that is not supported, would otherwise get through. A null name is skipped
//
def checkSampleFields(sample, library_id, flowcell_id, platform) {
    checkName('Sample name', sample)
    checkName('Sequencing library ID', library_id)
    checkName('Flowcell ID', flowcell_id)
    if ( platform != null && !(platform in [ 'ILLUMINA', 'IONTORRENT', 'ONT', 'PACBIO' ]) ) {
        inputError("Sequencing platform '${platform}' must be one of the SAM specification @RG:PL values (in uppercase): ILLUMINA, IONTORRENT, ONT, PACBIO. To request support of another platform, please log a GitHub issue")
    }
}

def checkName(label, value) {
    if ( value != null && !("${value}" ==~ /^[^\s.]+$/) ) {
        inputError("${label} '${value}' cannot contain spaces or full stops")
    }
}

//
// Qualimap cannot read CRAM output, so the two cannot be enabled together
//
def checkQualimapCram(cram_format, align_qc, qualimap) {
    if ( cram_format && align_qc && qualimap ) {
        error "Qualimap cannot be run when CRAM output is enabled."
    }
}

//
// Stop when two rows of a stage input are the same item: key returns what identifies a row (for example the sample,
// library and platform), and the message says what to do about it. Returns the rows when none repeats
//
def checkNoRepeats(rows, key, message) {
    def repeated = rows
        .groupBy { row -> key.call(row) }
        .findAll { _key, group -> group.size() > 1 }
        .collect { repeated_key, _group -> repeated_key.join(' / ') }
    if ( !repeated.isEmpty() ) {
        inputError("${message} Repeated: ${repeated.join(', ')}")
    }
    return rows
}

//
// A tool that needs to know if the reads are single-end or paired-end gets a null when the meta has no single_end.
// Stop with a message that names the field and the sample
//
def checkSingleEnd(meta) {
    if ( meta.single_end == null ) {
        inputError("The meta of sample '${meta.id}' has no single_end (true or false). It is needed to tell single-end from paired-end data")
    }
}

//
// A CRAM can only be decoded with the reference it was made with. other_need is whether a tool of the stage needs the
// reference anyway. Both are checked for the input, so a stage given no CRAM and no such tool can run without --fasta
//
def checkReferenceForInput(alignment, fasta_given, other_need) {
    if ( !fasta_given ) {
        if ( "${alignment}".endsWith('.cram') ) {
            inputError("The CRAM '${alignment}' needs a reference fasta (--fasta) to be read")
        }
        if ( other_need ) {
            inputError("A reference fasta (--fasta) is required by the enabled tools, for example Riker and CRAM output")
        }
    }
}
