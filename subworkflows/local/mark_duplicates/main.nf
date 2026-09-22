include { PICARD_MARKDUPLICATES } from '../../../modules/nf-core/picard/markduplicates/main'
include { SAMTOOLS_SORMADUP     } from '../../../modules/nf-core/samtools/sormadup/main'
include { SAMTOOLS_INDEX        } from '../../../modules/nf-core/samtools/index/main'
include { ALIGNMENT_QC          } from '../alignment_qc/main'

workflow MARK_DUPLICATES {
    take:
    duplicate_marker
    ch_library_alignments_indexed
    ch_reference_and_optional_fai
    ch_multiqc_files
    enable

    main:
    if (duplicate_marker == 'picard') {
        picard_markduplicates_out = PICARD_MARKDUPLICATES(
            ch_library_alignments_indexed.map { meta, alignment, _index -> [meta, alignment] },
            ch_reference_and_optional_fai,
        )
        ch_from_markdups_alignments = picard_markduplicates_out.bam.mix(picard_markduplicates_out.cram)
        samtools_index_out = SAMTOOLS_INDEX(
            ch_from_markdups_alignments
        )
        ch_from_markdups_alignments_indexed = ch_from_markdups_alignments.join(samtools_index_out.index)
        ch_from_markdups_metrics = picard_markduplicates_out.metrics
        ch_multiqc_files = ch_multiqc_files.mix(picard_markduplicates_out.metrics.map { _meta, file -> file })
    }
    else if (duplicate_marker == 'samtools') {
        samtools_sormadup_out = SAMTOOLS_SORMADUP(
            ch_library_alignments_indexed.map { meta, alignment, _index -> [meta, alignment] },
            ch_reference_and_optional_fai,
        )
        ch_from_markdups_bam_indexed = samtools_sormadup_out.bam.join(samtools_sormadup_out.csi)
        ch_from_markdups_cram_indexed = samtools_sormadup_out.cram.join(samtools_sormadup_out.crai)
        ch_from_markdups_alignments_indexed = ch_from_markdups_bam_indexed.mix(ch_from_markdups_cram_indexed)
        ch_from_markdups_metrics = samtools_sormadup_out.metrics
        ch_multiqc_files = ch_multiqc_files.mix(samtools_sormadup_out.metrics.map { _meta, file -> file })
    }

    // MARK_DUPLICATES:ALIGNMENT_QC
    outputs_mark_duplicates_flagstat = channel.empty()
    outputs_mark_duplicates_riker = channel.empty()
    outputs_mark_duplicates_qualimap = channel.empty()
    if (enable.align_qc) {
        alignment_qc_out = ALIGNMENT_QC(
            ch_from_markdups_alignments_indexed,
            ch_reference_and_optional_fai,
            enable,
            'markdup',
        )
        ch_multiqc_files = ch_multiqc_files.mix(
            alignment_qc_out.flagstat_outputs.map { _meta, file -> file },
            alignment_qc_out.riker_outputs.map { _meta, file -> file },
            alignment_qc_out.qualimap_outputs.map { _meta, file -> file },
        )
        outputs_mark_duplicates_flagstat = alignment_qc_out.flagstat_outputs
        outputs_mark_duplicates_riker = alignment_qc_out.riker_outputs
        outputs_mark_duplicates_qualimap = alignment_qc_out.qualimap_outputs
    }

    emit:
    ch_from_markdups_alignments_indexed
    ch_from_markdups_metrics
    ch_multiqc_files
    outputs_mark_duplicates_flagstat
    outputs_mark_duplicates_riker
    outputs_mark_duplicates_qualimap
}
