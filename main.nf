#!/usr/bin/env nextflow
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    BioVAT
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Github : https://github.com/NBISweden/biovat

    BioVAT composes the stage pipelines in pipelines/, each of which can also be run on its own.
    This pipeline can be run directly or included by another pipeline:
        include { workflow as BIOVAT } from './biovat/main.nf'
----------------------------------------------------------------------------------------
*/

nextflow.enable.types = true

include { PIPELINE_INITIALISATION    } from './subworkflows/local/utils_nfcore_biovat_pipeline'
include { PIPELINE_COMPLETION        } from './subworkflows/local/utils_nfcore_biovat_pipeline'
include { readSamplesheet            } from './subworkflows/local/utils_nfcore_biovat_pipeline'
include { readSampleMetadata         } from './subworkflows/local/utils_nfcore_biovat_pipeline'
include { sampleToRow                } from './subworkflows/local/utils_nfcore_biovat_pipeline'
include { validateSamplesheetRows    } from './subworkflows/local/utils_nfcore_biovat_pipeline'
include { rikerActive                } from './subworkflows/local/utils_nfcore_biovat_pipeline'
include { REFERENCE_UTILS            } from './subworkflows/local/utils_reference/main'
include { paramsSummaryMap           } from 'plugin/nf-schema'
include { paramsSummaryMultiqc       } from './subworkflows/nf-core/utils_nfcore_pipeline'

// Each analysis stage is a pipeline, composed here with regular dataflow logic
include { workflow as READ_QC            } from './pipelines/read_qc'
include { workflow as TRIM_READS         } from './pipelines/trim_reads'
include { workflow as ALIGN_READS        } from './pipelines/align_reads'
include { workflow as INGEST_BAM_OR_CRAM } from './pipelines/ingest_bam_or_cram'
include { workflow as MERGE_TO_LIBRARY   } from './pipelines/merge'
include { workflow as MARK_DUPLICATES    } from './pipelines/mark_duplicates'
include { workflow as MERGE_TO_SAMPLE    } from './pipelines/merge'
include { workflow as CALL_VARIANTS      } from './pipelines/call_variants'
include { workflow as MULTIQC            } from './pipelines/multiqc'

// A row of the samplesheet
record Sample {
    sample     : String
    library_id : String
    flowcell_id: String
    lane       : Integer
    platform   : String
    fastq_1    : Path?
    fastq_2    : Path?
    bam        : Path?
    single_end : Boolean?
}

// Pipeline parameters and their defaults. Parameters that only the config reads are defined in nextflow.config
params {

    // Input options
    input                       : String?              // path to the samplesheet, validated against assets/schema_input.json
    samplesheet                 : Channel<Sample>?     // alternative to input for pipelines that include BioVAT
    sample_metadata             : String?              // path to the sample metadata sheet, validated against assets/schema_sample_metadata.json
    reference                   : Path?

    // Workflow stage gating options
    enable_raw_read_qc          : Boolean = true
    enable_trim                 : Boolean = true
    enable_align                : Boolean = true
    enable_align_qc             : Boolean = true
    enable_mark_duplicates      : Boolean = true
    enable_variant_calling      : Boolean = true
    enable_variant_qc           : Boolean = true

    // Read trimming options
    adapter_fasta               : Path?
    enable_save_trimmed_fail    : Boolean = false
    enable_save_merged          : Boolean = false

    // Alignment options
    aligner                     : String = 'bwa-mem3'
    enable_cram_format          : Boolean = false

    // Alignment QC options
    enable_riker                : Boolean = true
    enable_qualimap             : Boolean = false

    // Duplicate marking options
    duplicate_marker            : String = 'samtools'
    enable_remove_duplicates    : Boolean = false
    optical_distance            : Integer = 100

    // Variant calling options
    callset_prefix              : String = 'all_samples'
    variant_caller              : String = 'bcftools_multisample'
    chunk_size                  : Integer?
    min_length                  : Integer = 1000

    // BCFtools multi-sample variant calling options
    enable_save_mpileup         : Boolean = false
    bcftools_mpileup_extra      : String = '--no-BAQ'
    bcftools_call_extra         : String = '--variants-only'

    // MultiQC options
    multiqc_config              : Path?
    multiqc_title               : String?
    multiqc_logo                : Path?
    multiqc_methods_description : Path?

    // Boilerplate options
    outdir                      : String?
    monochrome_logs             : Boolean = false
    help                        : Boolean = false
    help_full                   : Boolean = false
    show_hidden                 : Boolean = false
    version                     : Boolean = false

    // Schema validation. Set to false when including BioVAT in another pipeline
    validate_params             : Boolean = true

}

