include { SAMTOOLS_FLAGSTAT } from '../../../modules/nf-core/samtools/flagstat/main'
include { RIKER_MULTI       } from '../../../modules/nf-core/riker/multi/main'
include { QUALIMAP_BAMQC    } from '../../../modules/nf-core/qualimap/bamqc/main'
//include { RUSTQC } from '../../../modules/nf-core/rustqc/main'

workflow BAM_QC {

    take:
    aligned_reads         // channel: aligned reads to perform QC on
    aligned_reads_index   // channel: index of aligned reads
    reference             // channel: reference fasta read in from --reference
    reference_fai         // channel: reference fasta fai index created by REFERENCE_UTILS
    enable_bamqc_riker    // boolean: Whether to run RIKER for BAM QC
    enable_bamqc_rustqc   // boolean: Whether to run RUSTQC for BAM QC
    enable_bamqc_qualimap // boolean: Whether to run QUALIMAP for BAM QC

    main:
    def ch_reads_and_index   = aligned_reads.join(aligned_reads_index)
    def ch_reference_and_fai = reference.join(reference_fai)

    // SAMTOOLS_FLAGSTAT
    SAMTOOLS_FLAGSTAT(ch_reads_and_index)

    // RIKER
    riker_outputs          = channel.empty()
    if ( enable_bamqc_riker ) {
        def ch_riker_input = ch_reads_and_index
            .map { meta, bam, index ->
                [
                    meta,
                    bam,
                    index,
                    // TODO: Add support for optional inputs to RIKER
                    [], // path: error_vcf
                    [], // path: error_vcf_idx
                    [], // path: error_intervals
                    [], // path: gcbias_exclude_intervals
                    [], // path: hybcap_baits
                    [], // path: hybcap_targets
                    [], // path: rna_gene_model
                    [], // path: rna_ribosomal_intervals
                    []  // path: wgs_intervals
                ]
            }
        RIKER_MULTI(
            ch_riker_input,
            ch_reference_and_fai
        )
        //riker_outputs = RIKER_MULTI.out
    }




    // RUSTQC(aligned_reads)
    // QUALIMAP_BAMQC(aligned_reads)

    emit:
    flagstat = SAMTOOLS_FLAGSTAT.out.flagstat

}
