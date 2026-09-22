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
    input: String
    reference: String

    // Workflow stage gating options
    enable_raw_read_qc: Boolean
    enable_trim: Boolean
    enable_align: Boolean
    enable_align_qc: Boolean
    enable_mark_duplicates: Boolean

    // Read trimming options
    adapter_fasta: String
    enable_save_trimmed_fail: Boolean
    enable_save_merged: Boolean

    // Alignment options
    aligner: String
    enable_cram_format: Boolean

    // Alignment QC options
    enable_riker: Boolean
    enable_qualimap: Boolean

    // Duplicate marking options
    duplicate_marker: String
    enable_remove_duplicates: Boolean
    optical_distance: Integer

    // MultiQC options
    multiqc_config: String
    multiqc_title: String
    multiqc_logo: String
    max_multiqc_email_size: String
    multiqc_methods_description: String

    // Boilerplate options
    outdir: String
    publish_dir_mode: String
    monochrome_logs: Boolean
    help: Boolean
    help_full: Boolean
    show_hidden: Boolean
    version: Boolean
    modules_testdata_base_path: String
    pipelines_testdata_base_path: String
    trace_report_suffix: String

    // Config options
    config_profile_name: String
    config_profile_description: String
    custom_config_version: String
    custom_config_base: String
    config_profile_contact: String
    config_profile_url: String

    // Schema validation default options
    validate_params: Boolean
}

// Main analysis pipeline
workflow NBISWEDEN_BIOVAT {
    take:
    samplesheet // channel: samplesheet read in from --input
    reference   // channel: reference fasta read in from --reference

    main:
    // Gating parameters, passed as a single map
    def enable = params
        .findAll { k, _v -> k.startsWith('enable_') }
        .collectEntries { k, v -> [(k - 'enable_'): v] }

    // 'requires' is a map of internal dependency relationships
    def requires = [
        // MERGE_TO_LIBRARY (readgroup -> library) and MERGE_TO_SAMPLE (library -> sample, post-deduplication)
        // are both triggered when a downstream consumer needs deduplicated alignments
        merge: enable.mark_duplicates,
    ]

    // ALIGNMENT_QC runs when a parent stage is also enabled
    // requires.merge acts as an umbrella for all sample-level stages
    def align_qc_active = enable.align_qc && (enable.align || requires.merge)

    // .fai is used for certain CRAM processes, and unconditionally by riker
    requires.fai = (enable.cram_format && requires.merge) || (align_qc_active && enable.riker)

    biovat_out = BIOVAT(
        samplesheet,
        reference,
        enable,
        requires,
        params.adapter_fasta,
        params.aligner,
        params.duplicate_marker,
        params.multiqc_config,
        params.multiqc_logo,
        params.multiqc_methods_description,
        params.outdir,
    )

    emit:
    outputs_raw_read_qc              = biovat_out.outputs_raw_read_qc
    outputs_trim_reads               = biovat_out.outputs_trim_reads
    outputs_read_group               = biovat_out.outputs_read_group
    outputs_read_group_flagstat      = biovat_out.outputs_read_group_flagstat
    outputs_read_group_riker         = biovat_out.outputs_read_group_riker
    outputs_read_group_qualimap      = biovat_out.outputs_read_group_qualimap
    outputs_library                  = biovat_out.outputs_library
    outputs_library_flagstat         = biovat_out.outputs_library_flagstat
    outputs_library_riker            = biovat_out.outputs_library_riker
    outputs_library_qualimap         = biovat_out.outputs_library_qualimap
    outputs_mark_duplicates          = biovat_out.outputs_mark_duplicates
    outputs_mark_duplicates_flagstat = biovat_out.outputs_mark_duplicates_flagstat
    outputs_mark_duplicates_riker    = biovat_out.outputs_mark_duplicates_riker
    outputs_mark_duplicates_qualimap = biovat_out.outputs_mark_duplicates_qualimap
    outputs_sample                   = biovat_out.outputs_sample
    outputs_sample_flagstat          = biovat_out.outputs_sample_flagstat
    outputs_sample_riker             = biovat_out.outputs_sample_riker
    outputs_sample_qualimap          = biovat_out.outputs_sample_qualimap
    outputs_multiqc                  = biovat_out.outputs_multiqc
}

// Entry workflow
workflow {

    main:
    pipeline_initialisation_out = PIPELINE_INITIALISATION(
        params.version,
        params.validate_params,
        params.monochrome_logs,
        args,
        params.outdir,
        params.input,
        params.help,
        params.help_full,
        params.show_hidden,
    )
    nbisweden_biovat_out = NBISWEDEN_BIOVAT(
        pipeline_initialisation_out.samplesheet,
        pipeline_initialisation_out.reference,
    )
    PIPELINE_COMPLETION(
        params.monochrome_logs
    )

    publish:
    outputs_raw_read_qc              = nbisweden_biovat_out.outputs_raw_read_qc
    outputs_trim_reads               = nbisweden_biovat_out.outputs_trim_reads
    outputs_read_group               = nbisweden_biovat_out.outputs_read_group
    outputs_read_group_flagstat      = nbisweden_biovat_out.outputs_read_group_flagstat
    outputs_read_group_riker         = nbisweden_biovat_out.outputs_read_group_riker
    outputs_read_group_qualimap      = nbisweden_biovat_out.outputs_read_group_qualimap
    outputs_library                  = nbisweden_biovat_out.outputs_library
    outputs_library_flagstat         = nbisweden_biovat_out.outputs_library_flagstat
    outputs_library_riker            = nbisweden_biovat_out.outputs_library_riker
    outputs_library_qualimap         = nbisweden_biovat_out.outputs_library_qualimap
    outputs_mark_duplicates          = nbisweden_biovat_out.outputs_mark_duplicates
    outputs_mark_duplicates_flagstat = nbisweden_biovat_out.outputs_mark_duplicates_flagstat
    outputs_mark_duplicates_riker    = nbisweden_biovat_out.outputs_mark_duplicates_riker
    outputs_mark_duplicates_qualimap = nbisweden_biovat_out.outputs_mark_duplicates_qualimap
    outputs_sample                   = nbisweden_biovat_out.outputs_sample
    outputs_sample_flagstat          = nbisweden_biovat_out.outputs_sample_flagstat
    outputs_sample_riker             = nbisweden_biovat_out.outputs_sample_riker
    outputs_sample_qualimap          = nbisweden_biovat_out.outputs_sample_qualimap
    outputs_multiqc                  = nbisweden_biovat_out.outputs_multiqc
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
    // MultiQC
    outputs_multiqc {
        path 'multiqc'
    }

}
