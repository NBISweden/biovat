nextflow.enable.types = true

//
// Mark duplicates pipeline
//

include { PICARD_MARKDUPLICATES } from '../../modules/nf-core/picard/markduplicates/main'
include { SAMTOOLS_SORMADUP     } from '../../modules/nf-core/samtools/sormadup/main'
include { SAMTOOLS_INDEX        } from '../../modules/nf-core/samtools/index/main'
include { ALIGNMENT_QC          } from '../../subworkflows/local/alignment_qc/main'
include { REFERENCE_VALUE       } from '../../subworkflows/local/utils_reference/main'
include { STAGE_HELP            } from '../../subworkflows/local/utils_stage_help/main'

// A row of the alignments samplesheet
record AlignmentSample {
    sample    : String   // sample name
    library_id: String?  // library, needed to merge or deduplicate at library level
    platform  : String   // sequencing platform
    single_end: Boolean  // whether the reads are single-end
    alignment : Path     // BAM or CRAM file
    index     : Path     // index of the BAM or CRAM file
}

record Alignment {
    meta     : Record // sample information, requires id, library and pl
    alignment: Path   // BAM or CRAM file
    index    : Path   // index of the BAM or CRAM file
}

params {
    samplesheet     : Channel<AlignmentSample>? // alignments samplesheet (CSV with the columns sample, library_id, platform, single_end, alignment, index)
    alignments      : Channel<Alignment>? // alternative to the samplesheet: library alignments with their meta record, from a YAML or JSON file or a calling pipeline
    duplicate_marker: String = 'samtools' // duplicate marking tool to use ('picard'/'samtools')
    remove_duplicates: Boolean = false    // remove alignments identified as duplicates (else mark them)
    optical_distance: Integer = 100       // maximum pixel distance for optical duplicates
    fasta           : Value<Path>?        // reference fasta
    fai             : Value<Path>?        // fai index of the reference fasta, needed for CRAM output and Riker
    cram_format     : Boolean = false     // write CRAM instead of BAM
    align_qc        : Boolean = true      // run alignment QC on the deduplicated alignments
    riker           : Boolean = true      // run Riker in the alignment QC
    qualimap        : Boolean = false     // run Qualimap in the alignment QC
    help            : Boolean = false
    help_full       : Boolean = false
}

workflow {

    main:
    STAGE_HELP(params.help, params.help_full, "${moduleDir}/nextflow_schema.json", 'nextflow run pipelines/mark_duplicates --samplesheet alignments.csv --fasta reference.fasta')
    if ( params.samplesheet && params.alignments ) {
        error "Provide either --samplesheet or --alignments, not both"
    }
    if ( !params.samplesheet && !params.alignments ) {
        error "Missing required parameter --samplesheet"
    }
    alignments = channel.empty()
    if ( params.samplesheet ) {
        alignments = params.samplesheet.map { s ->
            if ( s.library_id == null ) {
                error "Marking duplicates needs a library_id for every row of the samplesheet (missing for sample '${s.sample}')"
            }
            def meta = [ id: s.sample, library: s.library_id, pl: s.platform, single_end: s.single_end ]
            record(meta: record(meta), alignment: s.alignment, index: s.index)
        }
    } else {
        alignments = params.alignments.map { a -> record(meta: a.meta, alignment: a.alignment, index: a.index) }
    }
    reference = REFERENCE_VALUE(params.fasta, params.fai, (params.align_qc && params.riker) || params.cram_format)

    markdup_alignments = channel.empty()
    markdup_metrics    = channel.empty()
    if ( params.duplicate_marker == 'picard' ) {
        picard = PICARD_MARKDUPLICATES(
            alignments
                .combine(reference)
                .map { aln, ref ->
                    record(
                        id                        : aln.meta.id,
                        meta                      : aln.meta,
                        reads                     : aln.alignment,
                        fasta                     : ref.fasta,
                        fai                       : ref.fai,
                        picard_markduplicates_args: [
                            // Always report optical metrics, tag the BAM if retaining duplicates
                            params.remove_duplicates ? '--REMOVE_DUPLICATES true' : '--TAGGING_POLICY All',
                            "--OPTICAL_DUPLICATE_PIXEL_DISTANCE ${params.optical_distance}"
                        ].findAll { arg -> arg != '' }.join(' '),
                        output_prefix             : "${aln.meta.id}_${aln.meta.library}_${aln.meta.pl}_markdup"
                    )
                }
        )
        indexed = SAMTOOLS_INDEX(
            picard.map { out -> record(id: out.id, meta: out.meta, input: out.bam ?: out.cram, samtools_index_args: '--csi') }
        )
        markdup_alignments = picard
            .map { out -> record(meta: out.meta, alignment: out.bam ?: out.cram) }
            .join(indexed.map { out -> record(meta: out.meta, index: out.index) }, by: 'meta')
        markdup_metrics    = picard.map { out -> record(meta: out.meta, metrics: out.metrics) }
    } else if ( params.duplicate_marker == 'samtools' ) {
        sormadup = SAMTOOLS_SORMADUP(
            alignments
                .combine(reference)
                .map { aln, ref ->
                    record(
                        id                   : aln.meta.id,
                        meta                 : aln.meta,
                        input                : aln.alignment,
                        fasta                : ref.fasta,
                        fai                  : ref.fai,
                        samtools_cat_args    : null,
                        samtools_collate_args: null,
                        samtools_fixmate_args: null,
                        samtools_sort_args   : null,
                        samtools_markdup_args: [
                            params.remove_duplicates ? '-r' : '',
                            params.cram_format ? '--output-fmt cram' : '',
                            // Always report optical metrics, BAM tagging is automatic
                            "-d ${params.optical_distance}",
                            '--write-index'
                        ].findAll { arg -> arg != '' }.join(' '),
                        output_prefix        : "${aln.meta.id}_${aln.meta.library}_${aln.meta.pl}_markdup"
                    )
                }
        )
        markdup_alignments = sormadup.map { out ->
            record(meta: out.meta, alignment: out.bam ?: out.cram, index: out.csi ?: out.crai)
        }
        markdup_metrics    = sormadup.map { out -> record(meta: out.meta, metrics: out.metrics) }
    } else {
        error "Unknown duplicate marker '${params.duplicate_marker}', expected picard or samtools"
    }

    // MARK_DUPLICATES:ALIGNMENT_QC
    qc_flagstat      = channel.empty()
    qc_riker         = channel.empty()
    qc_qualimap      = channel.empty()
    qc_multiqc_files = channel.empty()
    if ( params.align_qc ) {
        alignment_qc = ALIGNMENT_QC(markdup_alignments, reference, params.riker, params.qualimap, 'markdup')
        qc_flagstat      = alignment_qc.flagstat
        qc_riker         = alignment_qc.riker
        qc_qualimap      = alignment_qc.qualimap
        qc_multiqc_files = alignment_qc.multiqc_files
    }

    publish:
    alignments    = markdup_alignments // record(meta, alignment, index)
    metrics       = markdup_metrics    // record(meta, metrics)
    flagstat      = qc_flagstat
    riker         = qc_riker
    qualimap      = qc_qualimap
    multiqc_files = qc_multiqc_files.mix(markdup_metrics.map { m -> m.metrics })

}

output {
    alignments   : Channel<Record> { path 'alignments' }
    metrics      : Channel<Record> { path 'metrics' }
    flagstat     : Channel<Record> { path 'flagstat' }
    riker        : Channel<Record> { path 'riker' }
    qualimap     : Channel<Record> { path 'qualimap' }
    multiqc_files: Channel<Path> { path 'multiqc_files' }
}
