include { SAMTOOLS_MERGE } from '../../../modules/nf-core/samtools/merge/main'
include { ALIGNMENT_QC   } from '../alignment_qc/main'

workflow MERGE_LIBRARIES {

    take:
    ch_library_alignments_indexed  // channel: aligned reads and index files
    ch_reference_and_fai           // channel: reference fasta and fai index
    enable
    ch_multiqc_files

    main:
    // Aligments: group on sample, branch to enable merge skipping (singleton libraries)
    ch_sample_groups = ch_library_alignments_indexed
        .map { meta, alignment, index ->
            def sample_meta = [
                id: meta.id,
                pl: meta.pl
            ]
            return [ sample_meta, alignment, index ]
        }
        .groupTuple()
        .branch { meta, alignments, indexes ->
            skip_merge: alignments.size() == 1
                return [ meta, alignments[0], indexes[0] ]
            run_merge : alignments.size() > 1
        }

    // Reference: shape the input channel based on alignment format
    ch_samtools_reference = enable.cram_format
        ? ch_reference_and_fai.map { meta, fasta, fai -> [ meta, fasta, fai, [] ] }
        : [ [], [], [], [] ] // else BAM

    // Merge alignments
    SAMTOOLS_MERGE(
        ch_sample_groups.run_merge,
        ch_samtools_reference
    )

    // Join merged alignments with their indexes, then re-mix with singletons
    ch_sample_alignments_indexed = SAMTOOLS_MERGE.out.cram
        .mix(SAMTOOLS_MERGE.out.bam)
        .join(SAMTOOLS_MERGE.out.index)
        .mix(ch_sample_groups.skip_merge)

    // MERGE_LIBRARIES:ALIGNMENT_QC
    outputs_sample_flagstat = channel.empty()
    outputs_sample_riker    = channel.empty()
    outputs_sample_qualimap = channel.empty()
    if ( enable.align_qc ) {
        ALIGNMENT_QC(
            ch_sample_alignments_indexed,
            ch_reference_and_fai,
            enable
        )
        ch_multiqc_files = ch_multiqc_files
            .mix(
                ALIGNMENT_QC.out.flagstat_outputs.map{ _meta, file -> file },
                ALIGNMENT_QC.out.riker_outputs.map{ _meta, file -> file },
                ALIGNMENT_QC.out.qualimap_outputs.map{ _meta, file -> file }
            )
        outputs_sample_flagstat = ALIGNMENT_QC.out.flagstat_outputs
        outputs_sample_riker    = ALIGNMENT_QC.out.riker_outputs
        outputs_sample_qualimap = ALIGNMENT_QC.out.qualimap_outputs
    }

    emit:
    ch_sample_alignments_indexed
    ch_multiqc_files
    outputs_sample_flagstat
    outputs_sample_riker
    outputs_sample_qualimap

}
