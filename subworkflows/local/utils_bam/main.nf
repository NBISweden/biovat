include { VALIDATE_READGROUP_HEADER } from '../../../modules/local/validate_readgroup_header/main'
include { SAMTOOLS_SORT             } from '../../../modules/nf-core/samtools/sort/main'
include { ALIGNMENT_QC              } from '../alignment_qc/main'

workflow INGEST_BAM_OR_CRAM {

    take:
    ch_input_bam_cram
    ch_reference_and_optional_fai
    enable
    ch_multiqc_files

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

    // INGEST_BAM_OR_CRAM:ALIGNMENT_QC
    outputs_input_flagstat = channel.empty()
    outputs_input_riker    = channel.empty()
    outputs_input_qualimap = channel.empty()
    if ( enable.align_qc ) {
        ALIGNMENT_QC(
            user_input_bam_cram,
            ch_reference_and_optional_fai,
            enable,
            'input'
        )
        ch_multiqc_files = ch_multiqc_files
            .mix(
                ALIGNMENT_QC.out.flagstat_outputs.map{ _meta, file -> file },
                ALIGNMENT_QC.out.riker_outputs.map{ _meta, file -> file },
                ALIGNMENT_QC.out.qualimap_outputs.map{ _meta, file -> file }
            )
        outputs_input_flagstat = ALIGNMENT_QC.out.flagstat_outputs
        outputs_input_riker    = ALIGNMENT_QC.out.riker_outputs
        outputs_input_qualimap = ALIGNMENT_QC.out.qualimap_outputs
    }

    emit:
    user_input_bam_cram    // channel: <Map> meta, <Path> bam/cram, <Path> csi/crai
    outputs_input_flagstat
    outputs_input_riker
    outputs_input_qualimap
    ch_multiqc_files

}
