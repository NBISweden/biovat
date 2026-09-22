include { BCFTOOLS_STATS } from '../../../modules/nf-core/bcftools/stats/main'

workflow VARIANT_QC {

    take:
    ch_variant_calls_and_index
    ch_reference_and_optional_fai

    main:
    // BCFTOOLS_STATS
    BCFTOOLS_STATS(ch_variant_calls_and_index, 
        [], // regions
        [], // targets
        [], // samples
        [], // exons
        ch_reference_and_optional_fai)

    emit:
    bcftools_stats_outputs = BCFTOOLS_STATS.out.stats

}
