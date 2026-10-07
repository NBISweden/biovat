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
    ch_reference = ch_reference_and_fai.map { meta, fasta, _fai -> [meta, fasta] }
    bcftools_stats_out = BCFTOOLS_STATS(
        ch_variant_calls_and_tbi,
        [[:], []],
        [[:], []],
        [[:], []],
        [[:], []],
        ch_reference,
    )

    // VCFTOOLS:
    // Remove tbi for VCFTOOLS module
    ch_variant_calls = ch_variant_calls_and_tbi.map { meta, vcf, _tbi -> [meta, vcf] }
    vcftools_tstv_count_out = VCFTOOLS_TSTV_COUNT(
        ch_variant_calls,
        [],
        [],
    )
    vcftools_tstv_qual_out = VCFTOOLS_TSTV_QUAL(
        ch_variant_calls,
        [],
        [],
    )
    vcftools_summary_out = VCFTOOLS_SUMMARY(
        ch_variant_calls,
        [],
        [],
    )
    vcftools_relatedness2_out = VCFTOOLS_RELATEDNESS2(
        ch_variant_calls,
        [],
        [],
    )

    emit:
    outputs_bcftools_stats          = bcftools_stats_out.stats
    outputs_vcftools_tstv_counts    = vcftools_tstv_count_out.tstv_count
    outputs_vcftools_tstv_qual      = vcftools_tstv_qual_out.tstv_qual
    outputs_vcftools_filter_summary = vcftools_summary_out.filter_summary
    outputs_vcftools_relatedness2   = vcftools_relatedness2_out.relatedness2
    multiqc_files                   = bcftools_stats_out.stats
        .mix(
            vcftools_tstv_count_out.tstv_count,
            vcftools_tstv_qual_out.tstv_qual,
            vcftools_summary_out.filter_summary,
            vcftools_relatedness2_out.relatedness2,
        )
        .map { _meta, file -> [file] }
}
