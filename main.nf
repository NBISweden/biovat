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
    enable_mark_duplicates      : Boolean
    enable_variant_calling      : Boolean
    enable_variant_qc           : Boolean

    // Read trimming options
    adapter_fasta               : String
    enable_save_trimmed_fail    : Boolean
    enable_save_merged          : Boolean

    // Alignment options
    aligner                     : String
    enable_cram_format          : Boolean

    // Alignment QC options
    enable_riker                : Boolean
    enable_qualimap             : Boolean

    // Duplicate marking options
    duplicate_marker            : String
    enable_remove_duplicates    : Boolean
    optical_distance            : Integer

    // Variant calling options
    dataset_name                : String
    variant_caller              : String
    enable_save_mpileup         : Boolean
    bcftools_call_arguments     : String

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
    def enable = params.findAll { k, _v -> k.startsWith('enable_') }
        .collectEntries { k, v -> [(k - 'enable_'): v] }

    // 'requires' is a map of internal dependency relationships
    def requires = [
        // MERGE_TO_LIBRARY (readgroup -> library) and MERGE_TO_SAMPLE (library -> sample, post-deduplication)
        // are both triggered when a downstream consumer needs deduplicated alignments
        merge: enable.mark_duplicates || enable.variant_calling
    ]

    // ALIGNMENT_QC runs when a parent stage is also enabled
    // requires.merge acts as an umbrella for all sample-level stages
    def align_qc_active = enable.align_qc && (enable.align || requires.merge)

    // .fai is used for certain CRAM processes, and unconditionally by riker and bcftools mpileup
    requires.fai = (enable.cram_format && requires.merge)
        || (align_qc_active && enable.riker)
        || (enable.variant_calling && params.variant_caller == 'bcftools')

    BIOVAT (
        samplesheet,
        reference,
        enable,
        requires,
        params.adapter_fasta,
        params.aligner,
        params.duplicate_marker,
        params.variant_caller,
        params.dataset_name,
        params.multiqc_config,
        params.multiqc_logo,
        params.multiqc_methods_description,
        params.outdir
    )

    emit:
    outputs_raw_read_qc                           = BIOVAT.out.outputs_raw_read_qc
    outputs_trim_reads                            = BIOVAT.out.outputs_trim_reads
    outputs_read_group                            = BIOVAT.out.outputs_read_group
    outputs_read_group_flagstat                   = BIOVAT.out.outputs_read_group_flagstat
    outputs_read_group_riker                      = BIOVAT.out.outputs_read_group_riker
    outputs_read_group_qualimap                   = BIOVAT.out.outputs_read_group_qualimap
    outputs_library                               = BIOVAT.out.outputs_library
    outputs_library_flagstat                      = BIOVAT.out.outputs_library_flagstat
    outputs_library_riker                         = BIOVAT.out.outputs_library_riker
    outputs_library_qualimap                      = BIOVAT.out.outputs_library_qualimap
    outputs_mark_duplicates                       = BIOVAT.out.outputs_mark_duplicates
    outputs_mark_duplicates_flagstat              = BIOVAT.out.outputs_mark_duplicates_flagstat
    outputs_mark_duplicates_riker                 = BIOVAT.out.outputs_mark_duplicates_riker
    outputs_mark_duplicates_qualimap              = BIOVAT.out.outputs_mark_duplicates_qualimap
    outputs_sample                                = BIOVAT.out.outputs_sample
    outputs_sample_flagstat                       = BIOVAT.out.outputs_sample_flagstat
    outputs_sample_riker                          = BIOVAT.out.outputs_sample_riker
    outputs_sample_qualimap                       = BIOVAT.out.outputs_sample_qualimap
    outputs_variant_calls                         = BIOVAT.out.outputs_variant_calls
    outputs_mpileup                               = BIOVAT.out.outputs_mpileup
    outputs_call_variants_bcftools_stats          = BIOVAT.out.outputs_call_variants_bcftools_stats
    outputs_call_variants_vcftools_tstv_counts    = BIOVAT.out.outputs_call_variants_vcftools_tstv_counts
    outputs_call_variants_vcftools_tstv_qual      = BIOVAT.out.outputs_call_variants_vcftools_tstv_qual
    outputs_call_variants_vcftools_filter_summary = BIOVAT.out.outputs_call_variants_vcftools_filter_summary
    outputs_call_variants_vcftools_relatedness2   = BIOVAT.out.outputs_call_variants_vcftools_relatedness2
    outputs_multiqc                               = BIOVAT.out.outputs_multiqc

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
    outputs_raw_read_qc                           = NBISWEDEN_BIOVAT.out.outputs_raw_read_qc
    outputs_trim_reads                            = NBISWEDEN_BIOVAT.out.outputs_trim_reads
    outputs_read_group                            = NBISWEDEN_BIOVAT.out.outputs_read_group
    outputs_read_group_flagstat                   = NBISWEDEN_BIOVAT.out.outputs_read_group_flagstat
    outputs_read_group_riker                      = NBISWEDEN_BIOVAT.out.outputs_read_group_riker
    outputs_read_group_qualimap                   = NBISWEDEN_BIOVAT.out.outputs_read_group_qualimap
    outputs_library                               = NBISWEDEN_BIOVAT.out.outputs_library
    outputs_library_flagstat                      = NBISWEDEN_BIOVAT.out.outputs_library_flagstat
    outputs_library_riker                         = NBISWEDEN_BIOVAT.out.outputs_library_riker
    outputs_library_qualimap                      = NBISWEDEN_BIOVAT.out.outputs_library_qualimap
    outputs_mark_duplicates                       = NBISWEDEN_BIOVAT.out.outputs_mark_duplicates
    outputs_mark_duplicates_flagstat              = NBISWEDEN_BIOVAT.out.outputs_mark_duplicates_flagstat
    outputs_mark_duplicates_riker                 = NBISWEDEN_BIOVAT.out.outputs_mark_duplicates_riker
    outputs_mark_duplicates_qualimap              = NBISWEDEN_BIOVAT.out.outputs_mark_duplicates_qualimap
    outputs_sample                                = NBISWEDEN_BIOVAT.out.outputs_sample
    outputs_sample_flagstat                       = NBISWEDEN_BIOVAT.out.outputs_sample_flagstat
    outputs_sample_riker                          = NBISWEDEN_BIOVAT.out.outputs_sample_riker
    outputs_sample_qualimap                       = NBISWEDEN_BIOVAT.out.outputs_sample_qualimap
    outputs_variant_calls                         = NBISWEDEN_BIOVAT.out.outputs_variant_calls
    outputs_mpileup                               = NBISWEDEN_BIOVAT.out.outputs_mpileup
    outputs_call_variants_bcftools_stats          = NBISWEDEN_BIOVAT.out.outputs_call_variants_bcftools_stats
    outputs_call_variants_vcftools_tstv_counts    = NBISWEDEN_BIOVAT.out.outputs_call_variants_vcftools_tstv_counts
    outputs_call_variants_vcftools_tstv_qual      = NBISWEDEN_BIOVAT.out.outputs_call_variants_vcftools_tstv_qual
    outputs_call_variants_vcftools_filter_summary = NBISWEDEN_BIOVAT.out.outputs_call_variants_vcftools_filter_summary
    outputs_call_variants_vcftools_relatedness2   = NBISWEDEN_BIOVAT.out.outputs_call_variants_vcftools_relatedness2
    outputs_multiqc                               = NBISWEDEN_BIOVAT.out.outputs_multiqc

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
    outputs_read_group {
        path '03_read_alignment'
    }
    outputs_read_group_flagstat {
        path '03_read_alignment/qc/samtools_flagstat'
    }
    outputs_read_group_riker {
        path '03_read_alignment/qc/riker'
    }
    outputs_read_group_qualimap {
        path '03_read_alignment/qc/qualimap'
    }
    // MERGE_TO_LIBRARY
    outputs_library {
        path { meta, alignment, index ->
            // Includes library and platform to avoid file name collisions
            alignment >> "04_merged_libraries/${meta.id}_${meta.library}_${meta.pl}.${alignment.extension}"
            index     >> "04_merged_libraries/${meta.id}_${meta.library}_${meta.pl}.${alignment.extension}.${index.extension}"
        }
    }
    outputs_library_flagstat {
        path '04_merged_libraries/qc/samtools_flagstat'
    }
    outputs_library_riker {
        path '04_merged_libraries/qc/riker'
    }
    outputs_library_qualimap {
        path '04_merged_libraries/qc/qualimap'
    }
    // MARK_DUPLICATES
    outputs_mark_duplicates {
        path '05_duplicate_processed'
    }
    outputs_mark_duplicates_flagstat {
        path '05_duplicate_processed/qc/samtools_flagstat'
    }
    outputs_mark_duplicates_riker {
        path '05_duplicate_processed/qc/riker'
    }
    outputs_mark_duplicates_qualimap {
        path '05_duplicate_processed/qc/qualimap'
    }
    // MERGE_TO_SAMPLE
    outputs_sample {
        path { meta, alignment, index ->
            // Includes platform to avoid file name collisions
            alignment >> "06_merged_samples/${meta.id}_${meta.pl}.${alignment.extension}"
            index     >> "06_merged_samples/${meta.id}_${meta.pl}.${alignment.extension}.${index.extension}"
        }
    }
    outputs_sample_flagstat {
        path '06_merged_samples/qc/samtools_flagstat'
    }
    outputs_sample_riker {
        path '06_merged_samples/qc/riker'
    }
    outputs_sample_qualimap {
        path '06_merged_samples/qc/qualimap'
    }
        // CALL_VARIANTS
    outputs_variant_calls {
        path '06_variant_calls'
    }
    outputs_mpileup {
        path '06_variant_calls'
    }
    outputs_call_variants_bcftools_stats {
        path '06_variant_calls/qc/bcftools_stats'
    }
    outputs_call_variants_vcftools_tstv_counts {
        path '06_variant_calls/qc/vcftools'
    }
    outputs_call_variants_vcftools_tstv_qual {
        path '06_variant_calls/qc/vcftools'
    }
    outputs_call_variants_vcftools_filter_summary {
        path '06_variant_calls/qc/vcftools'
    }
    outputs_call_variants_vcftools_relatedness2 {
        path '06_variant_calls/qc/vcftools'
    }
    // MultiQC
    outputs_multiqc {
        path 'multiqc'
    }

}
