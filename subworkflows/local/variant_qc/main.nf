include { BCFTOOLS_STATS                    } from '../../../modules/nf-core/bcftools/stats/main'
include { VCFTOOLS as VCFTOOLS_SUMMARY      } from '../../../modules/nf-core/vcftools/main'
include { VCFTOOLS as VCFTOOLS_TSTV_COUNT   } from '../../../modules/nf-core/vcftools/main'
include { VCFTOOLS as VCFTOOLS_TSTV_QUAL    } from '../../../modules/nf-core/vcftools/main'
include { VCFTOOLS as VCFTOOLS_RELATEDNESS2 } from '../../../modules/nf-core/vcftools/main'

workflow VARIANT_QC {

    take:
    ch_variant_calls_and_tbi
    ch_reference_and_fai

    main:
    // BCFTOOLS_STATS
    // Remove fai for BCFTOOLS_STATS module
    ch_reference = ch_reference_and_fai
        .map { meta, fasta, fai -> [ meta, fasta ] }
    BCFTOOLS_STATS(ch_variant_calls_and_tbi,
        [[:],[]], // regions
        [[:],[]], // targets
        [[:],[]], // samples
        [[:],[]], // exons
        ch_reference)

    // VCFTOOLS:
    // Remove tbi for VCFTOOLS module
    ch_variant_calls = ch_variant_calls_and_tbi
            .map { meta, vcf, tbi -> [ meta, vcf ] }
    VCFTOOLS_TSTV_COUNT(ch_variant_calls,
        [], // regions
        [])
    VCFTOOLS_TSTV_QUAL(ch_variant_calls,
        [],
        [])
    VCFTOOLS_SUMMARY(ch_variant_calls,
        [],
        [])
    VCFTOOLS_RELATEDNESS2(ch_variant_calls,
        [],
        [])

    emit:
    bcftools_stats_output          = BCFTOOLS_STATS.out.stats
    vcftools_tstv_counts_output    = VCFTOOLS_TSTV_COUNT.out.tstv_count
    vcftools_tstv_qual_output      = VCFTOOLS_TSTV_QUAL.out.tstv_qual
    vcftools_filter_summary_output = VCFTOOLS_SUMMARY.out.filter_summary
    vcftools_relatedness2_output   = VCFTOOLS_RELATEDNESS2.out.relatedness2

}
