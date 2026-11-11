nextflow.enable.types = true

//
// Mark duplicates pipeline
//

include { PICARD_MARKDUPLICATES    } from '../../modules/nf-core/picard/markduplicates/main'
include { SAMTOOLS_SORMADUP        } from '../../modules/nf-core/samtools/sormadup/main'
include { SAMTOOLS_INDEX           } from '../../modules/nf-core/samtools/index/main'
include { workflow as ALIGNMENT_QC } from '../alignment_qc'
include { REFERENCE_VALUE          } from '../../subworkflows/local/utils_reference/main'
include { STAGE_HELP               } from '../../subworkflows/local/utils_stage_help/main'
include { checkStageInput          } from '../../subworkflows/local/utils_stage_help/main'
include { checkSampleFields        } from '../../subworkflows/local/utils_stage_help/main'
include { checkNoRepeats           } from '../../subworkflows/local/utils_stage_help/main'
include { checkQualimapCram        } from '../../subworkflows/local/utils_stage_help/main'
include { attachSingleEnd          } from '../../subworkflows/local/utils_stage_help/main'
include { stageError               } from '../../subworkflows/local/utils_stage_help/main'

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
    id        : String  // sample name
    meta      : Record  // read group information, requires library and pl
    alignment : Path    // BAM or CRAM file
    index     : Path    // index of the BAM or CRAM file
    single_end: Boolean // whether the reads are single-end
}

params {
    samplesheet      : Channel<AlignmentSample>? // alignments samplesheet (CSV with the columns sample, library_id, platform, single_end, alignment, index)
    alignments       : Channel<Alignment>? // alternative to the samplesheet: library alignments with their meta record, from a YAML or JSON file or a calling pipeline
    duplicate_marker : String = 'samtools' // duplicate marking tool to use ('picard'/'samtools')
    remove_duplicates: Boolean = false    // remove alignments identified as duplicates (else mark them)
    optical_distance : Integer = 100       // maximum pixel distance for optical duplicates
    fasta            : Value<Path>?        // reference fasta
    fai              : Value<Path>?        // fai index of the reference fasta, needed for CRAM output and Riker
    cram_format      : Boolean = false     // write CRAM instead of BAM
    align_qc         : Boolean = true      // run alignment QC on the deduplicated alignments
    riker            : Boolean = true      // run Riker in the alignment QC
    qualimap         : Boolean = false     // run Qualimap in the alignment QC
    help             : Boolean = false
    help_full        : Boolean = false
}

workflow {

    main:
    STAGE_HELP(params.help, params.help_full, "${moduleDir}/nextflow_schema.json", 'nextflow run pipelines/mark_duplicates --samplesheet alignments.csv --fasta reference.fasta')
    checkStageInput(params.samplesheet, params.alignments, 'alignments')
    checkQualimapCram(params.cram_format, params.align_qc, params.qualimap)
    alignments = channel.empty()
    if ( params.samplesheet ) {
        alignments = params.samplesheet.map { s ->
            checkSampleFields(s.sample, s.library_id, null, s.platform)
            if ( s.library_id == null ) {
                stageError "Marking duplicates needs a library_id for every row of the samplesheet (missing for sample '${s.sample}')"
            }
            record(id: s.sample, meta: record(library: s.library_id, pl: s.platform) as Record, alignment: s.alignment, index: s.index, single_end: s.single_end)
        }
    } else {
        alignments = params.alignments
    }
    // Duplicates are marked per library, so a library is one alignment. The samplesheet has no read group columns
    alignments = alignments.toList().flatMap { rows ->
        checkNoRepeats(rows, { row -> [ row.id, row.meta.library, row.meta.pl ] }, "Marking duplicates needs one alignment per library. Merge the alignments of a library first (the merge stage).")
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
                        id                        : aln.id,
                        meta                      : aln.meta,
                        reads                     : aln.alignment,
                        fasta                     : ref.fasta,
                        fai                       : ref.fai,
                        picard_markduplicates_args: [
                            // Always report optical metrics, tag the BAM if retaining duplicates
                            params.remove_duplicates ? '--REMOVE_DUPLICATES true' : '--TAGGING_POLICY All',
                            "--OPTICAL_DUPLICATE_PIXEL_DISTANCE ${params.optical_distance}"
                        ].findAll { arg -> arg != '' }.join(' '),
                        output_prefix             : "${aln.id}_${aln.meta.library}_${aln.meta.pl}_markdup"
                    )
                }
        )
        indexed = SAMTOOLS_INDEX(
            picard.map { out -> record(id: out.id, meta: out.meta, input: out.bam ?: out.cram, samtools_index_args: '--csi') }
        )
        markdup_alignments = picard
            .map { out -> record(key: record(id: out.id, meta: out.meta), id: out.id, meta: out.meta, alignment: out.bam ?: out.cram) }
            .join(indexed.map { out -> record(key: record(id: out.id, meta: out.meta), index: out.index) }, by: 'key')
            .map { a -> record(id: a.id, meta: a.meta, alignment: a.alignment, index: a.index) }
        markdup_metrics    = picard.map { out -> record(meta: out.meta, metrics: out.metrics) }
    } else if ( params.duplicate_marker == 'samtools' ) {
        sormadup = SAMTOOLS_SORMADUP(
            alignments
                .combine(reference)
                .map { aln, ref ->
                    record(
                        id                   : aln.id,
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
                        output_prefix        : "${aln.id}_${aln.meta.library}_${aln.meta.pl}_markdup"
                    )
                }
        )
        markdup_alignments = sormadup.map { out ->
            record(id: out.id, meta: out.meta, alignment: out.bam ?: out.cram, index: out.csi ?: out.crai)
        }
        markdup_metrics    = sormadup.map { out -> record(meta: out.meta, metrics: out.metrics) }
    } else {
        error "Unknown duplicate marker '${params.duplicate_marker}', expected picard or samtools"
    }

    // The marked alignment gets its single_end back from the alignment it came from
    marked_alignments = attachSingleEnd(markdup_alignments, alignments)
        .map { j -> record(id: j.out.id, meta: j.out.meta, alignment: j.out.alignment, index: j.out.index, single_end: j.single_end) }

    // MARK_DUPLICATES:ALIGNMENT_QC
    qc_flagstat      = channel.empty()
    qc_riker         = channel.empty()
    qc_qualimap      = channel.empty()
    qc_multiqc_files = channel.empty()
    if ( params.align_qc ) {
        // The reference has its fai index when this stage needed it. Pass it on, so that it is not created twice
        qc_fai = params.fai
        if ( params.riker || params.cram_format ) {
            qc_fai = reference.map { ref -> ref.fai }
        }
        alignment_qc = ALIGNMENT_QC(
            record(
                alignments: marked_alignments,
                level     : 'markdup',
                fasta     : params.fasta,
                fai       : qc_fai,
                riker     : params.riker,
                qualimap  : params.qualimap
            )
        )
        qc_flagstat      = alignment_qc.flagstat
        qc_riker         = alignment_qc.riker
        qc_qualimap      = alignment_qc.qualimap
        qc_multiqc_files = alignment_qc.multiqc_files
    }

    publish:
    alignments    = marked_alignments  // record(id, meta, alignment, index, single_end)
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
