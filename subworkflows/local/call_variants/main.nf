//
// Variant calling subworkflow
//

include { BCFTOOLS_MPILEUP } from '../modules/nf-core/bcftools/mpileup/main'
include { FREEBAYES } from '../modules/nf-core/freebayes/main'


workflow CALL_VARIANTS {

    take:
    variant_caller
    ch_alignment_and_index // CRAM/BAM files from PROCESS_ALIGNMENTS subworkflow or user-provided
    ch_reference_and_fai   // value channel: reference fasta and fai index
    enable                 // enable user-provided BAM qc, enable split genome, enable vcf.gz to bcf
    ch_multiqc_files       // channel: MultiQC files

    main:
    // TODO: add option to run BAM_QC on user-provided BAM files

    // TODO: add option to split genome into chromosomes or chunks for parallelization

    // Call variants with four alternative variant callers
    // TODO: add option to run variant calling on user-provided BAM files or a mix of BAM files from BioVAT and user

    // TODO: add bcftools mpileup/call

    // TODO: add freeBayes

    // TODO: add GATK4 haplotype caller and genotype gvcfs

    // TODO: add parabricks haplotype caller and genotype gvcfs

    // TODO: convert *.vcf from parabricks to *vcf.gz and index

    // TODO: add bcftools stats for VCF files

    // TODO: add option to convert `*.vcf.gz` to `*.bcf`

    emit:
    // vcf plus index
    // bcf plus index
    // bcftools stats output

}
