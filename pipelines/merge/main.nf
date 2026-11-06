nextflow.enable.types = true

//
// Merge pipeline: merges alignments to library level or to sample level
//

include { SAMTOOLS_MERGE           } from '../../modules/nf-core/samtools/merge/main'
include { workflow as ALIGNMENT_QC } from '../alignment_qc'
include { REFERENCE_VALUE          } from '../../subworkflows/local/utils_reference/main'
include { STAGE_HELP               } from '../../subworkflows/local/utils_stage_help/main'
include { checkStageInput          } from '../../subworkflows/local/utils_stage_help/main'
include { checkSampleFields        } from '../../subworkflows/local/utils_stage_help/main'
include { checkReferenceForInput   } from '../../subworkflows/local/utils_stage_help/main'
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
    meta      : Record  // read group information, requires pl (and library to merge at library level)
    alignment : Path    // BAM or CRAM file
    index     : Path    // index of the BAM or CRAM file
    single_end: Boolean // whether the reads are single-end
}

params {
    samplesheet: Channel<AlignmentSample>? // alignments samplesheet (CSV with the columns sample, library_id, platform, single_end, alignment, index)
    alignments : Channel<Alignment>? // alternative to the samplesheet: alignments with their meta record, from a YAML or JSON file or a calling pipeline
    level      : String = 'library'  // merge level, controls grouping and QC prefix ('library'/'sample')
    fasta      : Value<Path>?        // reference fasta, needed for CRAM output
    fai        : Value<Path>?        // fai index of the reference fasta, needed for CRAM output and Riker
    cram_format: Boolean = false    // write CRAM instead of BAM
    align_qc   : Boolean = true      // run alignment QC on the merged alignments
    riker      : Boolean = true      // run Riker in the alignment QC
    qualimap   : Boolean = false     // run Qualimap in the alignment QC
    help       : Boolean = false
    help_full  : Boolean = false
}

workflow {

    main:
    STAGE_HELP(params.help, params.help_full, "${moduleDir}/nextflow_schema.json", 'nextflow run pipelines/merge --samplesheet alignments.csv --level library --fasta reference.fasta')
    if ( !(params.level in [ 'library', 'sample' ]) ) {
        error "Unknown merge level '${params.level}', expected library or sample"
    }
    checkStageInput(params.samplesheet, params.alignments, 'alignments')
    checkQualimapCram(params.cram_format, params.align_qc, params.qualimap)
    alignments = channel.empty()
    if ( params.samplesheet ) {
        alignments = params.samplesheet.map { s ->
            checkSampleFields(s.sample, s.library_id, null, s.platform)
            if ( params.level == 'library' && s.library_id == null ) {
                stageError "Merging to library level needs a library_id for every row of the samplesheet (missing for sample '${s.sample}')"
            }
            record(id: s.sample, meta: record(library: s.library_id, pl: s.platform) as Record, alignment: s.alignment, index: s.index, single_end: s.single_end)
        }
    } else {
        alignments = params.alignments.map { a -> record(id: a.id, meta: a.meta, alignment: a.alignment, index: a.index, single_end: a.single_end) }
    }
    alignments = alignments.map { aln ->
        checkReferenceForInput(aln.alignment, params.fasta != null, false)
        aln
    }
    reference = REFERENCE_VALUE(params.fasta, params.fai, (params.align_qc && params.riker) || params.cram_format)

    // Group on the requested level (dropping flowcell, lane, read group, platform unit and input type),
    // then branch to enable merge skipping (singletons).
    grouped = alignments
        .map { aln ->
            // library is dropped (null) when merging libraries to sample level
            def group_meta = record(
                id        : aln.id,
                library   : params.level == 'sample' ? null : aln.meta.library,
                pl        : aln.meta.pl,
                single_end: aln.single_end
            )
            tuple(group_meta, aln)
        }
        .groupBy()
        .map { group_meta, alns ->
            // groupBy order reflects non-deterministic arrival timing.
            // sort by filename so SAMTOOLS_MERGE always stages in the same subdirectories.
            // (samtools merge breaks position ties using input file order)
            tuple(group_meta, alns.toSorted { a, b -> a.alignment.name <=> b.alignment.name })
        }
    to_merge = grouped.filter { _group_meta, alns -> alns.size() > 1 }
    skipped  = grouped
        .filter { _group_meta, alns -> alns.size() == 1 }
        .map { group_meta, alns -> record(id: group_meta.id, meta: record(library: group_meta.library, pl: group_meta.pl), alignment: alns[0].alignment, index: alns[0].index, single_end: group_meta.single_end) }

    // Merge alignments
    merged = SAMTOOLS_MERGE(
        to_merge
            .combine(reference)
            .map { group_meta, alns, ref ->
                record(
                    id                 : group_meta.id,
                    meta               : record(library: group_meta.library, pl: group_meta.pl),
                    input_files        : alns.collect { aln -> aln.alignment }.toList(),
                    index_files        : alns.collect { aln -> aln.index }.toList(),
                    // The reference is needed to read CRAM input and to write CRAM output
                    fasta              : ref.fasta,
                    fai                : ref.fai,
                    gzi                : null,
                    index_format       : params.cram_format ? 'crai' : 'csi',
                    samtools_merge_args: null,
                    output_prefix      : params.level == 'sample'
                        ? "${group_meta.id}_${group_meta.pl}"
                        : "${group_meta.id}_${group_meta.library}_${group_meta.pl}"
                )
            }
    )

    // Merged alignments with their indexes, for alignment QC and publishing.
    // The merged alignment gets its single_end back from its group, which holds alignments of one layout
    groups = grouped.map { group_meta, _alns -> record(id: group_meta.id, meta: record(library: group_meta.library, pl: group_meta.pl), single_end: group_meta.single_end) }
    merged_alignments = attachSingleEnd(merged, groups)
        .map { j -> record(id: j.out.id, meta: j.out.meta, alignment: j.out.cram ?: j.out.bam, index: j.out.index, single_end: j.single_end) }

    // MERGE:ALIGNMENT_QC — only for alignments that were actually merged; a skipped singleton is
    // byte-identical to the pre-merge alignment already QC'd upstream
    qc_flagstat      = channel.empty()
    qc_riker         = channel.empty()
    qc_qualimap      = channel.empty()
    qc_multiqc_files = channel.empty()
    if ( params.align_qc ) {
        // The reference has its fai index when this stage needed it. Pass it on, so that it is not created twice
        qc_fai = params.fai
        if ( params.riker || params.cram_format ) {
            qc_fai = reference.map { ref -> ref.fai } as Value<Path>
        }
        alignment_qc = ALIGNMENT_QC(
            record(
                alignments: merged_alignments,
                level     : params.level,
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
    alignments    = merged_alignments.mix(skipped) // full set (merged + passthrough), for downstream processing
    merged        = merged_alignments              // merged only, for publishing
    flagstat      = qc_flagstat
    riker         = qc_riker
    qualimap      = qc_qualimap
    multiqc_files = qc_multiqc_files

}

output {
    alignments   : Channel<Record> { path 'alignments' }
    merged       : Channel<Record> { path 'merged' }
    flagstat     : Channel<Record> { path 'flagstat' }
    riker        : Channel<Record> { path 'riker' }
    qualimap     : Channel<Record> { path 'qualimap' }
    multiqc_files: Channel<Path> { path 'multiqc_files' }
}
