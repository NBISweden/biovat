include { PICARD_MARKDUPLICATES } from '../../../modules/nf-core/picard/markduplicates/main'
include { SAMTOOLS_SORMADUP     } from '../../../modules/nf-core/samtools/sormadup/main'
include { SAMTOOLS_INDEX        } from '../../../modules/nf-core/samtools/index/main'
include { ALIGNMENT_QC          } from '../alignment_qc/main'

workflow MARK_DUPLICATES {

    take:
    duplicate_marker
    ch_sample_alignments_indexed
    ch_reference_and_fai
    ch_multiqc_files
    enable

    main:
    if ( duplicate_marker == 'picard' ) {
        PICARD_MARKDUPLICATES(
            ch_sample_alignments_indexed.map { meta, alignment, _index -> [ meta, alignment ] },
            ch_reference_and_fai
        )
        ch_from_markdups_alignments = PICARD_MARKDUPLICATES.out.bam.mix(PICARD_MARKDUPLICATES.out.cram)
        SAMTOOLS_INDEX(
            ch_from_markdups_alignments
        )
        ch_from_markdups_alignments_indexed = ch_from_markdups_alignments
            .join(SAMTOOLS_INDEX.out.index)
        ch_from_markdups_metrics            = PICARD_MARKDUPLICATES.out.metrics
        ch_multiqc_files = ch_multiqc_files
            .mix(PICARD_MARKDUPLICATES.out.metrics.map { _meta, file -> file })
    } else if ( duplicate_marker == 'samtools' ) {
        SAMTOOLS_SORMADUP(
            ch_sample_alignments_indexed.map { meta, alignment, _index -> [ meta, alignment ] },
            ch_reference_and_fai
        )
        ch_from_markdups_bam_indexed  = SAMTOOLS_SORMADUP.out.bam.join(SAMTOOLS_SORMADUP.out.csi)
        ch_from_markdups_cram_indexed = SAMTOOLS_SORMADUP.out.cram.join(SAMTOOLS_SORMADUP.out.crai)
        ch_from_markdups_alignments_indexed = ch_from_markdups_bam_indexed.mix(ch_from_markdups_cram_indexed)
        ch_from_markdups_metrics            = SAMTOOLS_SORMADUP.out.metrics
        ch_multiqc_files = ch_multiqc_files
            .mix(SAMTOOLS_SORMADUP.out.metrics.map { _meta, file -> file })
    }

    // MARK_DUPLICATES:ALIGNMENT_QC
    outputs_mark_duplicates_flagstat = channel.empty()
    outputs_mark_duplicates_riker    = channel.empty()
    outputs_mark_duplicates_qualimap = channel.empty()
    if ( enable.align_qc ) {
        ALIGNMENT_QC(
            ch_from_markdups_alignments_indexed,
            ch_reference_and_fai,
            enable,
            'markdup'
        )
        ch_multiqc_files = ch_multiqc_files
            .mix(
                ALIGNMENT_QC.out.flagstat_outputs.map{ _meta, file -> file },
                ALIGNMENT_QC.out.riker_outputs.map{ _meta, file -> file },
                ALIGNMENT_QC.out.qualimap_outputs.map{ _meta, file -> file }
            )
        outputs_mark_duplicates_flagstat = ALIGNMENT_QC.out.flagstat_outputs
        outputs_mark_duplicates_riker    = ALIGNMENT_QC.out.riker_outputs
        outputs_mark_duplicates_qualimap = ALIGNMENT_QC.out.qualimap_outputs
    }

    emit:
    ch_from_markdups_alignments_indexed
    ch_from_markdups_metrics
    ch_multiqc_files
    outputs_mark_duplicates_flagstat
    outputs_mark_duplicates_riker
    outputs_mark_duplicates_qualimap

}
