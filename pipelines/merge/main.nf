nextflow.enable.types = true

//
// Merge pipeline: merges alignments to library level or to sample level
//

include { SAMTOOLS_MERGE } from '../../modules/nf-core/samtools/merge/main'
include { ALIGNMENT_QC   } from '../../subworkflows/local/alignment_qc/main'
include { REFERENCE_VALUE } from '../../subworkflows/local/utils_reference/main'
include { STAGE_HELP     } from '../../subworkflows/local/utils_stage_help/main'

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
    meta     : Record // sample information, requires id, pl and single_end (and library to merge at library level)
    alignment: Path   // BAM or CRAM file
    index    : Path   // index of the BAM or CRAM file
}

params {
    samplesheet: Channel<AlignmentSample>? // alignments samplesheet (CSV with the columns sample, library_id, platform, single_end, alignment, index)
    alignments: Channel<Alignment>? // alternative to the samplesheet: alignments with their meta record, from a YAML or JSON file or a calling pipeline
    level     : String = 'library'  // merge level, controls grouping and QC prefix ('library'/'sample')
    fasta     : Value<Path>?        // reference fasta, needed for CRAM output
    fai       : Value<Path>?        // fai index of the reference fasta, needed for CRAM output and Riker
    cram_format: Boolean = false    // write CRAM instead of BAM
    align_qc  : Boolean = true      // run alignment QC on the merged alignments
    riker     : Boolean = true      // run Riker in the alignment QC
    qualimap  : Boolean = false     // run Qualimap in the alignment QC
    help      : Boolean = false
    help_full : Boolean = false
}

workflow {

    main:
    STAGE_HELP(params.help, params.help_full, "${moduleDir}/nextflow_schema.json", 'nextflow run pipelines/merge --samplesheet alignments.csv --level library --fasta reference.fasta')
    if ( !(params.level in [ 'library', 'sample' ]) ) {
        error "Unknown merge level '${params.level}', expected library or sample"
    }
    if ( params.samplesheet && params.alignments ) {
        error "Provide either --samplesheet or --alignments, not both"
    }
    if ( !params.samplesheet && !params.alignments ) {
        error "Missing required parameter --samplesheet"
    }
    alignments = channel.empty()
    if ( params.samplesheet ) {
        alignments = params.samplesheet.map { s ->
            if ( params.level == 'library' && s.library_id == null ) {
                error "Merging to library level needs a library_id for every row of the samplesheet (missing for sample '${s.sample}')"
            }
            def meta = [ id: s.sample, library: s.library_id, pl: s.platform, single_end: s.single_end ]
            record(meta: record(meta), alignment: s.alignment, index: s.index)
        }
    } else {
        alignments = params.alignments.map { a -> record(meta: a.meta, alignment: a.alignment, index: a.index) }
    }
    reference = REFERENCE_VALUE(params.fasta, params.fai, (params.align_qc && params.riker) || params.cram_format)

    // Group on the requested level (dropping flowcell, lane, read group, platform unit and input type),
    // then branch to enable merge skipping (singletons).
    grouped = alignments
        .map { aln ->
            // library is dropped (null) when merging libraries to sample level
            def group_meta = record(
                id        : aln.meta.id,
                library   : params.level == 'sample' ? null : aln.meta.library,
                pl        : aln.meta.pl,
                single_end: aln.meta.single_end
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
        .map { group_meta, alns -> record(meta: group_meta, alignment: alns[0].alignment, index: alns[0].index) }

    // Merge alignments
    merged = SAMTOOLS_MERGE(
        to_merge
            .combine(reference)
            .map { group_meta, alns, ref ->
                record(
                    id                 : group_meta.id,
                    meta               : group_meta,
                    input_files        : alns.collect { aln -> aln.alignment }.toList(),
                    index_files        : alns.collect { aln -> aln.index }.toList(),
                    // The reference is only needed for CRAM output
                    fasta              : params.cram_format ? ref.fasta : null,
                    fai                : params.cram_format ? ref.fai : null,
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
    merged_alignments = merged.map { out -> record(meta: out.meta, alignment: out.cram ?: out.bam, index: out.index) }

    // MERGE:ALIGNMENT_QC — only for alignments that were actually merged; a skipped singleton is
    // byte-identical to the pre-merge alignment already QC'd upstream
    qc_flagstat      = channel.empty()
    qc_riker         = channel.empty()
    qc_qualimap      = channel.empty()
    qc_multiqc_files = channel.empty()
    if ( params.align_qc ) {
        alignment_qc = ALIGNMENT_QC(merged_alignments, reference, params.riker, params.qualimap, params.level)
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
