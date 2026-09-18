//
// Variant calling subworkflow
//

include { BCFTOOLS_MPILEUP_MULTISAMPLE } from '../../../modules/local/bcftools/mpileup_multisample/main'


workflow CALL_VARIANTS {

    take:
    variant_caller
    ch_alignment_and_index
    ch_reference_and_fai
    enable
    ch_multiqc_files

    main:
    // TODO: add option to split genome into chromosomes or chunks for parallelization

    // Group all samples into a single joint call
    // TODO: provide option for dataset name to replace 'all_samples'
    ch_joint_alignments = ch_alignment_and_index
        .map { meta, alignment, index -> [ 'all_samples', meta.id, alignment, index ] }
        .groupTuple()
        .map { group, samples, alignments, indexes ->
            [ [ id: group, samples: samples ], alignments, indexes ]
        }

    // Call variants with four alternative variant callers
    outputs_variant_calls = channel.empty()
    outputs_mpileup       = channel.empty()
    if ( variant_caller == 'bcftools' ) {
        BCFTOOLS_MPILEUP_MULTISAMPLE(
            ch_joint_alignments,
            ch_reference_and_fai,
            [], // intervals
            enable.save_mpileup
        )
        outputs_variant_calls = BCFTOOLS_MPILEUP_MULTISAMPLE.out.vcf
            .mix(BCFTOOLS_MPILEUP_MULTISAMPLE.out.index)
        outputs_mpileup       = BCFTOOLS_MPILEUP_MULTISAMPLE.out.mpileup
    }

    // TODO: add bcftools mpileup/call per sample calling and merging/joint genotyping

    // TODO: add GATK4 haplotype caller and genotype gvcfs

    // TODO: add parabricks haplotype caller and genotype gvcfs

    // TODO: convert *.vcf from parabricks to *vcf.gz and index

    // TODO: add bcftools stats for VCF files

    // TODO: add option to convert `*.vcf.gz` to `*.bcf`

    emit:
    outputs_variant_calls // channel: [ meta, *.vcf.gz ] and [ meta, *.tbi/csi ]
    outputs_mpileup       // channel: [ meta, *.mpileup.gz ], empty unless enable_save_mpileup
    ch_multiqc_files

}
