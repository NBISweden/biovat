include { SAMTOOLS_SORT } from '../../../modules/nf-core/samtools/sort/main'

workflow INGEST_BAM_OR_CRAM {

    take:
    ch_input_bam_cram
    ch_reference_and_optional_fai
    enable

    main:
    // ifEmpty handles case with no reference set (only BAM, CRAM input forces early error)
    SAMTOOLS_SORT(
        ch_input_bam_cram,
        ch_reference_and_optional_fai.ifEmpty([[],[],[]]),
        enable.cram_format ? "crai" : "csi"
    )
    normalised_bam      = SAMTOOLS_SORT.out.bam.join(SAMTOOLS_SORT.out.index)
    normalised_cram     = SAMTOOLS_SORT.out.cram.join(SAMTOOLS_SORT.out.index)
    user_input_bam_cram = normalised_bam.mix(normalised_cram)

    emit:
    user_input_bam_cram

}
