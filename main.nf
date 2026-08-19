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
    Global default params (typed)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
params {

    // NOTE: define param types here, and param defaults in nextflow.config

    // Input options
    input                       : String
    reference                   : String

    // Workflow stage gating options
    enable_trim                 : Boolean
    enable_align                : Boolean

    // Read trimming options
    adapter_fasta               : String
    discard_trimmed_pass        : Boolean
    save_trimmed_fail           : Boolean
    save_merged                 : Boolean

    // Alignment options
    aligner                     : String
    sort_bam                    : Boolean

    // MultiQC options
    multiqc_config              : String
    multiqc_title               : String
    multiqc_logo                : String
    max_multiqc_email_size      : String
    multiqc_methods_description : String

    // Boilerplate options
    outdir                      : String
    publish_dir_mode            : String
    monochrome_logs             : Boolean
    help                        : Boolean
    help_full                   : Boolean
    show_hidden                 : Boolean
    version                     : Boolean
    pipelines_testdata_base_path: String
    trace_report_suffix         : String

    // Config options
    config_profile_name         : String
    config_profile_description  : String
    custom_config_version       : String
    custom_config_base          : String
    config_profile_contact      : String
    config_profile_url          : String

    // Schema validation default options
    validate_params             : Boolean

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    NAMED WORKFLOWS FOR PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
// WORKFLOW: Run main analysis pipeline depending on type of input
workflow NBISWEDEN_BIOVAT {

    take:
    samplesheet // channel: samplesheet read in from --input
    reference   // channel: reference fasta read in from --reference

    main:
    // WORKFLOW: Run pipeline
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
    multiqc_data   = BIOVAT.out.multiqc_data
    multiqc_plots  = BIOVAT.out.multiqc_plots
    multiqc_report = BIOVAT.out.multiqc_report // channel: /path/to/multiqc_report.html

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
workflow {

    main:
    // SUBWORKFLOW: Run initialisation tasks
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

    // WORKFLOW: Run main workflow
    NBISWEDEN_BIOVAT (
        PIPELINE_INITIALISATION.out.samplesheet,
        PIPELINE_INITIALISATION.out.reference
    )

    // SUBWORKFLOW: Run completion tasks
    PIPELINE_COMPLETION (
        params.monochrome_logs,
    )

    // Publish workflow outputs
    publish:

    // MultiQC
    multiqc_data   = NBISWEDEN_BIOVAT.out.multiqc_data
    multiqc_plots  = NBISWEDEN_BIOVAT.out.multiqc_plots
    multiqc_report = NBISWEDEN_BIOVAT.out.multiqc_report

}

output {
    // MultiQC
    multiqc_data {
        path 'multiqc'
    }
    multiqc_plots {
        path 'multiqc'
    }
    multiqc_report {
        path 'multiqc'
    }
}
