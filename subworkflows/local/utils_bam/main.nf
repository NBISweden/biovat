include { SAMTOOLS_SORT } from '../../../modules/nf-core/samtools/sort/main'

workflow INGEST_BAM_OR_CRAM {

    take:
    ch_input_bam_cram
    ch_reference_and_optional_fai
    enable

    main:
    SAMTOOLS_SORT(
        ch_input_bam_cram,
        enable.cram_format ? ch_reference_and_optional_fai : [[],[],[]],
        enable.cram_format ? "crai" : "csi"
    )
    normalised_bam      = SAMTOOLS_SORT.out.bam.join(SAMTOOLS_SORT.out.index)
    normalised_cram     = SAMTOOLS_SORT.out.cram.join(SAMTOOLS_SORT.out.index)
    user_input_bam_cram = normalised_bam.mix(normalised_cram)

    emit:
    user_input_bam_cram

}
