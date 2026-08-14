#!/usr/bin/env nextflow
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    BioVAT
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Github : https://github.com/NBISweden/biovat
----------------------------------------------------------------------------------------
*/

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS / WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { BIOVAT  } from './workflows/biovat'
include { PIPELINE_INITIALISATION } from './subworkflows/local/utils_nfcore_biovat_pipeline'
include { PIPELINE_COMPLETION     } from './subworkflows/local/utils_nfcore_biovat_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Global default params (typed), used in scripts and configs
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
params {

    // Input options
    input                       : String
    reference                   : String

    // Workflow stage gating options
    enable_trim                 : Boolean = true
    enable_align                : Boolean = true

    // Read trimming options
    adapter_fasta               : String? = null
    discard_trimmed_pass        : Boolean = false
    save_trimmed_fail           : Boolean = false
    save_merged                 : Boolean = false

    // Alignment options
    aligner                     : String  = 'bwa-mem3'
    sort_bam                    : Boolean = true

    // MultiQC options
    multiqc_config              : String? = null
    multiqc_logo                : String? = null
    multiqc_methods_description : String? = null

    // Boilerplate options
    outdir                      : String
    monochrome_logs             : Boolean = false
    help                        : Boolean = false
    help_full                   : Boolean = false
    show_hidden                 : Boolean = false
    version                     : Boolean = false
    pipelines_testdata_base_path: String  = 'https://raw.githubusercontent.com/nf-core/test-datasets/'

    // Schema validation default options
    validate_params             : Boolean = true

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    NAMED WORKFLOWS FOR PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
//
// WORKFLOW: Run main analysis pipeline depending on type of input
//
workflow NBISWEDEN_BIOVAT {

    take:
    samplesheet // channel: samplesheet read in from --input
    reference   // channel: reference fasta read in from --reference

    main:

    //
    // WORKFLOW: Run pipeline
    //
    BIOVAT (
        samplesheet,
        reference,
        params.enable_trim,
        params.enable_align,
        params.adapter_fasta,
        params.discard_trimmed_pass,
        params.save_trimmed_fail,
        params.save_merged,
        params.aligner,
        params.sort_bam,
        params.multiqc_config,
        params.multiqc_logo,
        params.multiqc_methods_description,
        params.outdir,
    )
    emit:
    multiqc_report = BIOVAT.out.multiqc_report // channel: /path/to/multiqc_report.html
}
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow {

    main:
    //
    // SUBWORKFLOW: Run initialisation tasks
    //
    PIPELINE_INITIALISATION (
        params.version,
        params.validate_params,
        params.monochrome_logs,
        args,
        params.outdir,
        params.input,
        params.help,
        params.help_full,
        params.show_hidden
    )

    //
    // WORKFLOW: Run main workflow
    //
    NBISWEDEN_BIOVAT (
        PIPELINE_INITIALISATION.out.samplesheet,
        PIPELINE_INITIALISATION.out.reference
    )
    //
    // SUBWORKFLOW: Run completion tasks
    //
    PIPELINE_COMPLETION (
        params.monochrome_logs,
    )
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