// Entry workflow
workflow {

    main:
    // Gating parameters, passed as a single record
    enable = record(
        raw_read_qc      : params.enable_raw_read_qc,
        trim             : params.enable_trim,
        align            : params.enable_align,
        align_qc         : params.enable_align_qc,
        mark_duplicates  : params.enable_mark_duplicates,
        variant_calling  : params.enable_variant_calling,
        variant_qc       : params.enable_variant_qc,
        cram_format      : params.enable_cram_format,
        riker            : params.enable_riker,
        qualimap         : params.enable_qualimap
    )

    // nf-schema cannot validate a channel param (it never finishes), so validation is skipped when a calling
    // pipeline passes a samplesheet channel. The command line route (--input) is validated
    if ( params.samplesheet && params.validate_params ) {
        log.warn "Parameter validation is skipped when a samplesheet channel is given. Set validate_params to false to silence this warning"
    }

    PIPELINE_INITIALISATION(
        params.version,
        params.validate_params && !params.samplesheet,
        params.monochrome_logs,
        args,
        params.outdir,
        params.help,
        params.help_full,
        params.show_hidden,
        enable
    )

    // 'requires' is a record of internal dependency relationships
    // MERGE_TO_LIBRARY (readgroup -> library) and MERGE_TO_SAMPLE (library -> sample, post-deduplication)
    // are triggered when a downstream consumer needs alignments merged to respective levels
    merge_to_library = enable.mark_duplicates
    merge_to_sample  = enable.variant_calling
    merge_active     = merge_to_library || merge_to_sample
    // .fai is used for certain CRAM processes, and unconditionally by riker and variant calling. The samplesheet rows aren't
    // visible here, so assume BAM/CRAM input rows may exist (ALIGNMENT_QC runs on them during ingestion)
    requires = record(
        merge_to_library: merge_to_library,
        merge_to_sample : merge_to_sample,
        // Providing --sample_metadata groups samples into populations during bcftools_multisample variant calling
        group_samples   : enable.variant_calling && params.variant_caller == 'bcftools_multisample' && params.sample_metadata != null,
        // GATK tools need a sequence dictionary alongside the reference fasta
        dict            : enable.variant_calling && params.variant_caller == 'gatk',
        fai             : (enable.cram_format && merge_active) || rikerActive(enable, true) || enable.variant_calling
    )

    // Samplesheet rows as records: record(meta, files). They come from the --input file (validated by nf-schema)
    // or from a samplesheet channel given by a calling pipeline
    sample_metadata_rows = readSampleMetadata(params.sample_metadata)
    if ( params.input && params.samplesheet ) {
        error "Provide either --input or a samplesheet channel, not both"
    }
    if ( params.input ) {
        rows = channel.fromList(readSamplesheet(params.input))
    } else if ( params.samplesheet ) {
        rows = params.samplesheet.map { sample -> sampleToRow(sample) }
    } else {
        error "Missing required parameter --input"
    }
    // Check the rows together, and release them only when the checks have passed
    samplesheet = rows
        .map { row -> record(meta: record(row[0]), files: row[1]) }
        .toList()
        .flatMap { list ->
            validateSamplesheetRows(
                list,
                sample_metadata_rows,
                enable,
                record(has_reference: params.reference != null, variant_caller: params.variant_caller, sample_metadata: params.sample_metadata != null)
            )
        }
    fastq_rows    = samplesheet.filter { row -> row.meta.input_type == 'fastq' }
    bam_cram_rows = samplesheet.filter { row -> row.meta.input_type == 'bam_cram' }
    reads         = fastq_rows.map { row -> record(meta: row.meta, reads: row.files) }

    // Reference: the fasta and, if needed, its fai index. Stages take them as separate Value params
    fasta = null
    fai   = null
    dict  = null
    if ( params.reference ) {
        reference = REFERENCE_UTILS(params.reference, requires)
        fasta     = reference.map { ref -> ref.fasta }
        if ( requires.fai ) {
            fai = reference.map { ref -> ref.fai }
        }
        if ( requires.dict ) {
            dict = reference.map { ref -> ref.dict }
        }
    }

    multiqc_files = channel.empty()

    // Raw read quality checks
    raw_read_qc = channel.empty()
    if ( enable.raw_read_qc ) {
        read_qc = READ_QC(record(reads: reads))
        raw_read_qc   = read_qc.fastqc
        multiqc_files = multiqc_files.mix(read_qc.multiqc_files)
    }

    // Trim reads
    trim_reads = channel.empty()
    if ( enable.trim ) {
        trim = TRIM_READS(
            record(
                reads            : reads,
                adapter_fasta    : params.adapter_fasta,
                save_trimmed_fail: params.enable_save_trimmed_fail,
                save_merged      : params.enable_save_merged
            )
        )
        trim_reads    = trim.fastp
        reads         = trim.trimmed_reads.map { r -> record(meta: r.meta, reads: r.reads) }
        multiqc_files = multiqc_files.mix(trim.multiqc_files)
    }

    // Align reads
    read_group_alignments = channel.empty()
    read_group_flagstat   = channel.empty()
    read_group_riker      = channel.empty()
    read_group_qualimap   = channel.empty()
    if ( enable.align ) {
        align = ALIGN_READS(
            record(
                reads      : reads,
                aligner    : params.aligner,
                fasta      : fasta,
                fai        : fai,
                cram_format: enable.cram_format,
                align_qc   : enable.align_qc,
                riker      : enable.riker,
                qualimap   : enable.qualimap
            )
        )
        read_group_alignments = align.alignments
        read_group_flagstat   = align.flagstat
        read_group_riker      = align.riker
        read_group_qualimap   = align.qualimap
        multiqc_files         = multiqc_files.mix(align.multiqc_files)
    }

    // User input BAM/CRAMs enter here
    // We assume they are aligned, but enforce sorting/indexing to ensure compatibility
    ingest = INGEST_BAM_OR_CRAM(
        record(
            bam_cram   : bam_cram_rows.map { row -> record(meta: row.meta, bam_cram: row.files[0]) },
            fasta      : fasta,
            fai        : fai,
            // validateReferenceRequirements has already required --reference for the rows that need it, so without
            // one no BAM/CRAM row needs Riker or CRAM decoding (a run without BAM/CRAM rows must work without a reference)
            cram_format: enable.cram_format && params.reference != null,
            align_qc   : enable.align_qc,
            riker      : enable.riker && params.reference != null,
            qualimap   : enable.qualimap
        )
    )
    multiqc_files         = multiqc_files.mix(ingest.multiqc_files)
    alignments_to_process = read_group_alignments
        .mix(ingest.alignments)
        .map { a -> record(meta: a.meta, alignment: a.alignment, index: a.index) }

    // Merge lane alignments to library level
    library_alignments = channel.empty()
    library_flagstat   = channel.empty()
    library_riker      = channel.empty()
    library_qualimap   = channel.empty()
    if ( requires.merge_to_library ) {
        merge_library = MERGE_TO_LIBRARY(
            record(
                alignments : alignments_to_process,
                level      : 'library',
                fasta      : fasta,
                fai        : fai,
                cram_format: enable.cram_format,
                align_qc   : enable.align_qc,
                riker      : enable.riker,
                qualimap   : enable.qualimap
            )
        )
        alignments_to_process = merge_library.alignments.map { a -> record(meta: a.meta, alignment: a.alignment, index: a.index) }
        library_alignments    = merge_library.merged
        library_flagstat      = merge_library.flagstat
        library_riker         = merge_library.riker
        library_qualimap      = merge_library.qualimap
        multiqc_files         = multiqc_files.mix(merge_library.multiqc_files)
    }

    // Deduplicate library alignments
    mark_duplicates_alignments = channel.empty()
    mark_duplicates_flagstat   = channel.empty()
    mark_duplicates_riker      = channel.empty()
    mark_duplicates_qualimap   = channel.empty()
    if ( enable.mark_duplicates ) {
        markdup = MARK_DUPLICATES(
            record(
                alignments       : alignments_to_process,
                duplicate_marker : params.duplicate_marker,
                remove_duplicates: params.enable_remove_duplicates,
                optical_distance : params.optical_distance,
                fasta            : fasta,
                fai              : fai,
                cram_format      : enable.cram_format,
                align_qc         : enable.align_qc,
                riker            : enable.riker,
                qualimap         : enable.qualimap
            )
        )
        alignments_to_process      = markdup.alignments.map { a -> record(meta: a.meta, alignment: a.alignment, index: a.index) }
        mark_duplicates_alignments = markdup.alignments.mix(markdup.metrics)
        mark_duplicates_flagstat   = markdup.flagstat
        mark_duplicates_riker      = markdup.riker
        mark_duplicates_qualimap   = markdup.qualimap
        multiqc_files              = multiqc_files.mix(markdup.multiqc_files)
    }

    // Merge deduplicated library alignments to sample level
    sample_alignments = channel.empty()
    sample_flagstat   = channel.empty()
    sample_riker      = channel.empty()
    sample_qualimap   = channel.empty()
    if ( requires.merge_to_sample ) {
        merge_sample = MERGE_TO_SAMPLE(
            record(
                alignments : alignments_to_process,
                level      : 'sample',
                fasta      : fasta,
                fai        : fai,
                cram_format: enable.cram_format,
                align_qc   : enable.align_qc,
                riker      : enable.riker,
                qualimap   : enable.qualimap
            )
        )
        alignments_to_process = merge_sample.alignments.map { a -> record(meta: a.meta, alignment: a.alignment, index: a.index) }
        sample_alignments     = merge_sample.merged
        sample_flagstat   = merge_sample.flagstat
        sample_riker      = merge_sample.riker
        sample_qualimap   = merge_sample.qualimap
        multiqc_files     = multiqc_files.mix(merge_sample.multiqc_files)
    }

    // Variant calling
    genome_chunks = channel.empty()
    variant_calls = channel.empty()
    mpileup       = channel.empty()
    bcftools_stats                = channel.empty()
    vcftools_tstv_counts          = channel.empty()
    vcftools_tstv_qual            = channel.empty()
    vcftools_filter_summary       = channel.empty()
    vcftools_relatedness2         = channel.empty()
    if ( enable.variant_calling ) {
        call_variants = CALL_VARIANTS(
            record(
                alignments            : alignments_to_process,
                sample_metadata       : channel.fromList(sample_metadata_rows).map { meta -> record(sample: meta.id, population: meta.population) },
                variant_caller        : params.variant_caller,
                chunk_size            : params.chunk_size,
                min_length            : params.min_length,
                callset_prefix        : params.callset_prefix,
                group_samples         : requires.group_samples,
                save_mpileup          : params.enable_save_mpileup,
                bcftools_mpileup_extra: params.bcftools_mpileup_extra,
                bcftools_call_extra   : params.bcftools_call_extra,
                fasta                 : fasta,
                fai                   : fai,
                dict                  : dict,
                variant_qc            : enable.variant_qc
            )
        )
        genome_chunks = channel.empty().mix(call_variants.genome_chunks)
        variant_calls = call_variants.variant_calls
        mpileup       = call_variants.mpileup
        multiqc_files = multiqc_files.mix(call_variants.multiqc_files)
        bcftools_stats          = call_variants.bcftools_stats
        vcftools_tstv_counts    = call_variants.vcftools_tstv_counts
        vcftools_tstv_qual      = call_variants.vcftools_tstv_qual
        vcftools_filter_summary = call_variants.vcftools_filter_summary
        vcftools_relatedness2   = call_variants.vcftools_relatedness2
    }

    // MultiQC and software versions
    multiqc = MULTIQC(
        record(
            multiqc_files              : multiqc_files.map { f -> record(file: f) },
            multiqc_config             : params.multiqc_config,
            multiqc_logo               : params.multiqc_logo,
            multiqc_title              : params.multiqc_title,
            multiqc_methods_description: params.multiqc_methods_description,
            workflow_summary           : paramsSummaryMultiqc(paramsSummaryMap(workflow, parameters_schema: "${moduleDir}/nextflow_schema.json"))
        )
    )

    PIPELINE_COMPLETION(params.monochrome_logs)

    publish:
    outputs_raw_read_qc              = raw_read_qc
    outputs_input_flagstat           = ingest.flagstat
    outputs_input_riker              = ingest.riker
    outputs_input_qualimap           = ingest.qualimap
    outputs_trim_reads               = trim_reads
    outputs_read_group               = read_group_alignments
    outputs_read_group_flagstat      = read_group_flagstat
    outputs_read_group_riker         = read_group_riker
    outputs_read_group_qualimap      = read_group_qualimap
    outputs_library                  = library_alignments
    outputs_library_flagstat         = library_flagstat
    outputs_library_riker            = library_riker
    outputs_library_qualimap         = library_qualimap
    outputs_mark_duplicates          = mark_duplicates_alignments
    outputs_mark_duplicates_flagstat = mark_duplicates_flagstat
    outputs_mark_duplicates_riker    = mark_duplicates_riker
    outputs_mark_duplicates_qualimap = mark_duplicates_qualimap
    outputs_sample                   = sample_alignments
    outputs_sample_flagstat          = sample_flagstat
    outputs_sample_riker             = sample_riker
    outputs_sample_qualimap          = sample_qualimap
    outputs_genome_chunks                         = genome_chunks
    outputs_variant_calls                         = variant_calls
    outputs_mpileup                               = mpileup
    outputs_call_variants_bcftools_stats          = bcftools_stats
    outputs_call_variants_vcftools_tstv_counts    = vcftools_tstv_counts
    outputs_call_variants_vcftools_tstv_qual      = vcftools_tstv_qual
    outputs_call_variants_vcftools_filter_summary = vcftools_filter_summary
    outputs_call_variants_vcftools_relatedness2   = vcftools_relatedness2
    outputs_multiqc                  = multiqc.multiqc
    outputs_versions                 = multiqc.versions

}

