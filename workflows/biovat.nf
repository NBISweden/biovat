/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { MULTIQC                   } from '../modules/nf-core/multiqc/main'
include { paramsSummaryMap          } from 'plugin/nf-schema'
include { paramsSummaryMultiqc      } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML    } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText    } from '../subworkflows/local/utils_nfcore_biovat_pipeline'
include { INGEST_BAM_OR_CRAM        } from '../subworkflows/local/utils_bam'
include { REFERENCE_UTILS           } from '../subworkflows/local/utils_reference'
include { READ_QC                   } from '../subworkflows/local/read_qc/main'
include { TRIM_READS                } from '../subworkflows/local/trim_reads/main'
include { ALIGN_READS               } from '../subworkflows/local/align_reads/main'
include { MERGE as MERGE_TO_LIBRARY } from '../subworkflows/local/merge/main'
include { MARK_DUPLICATES           } from '../subworkflows/local/mark_duplicates/main'
include { MERGE as MERGE_TO_SAMPLE  } from '../subworkflows/local/merge/main'
include { CALL_VARIANTS             } from '../subworkflows/local/call_variants/main'

workflow BIOVAT {
    take:
    ch_samplesheet // channel: samplesheet read in from --input
    reference // channel: reference fasta read in from --reference
    enable // map: gating flags
    requires // map: defines internal dependency relationships
    adapter_fasta // channel: adapter fasta file read in from --adapter_fasta
    aligner // string: Aligner to use for read alignment (e.g. bwa, parabricks)
    duplicate_marker // string: Duplicate marking tool to use (e.g. picard, samtools)
    variant_caller // string: Variant calling tool to use (e.g. bcftools_multisample)
    chunk_size // integer: Genome chunk size (bp) used for parallelization
    min_length // integer: Minimum contig/scaffold length to be kept
    dataset_name // string: File name prefix for VCF/BCF file containing all samples
    multiqc_config
    multiqc_logo
    multiqc_methods_description
    outdir

    main:
    def ch_versions = channel.empty()
    def ch_multiqc_files = channel.empty()
    ch_input             = ch_samplesheet
        .branch { meta, _data ->
            bam_cram: meta.input_type == 'bam_cram'
            fastq   : meta.input_type == 'fastq'
        }
    reads_to_preprocess = ch_input.fastq

    // Reference utilities
    ch_reference_and_optional_fai = channel.value([[], [], []])
    if ( params.reference ) {
        reference_utils_out = REFERENCE_UTILS(
            reference,
            requires,
        )
        ch_reference_and_optional_fai = reference_utils_out.ch_reference_and_optional_fai
    }

    // Raw read quality checks
    outputs_raw_read_qc = channel.empty()
    if ( enable.raw_read_qc ) {
        read_qc_out = READ_QC(
            reads_to_preprocess
        )
        ch_multiqc_files    = ch_multiqc_files.mix(read_qc_out.fastqc_zip.map { _meta, file -> file })
        outputs_raw_read_qc = read_qc_out.fastqc_zip.mix(read_qc_out.fastqc_html)
    }

    // Trim reads
    outputs_trim_reads = channel.empty()
    if (enable.trim) {
        // FASTP takes reads + adapters (if provided)
        def path_adapter_fasta    = adapter_fasta ? file(adapter_fasta, checkIfExists: true) : []
        def ch_reads_and_adapters = reads_to_preprocess.map { meta, reads -> [meta, reads, path_adapter_fasta] }
        // FASTP
        trim_reads_out = TRIM_READS(
            ch_reads_and_adapters,
            enable,
        )
        reads_to_preprocess = trim_reads_out.trimmed_reads
        ch_multiqc_files    = ch_multiqc_files.mix(trim_reads_out.fastp_json.map { _meta, file -> file })
        outputs_trim_reads  = trim_reads_out.mix()
    }

    // Align reads
    ch_read_group_alignments_indexed = channel.empty()
    outputs_read_group               = channel.empty()
    outputs_read_group_flagstat      = channel.empty()
    outputs_read_group_riker         = channel.empty()
    outputs_read_group_qualimap      = channel.empty()
    if ( enable.align ) {
        align_reads_out = ALIGN_READS(
            aligner,
            ch_reference_and_optional_fai,
            reads_to_preprocess,
            enable,
            ch_multiqc_files,
        )
        ch_read_group_alignments_indexed = align_reads_out.ch_read_group_alignments_indexed
        ch_multiqc_files                 = align_reads_out.ch_multiqc_files
        outputs_read_group               = ch_read_group_alignments_indexed
        outputs_read_group_flagstat      = align_reads_out.outputs_read_group_flagstat
        outputs_read_group_riker         = align_reads_out.outputs_read_group_riker
        outputs_read_group_qualimap      = align_reads_out.outputs_read_group_qualimap
    }

    // User input BAM/CRAMs enter here
    // We assume they are aligned, but enforce sorting/indexing to ensure compatibility
    ingest_bam_or_cram_out = INGEST_BAM_OR_CRAM(
        ch_input.bam_cram,
        ch_reference_and_optional_fai,
        enable,
        ch_multiqc_files
    )
    ch_multiqc_files      = ingest_bam_or_cram_out.ch_multiqc_files
    alignments_to_process = ch_read_group_alignments_indexed.mix(ingest_bam_or_cram_out.user_input_bam_cram)

    // Merge lane alignments to library level
    outputs_library               = channel.empty()
    outputs_library_flagstat      = channel.empty()
    outputs_library_riker         = channel.empty()
    outputs_library_qualimap      = channel.empty()
    if ( requires.merge_to_library ) {
        merge_to_library_out = MERGE_TO_LIBRARY(
            alignments_to_process,
            ch_reference_and_optional_fai,
            enable,
            ch_multiqc_files,
            'library',
        )
        alignments_to_process    = merge_to_library_out.ch_merged_alignments_indexed
        ch_multiqc_files         = merge_to_library_out.ch_multiqc_files
        outputs_library          = merge_to_library_out.outputs_alignments
        outputs_library_flagstat = merge_to_library_out.outputs_flagstat
        outputs_library_riker    = merge_to_library_out.outputs_riker
        outputs_library_qualimap = merge_to_library_out.outputs_qualimap
    }

    // Deduplicate library alignments
    outputs_mark_duplicates             = channel.empty()
    outputs_mark_duplicates_flagstat    = channel.empty()
    outputs_mark_duplicates_riker       = channel.empty()
    outputs_mark_duplicates_qualimap    = channel.empty()
    if ( enable.mark_duplicates ) {
        mark_duplicates_out = MARK_DUPLICATES(
            duplicate_marker,
            alignments_to_process,
            ch_reference_and_optional_fai,
            ch_multiqc_files,
            enable,
        )
        alignments_to_process            = mark_duplicates_out.ch_from_markdups_alignments_indexed
        ch_multiqc_files                 = mark_duplicates_out.ch_multiqc_files
        outputs_mark_duplicates          = alignments_to_process
            .mix(mark_duplicates_out.ch_from_markdups_metrics)
        outputs_mark_duplicates_flagstat = mark_duplicates_out.outputs_mark_duplicates_flagstat
        outputs_mark_duplicates_riker    = mark_duplicates_out.outputs_mark_duplicates_riker
        outputs_mark_duplicates_qualimap = mark_duplicates_out.outputs_mark_duplicates_qualimap
    }

    // Merge deduplicated library alignments to sample level
    outputs_sample               = channel.empty()
    outputs_sample_flagstat      = channel.empty()
    outputs_sample_riker         = channel.empty()
    outputs_sample_qualimap      = channel.empty()
    if ( requires.merge_to_sample ) {
        merge_to_sample_out = MERGE_TO_SAMPLE(
            alignments_to_process,
            ch_reference_and_optional_fai,
            enable,
            ch_multiqc_files,
            'sample',
        )
        alignments_to_process   = merge_to_sample_out.ch_merged_alignments_indexed
        ch_multiqc_files        = merge_to_sample_out.ch_multiqc_files
        outputs_sample          = merge_to_sample_out.outputs_alignments
        outputs_sample_flagstat = merge_to_sample_out.outputs_flagstat
        outputs_sample_riker    = merge_to_sample_out.outputs_riker
        outputs_sample_qualimap = merge_to_sample_out.outputs_qualimap
    }

    // Variant calling
    outputs_genome_chunks                         = channel.empty()
    outputs_variant_calls                         = channel.empty()
    outputs_mpileup                               = channel.empty()
    outputs_call_variants_bcftools_stats          = channel.empty()
    outputs_call_variants_vcftools_tstv_counts    = channel.empty()
    outputs_call_variants_vcftools_tstv_qual      = channel.empty()
    outputs_call_variants_vcftools_filter_summary = channel.empty()
    outputs_call_variants_vcftools_relatedness2   = channel.empty()
    if (enable.variant_calling) {
        def ch_alignments_for_calling = ch_sample_alignments_indexed
        CALL_VARIANTS(
            variant_caller,
            chunk_size,
            min_length,
            ch_alignments_for_calling,
            ch_samplesheet,
            ch_reference_and_optional_fai,
            dataset_name,
            enable,
            ch_multiqc_files,
        )
        ch_multiqc_files                              = CALL_VARIANTS.out.ch_multiqc_files
        outputs_genome_chunks                         = CALL_VARIANTS.out.ch_genome_chunks
        outputs_variant_calls                         = CALL_VARIANTS.out.ch_variant_calls_indexed
        outputs_mpileup                               = CALL_VARIANTS.out.ch_mpileup
        outputs_call_variants_bcftools_stats          = CALL_VARIANTS.out.outputs_bcftools_stats
        outputs_call_variants_vcftools_tstv_counts    = CALL_VARIANTS.out.outputs_vcftools_tstv_counts
        outputs_call_variants_vcftools_tstv_qual      = CALL_VARIANTS.out.outputs_vcftools_tstv_qual
        outputs_call_variants_vcftools_filter_summary = CALL_VARIANTS.out.outputs_vcftools_filter_summary
        outputs_call_variants_vcftools_relatedness2   = CALL_VARIANTS.out.outputs_vcftools_relatedness2
    }

    // Collate and save software versions
    def topic_versions = channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }
    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [process[process.lastIndexOf(':') + 1..-1], "  ${tool}: ${version}"]
        }
        .groupTuple(by: 0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }
    def ch_collated_versions = softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${outdir}/pipeline_info",
            name: 'biovat_software_' + 'mqc_' + 'versions.yml',
            sort: true,
            newLine: true,
        )

    // MultiQC
    ch_multiqc_files                          = ch_multiqc_files.mix(ch_collated_versions)
    def ch_summary_params                     = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    def ch_workflow_summary                   = channel.value(paramsSummaryMultiqc(ch_summary_params))
    ch_multiqc_files                          = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    def ch_multiqc_custom_methods_description = multiqc_methods_description
        ? file(multiqc_methods_description, checkIfExists: true)
        : file("${projectDir}/assets/biovat_methods_description.yml", checkIfExists: true)
    def ch_methods_description                = channel.value(methodsDescriptionText(ch_multiqc_custom_methods_description))
    ch_multiqc_files                          = ch_multiqc_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml', sort: true))
    multiqc_out = MULTIQC(
        ch_multiqc_files.flatten().collect().map { files ->
            [
                [id: 'biovat'],
                files,
                multiqc_config
                    ? file(multiqc_config, checkIfExists: true)
                    : file("${projectDir}/assets/multiqc_config.yml", checkIfExists: true),
                multiqc_logo ? file(multiqc_logo, checkIfExists: true) : [],
                [],
                [],
            ]
        }
    )

    emit:
    outputs_raw_read_qc
    outputs_trim_reads
    outputs_input_flagstat                        = ingest_bam_or_cram_out.outputs_input_flagstat
    outputs_input_riker                           = ingest_bam_or_cram_out.outputs_input_riker
    outputs_input_qualimap                        = ingest_bam_or_cram_out.outputs_input_qualimap
    outputs_read_group
    outputs_read_group_flagstat
    outputs_read_group_riker
    outputs_read_group_qualimap
    outputs_library
    outputs_library_flagstat
    outputs_library_riker
    outputs_library_qualimap
    outputs_mark_duplicates
    outputs_mark_duplicates_flagstat
    outputs_mark_duplicates_riker
    outputs_mark_duplicates_qualimap
    outputs_sample
    outputs_sample_flagstat
    outputs_sample_riker
    outputs_sample_qualimap
    outputs_genome_chunks
    outputs_variant_calls
    outputs_mpileup
    outputs_call_variants_bcftools_stats
    outputs_call_variants_vcftools_tstv_counts
    outputs_call_variants_vcftools_tstv_qual
    outputs_call_variants_vcftools_filter_summary
    outputs_call_variants_vcftools_relatedness2
    outputs_multiqc                               = multiqc_out.report.mix(multiqc_out.data, multiqc_out.plots)

}
