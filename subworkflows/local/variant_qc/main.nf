include { BCFTOOLS_STATS } from '../../../modules/nf-core/bcftools/stats/main'

workflow VARIANT_QC {

    take:
    ch_variant_calls_and_tbi
    ch_reference

    main:
    // BCFTOOLS_STATS
    BCFTOOLS_STATS(ch_variant_calls_and_tbi, 
        [[], []], // regions
        [[], []], // targets
        [[], []], // samples
        [[], []], // exons
        ch_reference)

    emit:
    bcftools_stats_outputs = BCFTOOLS_STATS.out.stats

}
