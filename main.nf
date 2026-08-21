#!/usr/bin/env nextflow
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    BioVAT
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Github : https://github.com/NBISweden/biovat
----------------------------------------------------------------------------------------
*/

include { BIOVAT  } from './workflows/biovat'
include { PIPELINE_INITIALISATION } from './subworkflows/local/utils_nfcore_biovat_pipeline'
include { PIPELINE_COMPLETION     } from './subworkflows/local/utils_nfcore_biovat_pipeline'

// Global default parameters: define param types here, and defaults in nextflow.config
params {

    // Input options
    input                       : String
    reference                   : String

    // Workflow stage gating options
    enable_raw_read_qc          : Boolean
    enable_trim                 : Boolean
    enable_align                : Boolean

    // Read trimming options
    adapter_fasta               : String
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
    modules_testdata_base_path  : String
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

// Main analysis pipeline
workflow NBISWEDEN_BIOVAT {

    take:
    samplesheet // channel: samplesheet read in from --input
    reference   // channel: reference fasta read in from --reference

    main:
    BIOVAT (
        samplesheet,
        reference,
        params.enable_raw_read_qc,
        params.enable_trim,
        params.enable_align,
        params.adapter_fasta,
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
    outputs_trim_reads  = BIOVAT.out.outputs_trim_reads
    outputs_align_reads = BIOVAT.out.outputs_align_reads
    outputs_multiqc     = BIOVAT.out.outputs_multiqc

}

// Entry workflow
workflow {

    main:
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
    NBISWEDEN_BIOVAT (
        PIPELINE_INITIALISATION.out.samplesheet,
        PIPELINE_INITIALISATION.out.reference
    )
    PIPELINE_COMPLETION (
        params.monochrome_logs,
    )

    publish:
    outputs_trim_reads  = NBISWEDEN_BIOVAT.out.outputs_trim_reads
    outputs_align_reads = NBISWEDEN_BIOVAT.out.outputs_align_reads
    outputs_multiqc     = NBISWEDEN_BIOVAT.out.outputs_multiqc

}

output {

    // TRIM_READS
    outputs_trim_reads {
        path '02_read_trimming'
    }
    // ALIGN_READS
    outputs_align_reads {
        path '03_read_alignment'
    }
    // MultiQC
    outputs_multiqc {
        path 'multiqc'
    }

}
