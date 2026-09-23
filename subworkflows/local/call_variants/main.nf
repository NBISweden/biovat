//
// Variant calling subworkflow
//

include { BCFTOOLS_MPILEUP_MULTISAMPLE } from '../../../modules/local/bcftools/mpileup_multisample/main'
include { VARIANT_QC                   } from '../variant_qc/main'

workflow CALL_VARIANTS {

    take:
    variant_caller
    ch_alignment_and_index
    ch_samplesheet
    ch_reference_and_fai
    dataset_name
    enable
    ch_multiqc_files

    main:
    // TODO: add option to split genome into chromosomes or chunks for parallelization

    // Group all samples into a single joint call
    ch_joint_alignments = ch_alignment_and_index
        .map { meta, alignment, index -> [ dataset_name, meta.id, alignment, index ] }
        .groupTuple()
        .map { group, samples, alignments, indexes ->
            [ [ id: group, samples: samples ], alignments, indexes ]
        }

    // Call variants with four alternative variant callers
    ch_variant_calls_indexed = channel.empty()
    ch_mpileup               = channel.empty()

    if ( variant_caller == 'bcftools' ) {
        ch_population_file   = channel.value([])
        if ( enable.group_samples ) {
            ch_population_file = ch_samplesheet
                .map { meta, _reads -> "${meta.id}\t${meta.population}" }
                .unique()
                .collectFile(
                    name:    'sample_population.tsv',
                    newLine: true,
                    sort:    true,
                    cache:   true
                )
            }

        BCFTOOLS_MPILEUP_MULTISAMPLE(
            ch_joint_alignments,
            ch_reference_and_fai,
            [], // intervals
            enable.save_mpileup,
            enable.group_samples,
            ch_population_file
        )
        ch_variant_calls_indexed = BCFTOOLS_MPILEUP_MULTISAMPLE.out.vcf
            .join(BCFTOOLS_MPILEUP_MULTISAMPLE.out.index)
        ch_mpileup               = BCFTOOLS_MPILEUP_MULTISAMPLE.out.mpileup
    }

    // TODO: add bcftools mpileup/call per sample calling and merging/joint genotyping

    // TODO: add GATK4 haplotype caller and genotype gvcfs

    // TODO: add parabricks haplotype caller and genotype gvcfs

    // TODO: convert *.vcf from parabricks to *vcf.gz and index

    // CALL_VARIANTS:VARIANT_QC
    outputs_bcftools_stats          = channel.empty()
    outputs_vcftools_tstv_counts    = channel.empty()
    outputs_vcftools_tstv_qual      = channel.empty()
    outputs_vcftools_filter_summary = channel.empty()
    outputs_vcftools_relatedness2   = channel.empty()
    if ( enable.variant_qc ) {
        VARIANT_QC(
            ch_variant_calls_indexed,
            ch_reference_and_fai
        )
        ch_multiqc_files = ch_multiqc_files
            .mix(VARIANT_QC.out.bcftools_stats_output.map { _meta, file -> [file] },
                VARIANT_QC.out.vcftools_tstv_counts_output.map { _meta, file -> [file] },
                VARIANT_QC.out.vcftools_tstv_qual_output.map { _meta, file -> [file] },
                VARIANT_QC.out.vcftools_filter_summary_output.map { _meta, file -> [file] },
                VARIANT_QC.out.vcftools_relatedness2_output.map { _meta, file -> [file] }
            )
        outputs_bcftools_stats          = VARIANT_QC.out.bcftools_stats_output
        outputs_vcftools_tstv_counts    = VARIANT_QC.out.vcftools_tstv_counts_output
        outputs_vcftools_tstv_qual      = VARIANT_QC.out.vcftools_tstv_qual_output
        outputs_vcftools_filter_summary = VARIANT_QC.out.vcftools_filter_summary_output
        outputs_vcftools_relatedness2   = VARIANT_QC.out.vcftools_relatedness2_output
    }


    // TODO: add option to convert `*.vcf.gz` to `*.bcf`

    emit:
    ch_variant_calls_indexed // channel: [ meta, *.vcf.gz ] and [ meta, *.tbi/csi ]
    ch_mpileup               // channel: [ meta, *.mpileup.gz ], empty unless enable_save_mpileup
    ch_multiqc_files
    outputs_bcftools_stats
    outputs_vcftools_tstv_counts
    outputs_vcftools_tstv_qual
    outputs_vcftools_filter_summary
    outputs_vcftools_relatedness2

}
