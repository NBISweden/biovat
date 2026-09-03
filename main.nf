#!/usr/bin/env nextflow
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    BioVAT
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Github : https://github.com/NBISweden/biovat
----------------------------------------------------------------------------------------
*/

include { BIOVAT                  } from './workflows/biovat'
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
    enable_align_qc             : Boolean

    // Read trimming options
    adapter_fasta               : String
    enable_save_trimmed_fail    : Boolean
    enable_save_merged          : Boolean

    // Alignment options
    aligner                     : String
    enable_sort_alignments      : Boolean
    enable_cram_format          : Boolean

    // BAM QC options
    enable_riker                : Boolean
    enable_qualimap             : Boolean

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
    // Gating parameters, passed as a single map
    def enable = params.findAll { k, v -> k.startsWith('enable_') }
        .collectEntries { k, v -> [(k - 'enable_'): v] }

    BIOVAT (
        samplesheet,
        reference,
        enable,
        params.adapter_fasta,
        params.aligner,
        params.multiqc_config,
        params.multiqc_logo,
        params.multiqc_methods_description,
        params.outdir
    )

    emit:
    outputs_raw_read_qc      = BIOVAT.out.outputs_raw_read_qc
    outputs_trim_reads       = BIOVAT.out.outputs_trim_reads
    outputs_align_reads      = BIOVAT.out.outputs_align_reads
    outputs_library_flagstat = BIOVAT.out.outputs_library_flagstat
    outputs_library_riker    = BIOVAT.out.outputs_library_riker
    outputs_library_qualimap = BIOVAT.out.outputs_library_qualimap
    outputs_multiqc          = BIOVAT.out.outputs_multiqc

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
    outputs_raw_read_qc      = NBISWEDEN_BIOVAT.out.outputs_raw_read_qc
    outputs_trim_reads       = NBISWEDEN_BIOVAT.out.outputs_trim_reads
    outputs_align_reads      = NBISWEDEN_BIOVAT.out.outputs_align_reads
    outputs_library_flagstat = NBISWEDEN_BIOVAT.out.outputs_library_flagstat
    outputs_library_riker    = NBISWEDEN_BIOVAT.out.outputs_library_riker
    outputs_library_qualimap = NBISWEDEN_BIOVAT.out.outputs_library_qualimap
    outputs_multiqc          = NBISWEDEN_BIOVAT.out.outputs_multiqc

}

output {

    // READ_QC
    outputs_raw_read_qc {
        path '01_input_checks/reads/fastqc'
    }
    // TRIM_READS
    outputs_trim_reads {
        path '02_read_trimming'
    }
    // ALIGN_READS
    outputs_align_reads {
        path '03_read_alignment'
    }
    // ALIGNMENT_QC: library level
    outputs_library_flagstat {
        path '03_read_alignment/qc/samtools_flagstat'
    }
    outputs_library_riker {
        path '03_read_alignment/qc/riker'
    }
    outputs_library_qualimap {
        path '03_read_alignment/qc/qualimap'
    }
    // MultiQC
    outputs_multiqc {
        path 'multiqc'
    }

}
