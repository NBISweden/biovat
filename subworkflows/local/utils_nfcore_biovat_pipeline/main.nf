//
// Subworkflow with functionality specific to the BioVAT pipeline
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { UTILS_NFSCHEMA_PLUGIN   } from '../../nf-core/utils_nfschema_plugin'
include { paramsSummaryMap        } from 'plugin/nf-schema'
include { samplesheetToList       } from 'plugin/nf-schema'
include { paramsHelp              } from 'plugin/nf-schema'
include { completionSummary       } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NFCORE_PIPELINE   } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NEXTFLOW_PIPELINE } from '../../nf-core/utils_nextflow_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW TO INITIALISE PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_INITIALISATION {

    take:
    version           // boolean: Display version and exit
    validate_params   // boolean: Boolean whether to validate parameters against the schema at runtime
    monochrome_logs   // boolean: Do not use coloured log outputs
    nextflow_cli_args // array: List of positional nextflow CLI args
    outdir            // string: The output directory where the results will be saved
    input             // string: Path to input samplesheet
    sample_metadata   // string: Path to sample-level metadata sheet (optional)
    help              // boolean: Display help message and exit
    help_full         // boolean: Show the full help message
    show_hidden       // boolean: Show hidden parameters in the help message

    main:
    //
    // Print version and exit if required and dump pipeline parameters to JSON file
    //
    UTILS_NEXTFLOW_PIPELINE(
        version,
        true,
        outdir,
        workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1
    )

    //
    // Validate parameters and generate parameter summary to stdout
    //

    def before_text = """\033[0;92mnbisweden/biovat ${workflow.manifest.version}\033[0m

    """

    def after_text = """Log issues or questions at: \033[0;92m${workflow.manifest.homePage}/issues\033[0m
    """
    if (monochrome_logs) {
        before_text = before_text.replaceAll(/\033\[[0-9;]*m/, '')
    }

    command = "nextflow run ${workflow.manifest.name} -profile <docker/singularity/.../institute> --input samplesheet.csv --outdir <OUTDIR>"

    UTILS_NFSCHEMA_PLUGIN(
        workflow,
        validate_params,
        null,
        help,
        help_full,
        show_hidden,
        before_text,
        after_text,
        command
    )

    //
    // Check config provided to the pipeline
    //
    UTILS_NFCORE_PIPELINE(
        nextflow_cli_args
    )

    // Validation pipeline parameters
    validateInputParameters()

    // Build list of samplesheet rows, run validation checks, & then create a channel from it
    // Uniqueness of the sample/library_id/flowcell_id/lane
    // combination is enforced by the "uniqueEntries" key in assets/schema_input.json
    def samplesheet_rows = samplesheetToList(input, "${projectDir}/assets/schema_input.json")
        .collect { meta, fastq_1, fastq_2, bam ->
            // We define read_group separately as an intuitive/readable @RG-level file prefix
            def read_group = "${meta.id}.${meta.library}.${meta.flowcell}.${meta.lane}".toString()
            // GATK format @RG ID/PU written by the aligners/samtools, and expected by VALIDATE_READGROUP_HEADER
            def platform_unit = "${meta.flowcell}.${meta.lane}.${meta.id}_${meta.library}".toString()
            def extra = bam
                ? [ read_group:read_group, platform_unit:platform_unit, input_type:'bam_cram' ]
                : [ read_group:read_group, platform_unit:platform_unit, input_type:'fastq', single_end:!fastq_2 ]
            [ meta + extra, bam ? [ bam ] : [ fastq_1, fastq_2 ].findAll() ]
        }

    // Alignments are merged from read group to library to sample levels. A specific library must not mix platforms, and
    // every alignment in a merge group must agree on single_end
    validateMergeGroups(samplesheet_rows)

    // Sample-level metadata (one row per sample) is loaded separately from readgroup level metadata.
    // Uniqueness of sample data is enforced by the "uniqueEntries" key in assets/schema_sample_metadata.json
    def sample_metadata_rows = sample_metadata
        ? samplesheetToList(sample_metadata, "${projectDir}/assets/schema_sample_metadata.json").collect { row -> row[0] }
        : []
    // Correctness of --sample_metadata is checked against the samplesheet rows
    validateSampleMetadata(samplesheet_rows, sample_metadata_rows)
    def samples = samplesheet_rows.collect { meta, _files -> meta.id }.toSet()

    // Reject alignment-consuming stages (dedup, variant calling) when nothing produces alignments
    validateAlignmentConsumers(samplesheet_rows)

    // Report every reason --reference is needed (params and samplesheet rows) in one error
    validateReferenceRequirements(samplesheet_rows)

    // Create reference channel from input file provided through params.reference
    reference = channel.empty()
    if ( params.reference ) {
        reference = channel.value(file(params.reference, checkIfExists: true))
            .map { fasta ->
                def meta = [ id: fasta.baseName ]
                return [ meta, fasta ]
            }
    }

    emit:
    samplesheet           = channel.fromList(samplesheet_rows)
    sample_metadata_sheet = channel.fromList(sample_metadata_rows.findAll { meta -> meta.id in samples })
    reference
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW FOR PIPELINE COMPLETION
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_COMPLETION {

    take:
    monochrome_logs // boolean: Disable ANSI colour codes in log output

    main:

    //
    // Completion email and summary
    //
    workflow.onComplete {

        completionSummary(monochrome_logs)

    }

    workflow.onError {
        log.error "Pipeline failed. Please refer to troubleshooting docs for common issues: https://nf-co.re/docs/running/troubleshooting"
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// Custom validation of input parameters (e.g. dependent/exclusive params)
//

def validationError(message) {
    error "\033[0;91mERROR\033[0m: ${message}"
}

def validateInputParameters() {

    def enable = params
        .findAll { k, _v -> k.startsWith('enable_') }
        .collectEntries { k, v -> [(k - 'enable_'): v] }
    // If CRAM format is requested, qualimap cannot be run
    if ( enable.cram_format && enable.align_qc && enable.qualimap ) {
        validationError("Qualimap cannot be run when CRAM output is enabled.")
    }
}

// Reject a samplesheet whose rows can't be merged consistently. Alignments are merged from read group -> library
// (grouped on sample, library and platform) -> sample (grouped on sample and platform):
//  - a library is prepared for a single sequencing platform. Its read groups must agree on platform
//  - every alignment in a merge group must agree on single_end, or it is merged into a single BAM with
//    inconsistent read pairing. A sample may span platforms (e.g. paired-end ILLUMINA and single-end ONT),
//    so libraries are only compared within a platform
def validateMergeGroups(rows) {
    rows
        .groupBy { meta, _reads -> [ meta.id, meta.library ] }
        .each { key, group ->
            def (sample_id, library_id) = key
            def platforms = group.collect { meta, _reads -> meta.pl }.unique()
            if (platforms.size() > 1) {
                validationError("Sample '${sample_id}', library '${library_id}' mixes sequencing platforms (${platforms.join(', ')}) - all lanes of a library must share the same platform.")
            }
            if (group.collect { meta, _reads -> meta.single_end }.unique().size() > 1) {
                validationError("Sample '${sample_id}', library '${library_id}' mixes single-end and paired-end reads across lanes - all lanes of a library must share the same read layout.")
            }
        }
    rows
        .groupBy { meta, _reads -> [ meta.id, meta.pl ] }
        .each { key, group ->
            def (sample_id, platform) = key
            if (group.collect { meta, _reads -> meta.single_end }.unique().size() > 1) {
                validationError("Sample '${sample_id}' mixes single-end and paired-end reads across its ${platform} libraries - all libraries of a sample sequenced on the same platform must share the same read layout.")
            }
        }
}

// --sample_metadata is used for population grouping during variant calling
// A sample must have a corresponding entry in the metadata file. We warn if extras are found.
def validateSampleMetadata(rows, metadata_rows) {
    def group_samples = params.enable_variant_calling && params.enable_group_samples
    if ( !group_samples ) {
        if ( params.sample_metadata ) {
            log.warn("--sample_metadata is only used for population grouping (--enable_variant_calling with --enable_group_samples), and will be ignored.")
        }
        return
    }
    if ( !params.sample_metadata ) {
        validationError("Grouping samples into populations (--enable_group_samples) requires --sample_metadata, with a 'population' value for every sample.")
    }
    def samplesheet_samples = rows.collect { meta, _files -> meta.id }.unique()
    def metadata_supplied   = metadata_rows.collect { meta -> meta.id }
    def extra_samples       = metadata_supplied - samplesheet_samples
    if ( extra_samples ) {
        log.warn("--sample_metadata lists sample(s) not in --input, which will be ignored: ${extra_samples.join(', ')}")
    }
    def missing_metadata    = samplesheet_samples - metadata_rows.findAll { meta -> meta.population }.collect { meta -> meta.id }
    if ( missing_metadata ) {
        validationError("Grouping samples into populations (--enable_group_samples) requires a 'population' in --sample_metadata for every sample. Missing for: ${missing_metadata.join(', ')}")
    }
}

// Alignments enter the pipeline only via ALIGN_READS or INGEST_BAM_OR_CRAM (BAM/CRAM input rows); every
// downstream stage (merge, dedup) operates on those same alignments, so adds no source of its own
def hasAlignmentSource(enable, has_bam_cram_rows) {
    enable.align || has_bam_cram_rows
}

// RIKER runs wherever ALIGNMENT_QC runs, i.e. whenever alignment QC is enabled and any alignment exists.
// Callers that can't see the samplesheet rows (main.nf) pass has_bam_cram_rows = true to stay conservative
def rikerActive(enable, has_bam_cram_rows) {
    enable.align_qc && enable.riker && hasAlignmentSource(enable, has_bam_cram_rows)
}

// Stages that consume alignments need a source of them: ALIGN_READS or BAM/CRAM input rows
def validateAlignmentConsumers(rows) {
    def enable            = params
        .findAll { k, _v -> k.startsWith('enable_') }
        .collectEntries { k, v -> [(k - 'enable_'): v] }
    def has_bam_cram_rows = rows.any { meta, _files -> meta.input_type == 'bam_cram' }
    if ( hasAlignmentSource(enable, has_bam_cram_rows) ) {
        return
    }
    def stages = [ mark_duplicates: '--enable_mark_duplicates', variant_calling: '--enable_variant_calling' ]
        .findAll { stage, _flag -> enable[stage] }
    if ( stages ) {
        validationError("No alignments to process for ${stages.values().join(', ')}. Either enable alignment, provide 'BAM/CRAM' files, or disable these stage(s).")
    }
}

// Collect every reason --reference is needed (from params and samplesheet rows) and report in one error
def validateReferenceRequirements(rows) {
    if ( params.reference ) {
        return
    }
    def enable            = params
        .findAll { k, _v -> k.startsWith('enable_') }
        .collectEntries { k, v -> [(k - 'enable_'): v] }
    def bam_cram_rows     = rows.findAll { meta, _files -> meta.input_type == 'bam_cram' }
    def cram_rows         = bam_cram_rows.findAll { _meta, files -> files[0].toString().endsWith('.cram') }
    def has_bam_cram_rows = !bam_cram_rows.isEmpty()
    def reasons           = []
    if ( enable.align ) {
        reasons.add("alignment (--enable_align)")
    }
    if ( enable.cram_format && hasAlignmentSource(enable, has_bam_cram_rows) ) {
        reasons.add("CRAM output (--enable_cram_format)")
    }
    // A CRAM input row needs --reference to decode (SAMTOOLS_SORT in INGEST_BAM_OR_CRAM)
    if ( !cram_rows.isEmpty() ) {
        def cram_samples = cram_rows.collect { meta, _files -> meta.id }.unique()
        reasons.add("decoding CRAM input (sample(s): ${cram_samples.join(', ')})")
    }
    if ( rikerActive(enable, has_bam_cram_rows) ) {
        reasons.add("RIKER (--enable_riker)")
    }
    if ( enable.variant_calling && hasAlignmentSource(enable, has_bam_cram_rows) ) {
        reasons.add("variant calling (--enable_variant_calling)")
    }
    if ( !reasons.isEmpty() ) {
        validationError("A reference FASTA file (--reference) is required for:\n  - ${reasons.join('\n  - ')}")
    }
}

//
// Generate methods description for MultiQC
//
def toolCitationText() {
    // TODO nf-core: Optionally add in-text citation tools to this list.
    // Can use ternary operators to dynamically construct based conditions, e.g. params["run_xyz"] ? "Tool (Foo et al. 2023)" : "",
    // Uncomment function in methodsDescriptionText to render in MultiQC report
    def citation_text = [
            "Tools used in the workflow included:",
            "FastQC (Andrews 2010),",
            "MultiQC (Ewels et al. 2016)",
            "."
        ].join(' ').trim()

    return citation_text
}

def toolBibliographyText() {
    // TODO nf-core: Optionally add bibliographic entries to this list.
    // Can use ternary operators to dynamically construct based conditions, e.g. params["run_xyz"] ? "<li>Author (2023) Pub name, Journal, DOI</li>" : "",
    // Uncomment function in methodsDescriptionText to render in MultiQC report
    def reference_text = [
            "<li>Andrews S, (2010) FastQC, URL: https://www.bioinformatics.babraham.ac.uk/projects/fastqc/).</li>",
            "<li>Ewels, P., Magnusson, M., Lundin, S., & Käller, M. (2016). MultiQC: summarize analysis results for multiple tools and samples in a single report. Bioinformatics , 32(19), 3047–3048. doi: /10.1093/bioinformatics/btw354</li>"
        ].join(' ').trim()

    return reference_text
}

def methodsDescriptionText(mqc_methods_yaml) {
    // Convert  to a named map so can be used as with familiar NXF ${workflow} variable syntax in the MultiQC YML file
    def meta = [:]
    meta.workflow = workflow.toMap()
    meta["manifest_map"] = workflow.manifest.toMap()

    // Pipeline DOI
    if (meta.manifest_map.doi) {
        // Using a loop to handle multiple DOIs
        // Removing `https://doi.org/` to handle pipelines using DOIs vs DOI resolvers
        // Removing ` ` since the manifest.doi is a string and not a proper list
        def temp_doi_ref = ""
        def manifest_doi = meta.manifest_map.doi.tokenize(",")
        manifest_doi.each { doi_ref ->
            temp_doi_ref += "(doi: <a href=\'https://doi.org/${doi_ref.replace("https://doi.org/", "").replace(" ", "")}\'>${doi_ref.replace("https://doi.org/", "").replace(" ", "")}</a>), "
        }
        meta["doi_text"] = temp_doi_ref.substring(0, temp_doi_ref.length() - 2)
    } else meta["doi_text"] = ""
    meta["nodoi_text"] = meta.manifest_map.doi ? "" : "<li>If available, make sure to update the text to include the Zenodo DOI of version of the pipeline used. </li>"

    // Tool references
    meta["tool_citations"] = ""
    meta["tool_bibliography"] = ""

    // TODO nf-core: Only uncomment below if logic in toolCitationText/toolBibliographyText has been filled!
    // meta["tool_citations"] = toolCitationText().replaceAll(", \\.", ".").replaceAll("\\. \\.", ".").replaceAll(", \\.", ".")
    // meta["tool_bibliography"] = toolBibliographyText()


    def methods_text = mqc_methods_yaml.text

    def engine = new groovy.text.SimpleTemplateEngine()
    def description_html = engine.createTemplate(methods_text).make(meta)

    return description_html.toString()
}
