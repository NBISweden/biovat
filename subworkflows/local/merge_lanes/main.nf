include { SAMTOOLS_MERGE } from '../../../modules/nf-core/samtools/merge/main'
include { ALIGNMENT_QC   } from '../alignment_qc/main'

workflow MERGE_LANES {

    take:
    ch_lane_alignments_indexed    // channel: aligned reads and index files, one entry per lane/flowcell
    ch_reference_and_optional_fai // channel: reference fasta and (optional) fai index
    enable
    ch_multiqc_files

    main:
    // Alignments: group on sample + library, branch to enable merge skipping (singleton lanes)
    ch_alignments = ch_lane_alignments_indexed
        .map { meta, alignment, index ->
            def library_meta = [
                id: meta.id,
                library: meta.library,
                pl: meta.pl
            ]
            return [ library_meta, alignment, index ]
        }
        .groupTuple()
        .branch { meta, alignments, indexes ->
            skip_merge: alignments.size() == 1
                return [ meta, alignments[0], indexes[0] ]
            for_merge : alignments.size() > 1
        }

    // Reference: shape the input channel based on alignment format
    ch_reference_for_merge = enable.cram_format
        ? ch_reference_and_optional_fai.map { meta, fasta, fai -> [ meta, fasta, fai, [] ] }
        : [ [], [], [], [] ] // else BAM

    // Merge alignments
    SAMTOOLS_MERGE(
        ch_alignments.for_merge,
        ch_reference_for_merge,
        enable.cram_format ? 'crai' : 'csi'
    )

    // Join merged alignments with their indexes, then re-mix with singletons
    ch_library_alignments_indexed = SAMTOOLS_MERGE.out.cram
        .mix(SAMTOOLS_MERGE.out.bam)
        .join(SAMTOOLS_MERGE.out.index)
        .mix(ch_alignments.skip_merge)

    // MERGE_LANES:ALIGNMENT_QC
    outputs_library_flagstat = channel.empty()
    outputs_library_riker    = channel.empty()
    outputs_library_qualimap = channel.empty()
    if ( enable.align_qc ) {
        ALIGNMENT_QC(
            ch_library_alignments_indexed,
            ch_reference_and_optional_fai,
            enable,
            'library'
        )
        ch_multiqc_files = ch_multiqc_files
            .mix(
                ALIGNMENT_QC.out.flagstat_outputs.map{ _meta, file -> file },
                ALIGNMENT_QC.out.riker_outputs.map{ _meta, file -> file },
                ALIGNMENT_QC.out.qualimap_outputs.map{ _meta, file -> file }
            )
        outputs_library_flagstat = ALIGNMENT_QC.out.flagstat_outputs
        outputs_library_riker    = ALIGNMENT_QC.out.riker_outputs
        outputs_library_qualimap = ALIGNMENT_QC.out.qualimap_outputs
    }

    emit:
    ch_library_alignments_indexed
    ch_multiqc_files
    outputs_library_flagstat
    outputs_library_riker
    outputs_library_qualimap

}
