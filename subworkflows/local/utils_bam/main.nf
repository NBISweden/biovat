include { VALIDATE_READGROUP_HEADER } from '../../../modules/local/validate_readgroup_header/main'
include { SAMTOOLS_SORT             } from '../../../modules/nf-core/samtools/sort/main'

workflow INGEST_BAM_OR_CRAM {

    take:
    ch_input_bam_cram
    ch_reference_and_optional_fai
    enable

    main:
    // Reject a BAM/CRAM whose @RG SM/LB disagrees with its samplesheet row
    VALIDATE_READGROUP_HEADER(
        ch_input_bam_cram
    )

    // Ensure compatibile sort order, index, and convert CRAM to BAM/BAM to CRAM if required
    SAMTOOLS_SORT(
        VALIDATE_READGROUP_HEADER.out.validated,
        ch_reference_and_optional_fai,
        enable.cram_format ? "crai" : "csi",
    )
    user_input_bam_cram = SAMTOOLS_SORT.out.bam
        .mix(SAMTOOLS_SORT.out.cram)
        .join(SAMTOOLS_SORT.out.index)

    emit:
    user_input_bam_cram

}