output {

    // READ_QC
    outputs_raw_read_qc: Channel<Record> {
        path '01_input_checks/reads/fastqc'
    }
    // INGEST_BAM_OR_CRAM
    outputs_input_flagstat: Channel<Record> {
        path '01_input_checks/reads/samtools_flagstat'
    }
    outputs_input_riker: Channel<Record> {
        path '01_input_checks/reads/riker'
    }
    outputs_input_qualimap: Channel<Record> {
        path '01_input_checks/reads/qualimap'
    }
    // TRIM_READS
    outputs_trim_reads: Channel<Record> {
        path '02_read_trimming'
    }
    // ALIGN_READS
    outputs_read_group: Channel<Record> {
        path '03_read_alignment'
    }
    outputs_read_group_flagstat: Channel<Record> {
        path '03_read_alignment/qc/samtools_flagstat'
    }
    outputs_read_group_riker: Channel<Record> {
        path '03_read_alignment/qc/riker'
    }
    outputs_read_group_qualimap: Channel<Record> {
        path '03_read_alignment/qc/qualimap'
    }
    // MERGE_TO_LIBRARY
    outputs_library: Channel<Record> {
        path { aln ->
            // Includes library and platform to avoid file name collisions
            aln.alignment >> "04_merged_libraries/${aln.meta.id}_${aln.meta.library}_${aln.meta.pl}.${aln.alignment.extension}"
            aln.index     >> "04_merged_libraries/${aln.meta.id}_${aln.meta.library}_${aln.meta.pl}.${aln.alignment.extension}.${aln.index.extension}"
        }
    }
    outputs_library_flagstat: Channel<Record> {
        path '04_merged_libraries/qc/samtools_flagstat'
    }
    outputs_library_riker: Channel<Record> {
        path '04_merged_libraries/qc/riker'
    }
    outputs_library_qualimap: Channel<Record> {
        path '04_merged_libraries/qc/qualimap'
    }
    // MARK_DUPLICATES
    outputs_mark_duplicates: Channel<Record> {
        path '05_duplicate_processed'
    }
    outputs_mark_duplicates_flagstat: Channel<Record> {
        path '05_duplicate_processed/qc/samtools_flagstat'
    }
    outputs_mark_duplicates_riker: Channel<Record> {
        path '05_duplicate_processed/qc/riker'
    }
    outputs_mark_duplicates_qualimap: Channel<Record> {
        path '05_duplicate_processed/qc/qualimap'
    }
    // MERGE_TO_SAMPLE
    outputs_sample: Channel<Record> {
        path { aln ->
            // Includes platform to avoid file name collisions
            aln.alignment >> "06_merged_samples/${aln.meta.id}_${aln.meta.pl}.${aln.alignment.extension}"
            aln.index     >> "06_merged_samples/${aln.meta.id}_${aln.meta.pl}.${aln.alignment.extension}.${aln.index.extension}"
        }
    }
    outputs_sample_flagstat: Channel<Record> {
        path '06_merged_samples/qc/samtools_flagstat'
    }
    outputs_sample_riker: Channel<Record> {
        path '06_merged_samples/qc/riker'
    }
    outputs_sample_qualimap: Channel<Record> {
        path '06_merged_samples/qc/qualimap'
    }
    // VARIANT_CALLING
    outputs_genome_chunks: Channel<Record> {
        path '07_variant_calls/genome_chunk_bed_files'
    }
    outputs_variant_calls: Channel<Record> {
        path { call ->
            // Named from the group meta, as a single-chunk call skips BCFTOOLS_CONCAT and keeps its chunk file name
            call.vcf   >> "07_variant_calls/${call.meta.id}.vcf.gz"
            call.index >> "07_variant_calls/${call.meta.id}.vcf.gz.${call.index.extension}"
        }
    }
    outputs_mpileup: Channel<Record> {
        path '07_variant_calls'
    }
    outputs_call_variants_bcftools_stats: Channel<Record> {
        path '07_variant_calls/qc/bcftools_stats'
    }
    outputs_call_variants_vcftools_tstv_counts: Channel<Record> {
        path '07_variant_calls/qc/vcftools'
    }
    outputs_call_variants_vcftools_tstv_qual: Channel<Record> {
        path '07_variant_calls/qc/vcftools'
    }
    outputs_call_variants_vcftools_filter_summary: Channel<Record> {
        path '07_variant_calls/qc/vcftools'
    }
    outputs_call_variants_vcftools_relatedness2: Channel<Record> {
        path '07_variant_calls/qc/vcftools'
    }
    // MultiQC
    outputs_multiqc: Value<Record> {
        path 'multiqc'
    }
    outputs_versions: Channel<Path> {
        path 'pipeline_info'
    }

}
