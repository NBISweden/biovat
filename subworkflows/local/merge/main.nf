include { SAMTOOLS_MERGE } from '../../../modules/nf-core/samtools/merge/main'
include { ALIGNMENT_QC   } from '../alignment_qc/main'

workflow MERGE {
    take:
    ch_alignments_indexed         // channel: aligned reads and index files to merge
    ch_reference_and_optional_fai // channel: reference fasta and (optional) fai index
    enable                        // map: stage/tool gating flags
    ch_multiqc_files              // channel: MultiQC files
    level                         // string: merge level, controls grouping and QC prefix ('library'/'sample')

    main:
    // Group on the requested level, branch to enable merge skipping (singletons).
    def keys_to_drop = level == 'library'
        ? ['flowcell', 'lane', 'read_group']
        : ['flowcell', 'lane', 'read_group', 'library'] // else 'sample'
    ch_alignments = ch_alignments_indexed
        .map { meta, alignment, index ->
            def group_meta = meta.subMap(meta.keySet() - keys_to_drop)
            return [group_meta, alignment, index]
        }
        .groupTuple()
        .branch { meta, alignments, indexes ->
            skip_merge: alignments.size() == 1
            return [meta, alignments[0], indexes[0]]
            for_merge: alignments.size() > 1
        }

    // Reference: shape the input channel based on alignment format
    ch_reference_for_merge = enable.cram_format
        ? ch_reference_and_optional_fai.map { meta, fasta, fai -> [meta, fasta, fai, []] }
        : [[], [], [], []] // else BAM

    // Merge alignments
    samtools_merge_out = SAMTOOLS_MERGE(
        ch_alignments.for_merge,
        ch_reference_for_merge,
        enable.cram_format ? 'crai' : 'csi',
    )

    // Join merged alignments with their indexes, for alignment QC and publishing.
    ch_merged_output_for_alignment_qc = samtools_merge_out.cram
        .mix(samtools_merge_out.bam)
        .join(samtools_merge_out.index)

    // MERGE:ALIGNMENT_QC — only for alignments that were actually merged; a skipped singleton is
    // byte-identical to the pre-merge alignment already QC'd upstream
    outputs_flagstat = channel.empty()
    outputs_riker = channel.empty()
    outputs_qualimap = channel.empty()
    if (enable.align_qc) {
        alignment_qc_out = ALIGNMENT_QC(
            ch_merged_output_for_alignment_qc,
            ch_reference_and_optional_fai,
            enable,
            level,
        )
        ch_multiqc_files = ch_multiqc_files.mix(
            alignment_qc_out.flagstat_outputs.map { _meta, file -> file },
            alignment_qc_out.riker_outputs.map { _meta, file -> file },
            alignment_qc_out.qualimap_outputs.map { _meta, file -> file },
        )
        outputs_flagstat = alignment_qc_out.flagstat_outputs
        outputs_riker = alignment_qc_out.riker_outputs
        outputs_qualimap = alignment_qc_out.qualimap_outputs
    }

    emit:
    // Re-mix merged output with singletons: full set (merged + passthrough), for downstream processing
    ch_merged_alignments_indexed = ch_merged_output_for_alignment_qc.mix(ch_alignments.skip_merge)
    outputs_alignments           = ch_merged_output_for_alignment_qc // merged only, singletons excluded, for publishing
    ch_multiqc_files
    outputs_flagstat
    outputs_riker
    outputs_qualimap
}
