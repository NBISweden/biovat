include { SAMTOOLS_FLAGSTAT } from '../../../modules/nf-core/samtools/flagstat/main'
include { RIKER_MULTI       } from '../../../modules/nf-core/riker/multi/main'
include { QUALIMAP_BAMQC    } from '../../../modules/nf-core/qualimap/bamqc/main'

workflow BAM_QC {

    take:
    aligned_reads         // channel: aligned reads to perform QC on
    aligned_reads_index   // channel: index of aligned reads
    reference             // channel: reference fasta read in from --reference
    reference_fai         // channel: reference fasta fai index created by REFERENCE_UTILS
    enable_bamqc_riker    // boolean: Whether to run RIKER for BAM QC
    enable_bamqc_qualimap // boolean: Whether to run QUALIMAP for BAM QC

    main:
    def ch_reads_and_index   = aligned_reads.join(aligned_reads_index)
    def ch_reference_and_fai = reference.join(reference_fai)

    // SAMTOOLS_FLAGSTAT
    SAMTOOLS_FLAGSTAT(ch_reads_and_index)

    // RIKER
    riker_outputs = channel.empty()
    if ( enable_bamqc_riker ) {
        def ch_riker_input = ch_reads_and_index // TODO: Potentially support optional inputs, except RNA-seq specific.
            .map { meta, bam, index ->
                [
                    meta, bam, index,
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
        riker_outputs = RIKER_MULTI.out.alignment_metrics.mix(
            RIKER_MULTI.out.base_dist,
            RIKER_MULTI.out.error_indel,
            RIKER_MULTI.out.error_mismatch,
            RIKER_MULTI.out.error_overlap,
            RIKER_MULTI.out.gcbias_detail,
            RIKER_MULTI.out.gcbias_summary,
            RIKER_MULTI.out.hybcap_metrics,
            RIKER_MULTI.out.hybcap_per_base,
            RIKER_MULTI.out.hybcap_per_target,
            RIKER_MULTI.out.isize_histogram,
            RIKER_MULTI.out.isize_metrics,
            RIKER_MULTI.out.mean_qual,
            RIKER_MULTI.out.pdf,
            RIKER_MULTI.out.qual_dist,
            RIKER_MULTI.out.rna_biotype,
            RIKER_MULTI.out.rna_insert_size_histogram,
            RIKER_MULTI.out.rna_insert_size,
            RIKER_MULTI.out.rna_metrics,
            RIKER_MULTI.out.wgs_coverage,
            RIKER_MULTI.out.wgs_metrics
        )
    }

    // QUALIMAP
    qualimap_outputs = channel.empty()
    if ( enable_bamqc_qualimap ) {
        QUALIMAP_BAMQC(
            aligned_reads,
            []         //  TODO: Potentially support optional input (gff file)
        )
        qualimap_outputs = QUALIMAP_BAMQC.out.results
    }

    emit:
    flagstat_outputs = SAMTOOLS_FLAGSTAT.out.flagstat
    riker_outputs    = riker_outputs
    qualimap_outputs = qualimap_outputs

}
