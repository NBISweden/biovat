include { VALIDATE_READGROUP_HEADER } from '../../../modules/local/validate_readgroup_header/main'
include { SAMTOOLS_ADDREPLACERG     } from '../../../modules/nf-core/samtools/addreplacerg/main'
include { SAMTOOLS_SORT             } from '../../../modules/nf-core/samtools/sort/main'
include { ALIGNMENT_QC              } from '../alignment_qc/main'

workflow INGEST_BAM_OR_CRAM {

    take:
    ch_input_bam_cram
    ch_reference_and_optional_fai
    enable
    ch_multiqc_files

    main:
    // Reject a BAM/CRAM with several @RG lines, or one whose @RG tags are missing or disagree with its samplesheet row
    validate_readgroup_header_out = VALIDATE_READGROUP_HEADER(
        ch_input_bam_cram
    )
    ch_validated = validate_readgroup_header_out.validated
        .branch { meta, bam_cram, rg_status ->
            missing: rg_status == 'missing'
                return [ meta, bam_cram ]
            present: true
                return [ meta, bam_cram ]
        }

    // A BAM/CRAM with no @RG line gets one built from its samplesheet row
    samtools_addreplacerg_out = SAMTOOLS_ADDREPLACERG(
        ch_validated.missing.map { meta, bam_cram ->
            log.warn "No @RG header line in '${bam_cram.name}' (sample '${meta.id}', library '${meta.library}'): adding one from the samplesheet and tagging the reads"
            [ meta, bam_cram, [], '' ]
        },
        ch_reference_and_optional_fai.map { meta, fasta, fai -> [ meta, fasta, fai, [] ] }
    )

    // Ensure compatible sort order, index, and convert CRAM to BAM/BAM to CRAM if required
    samtools_sort_out = SAMTOOLS_SORT(
        ch_validated.present.mix(samtools_addreplacerg_out.bam),
        ch_reference_and_optional_fai,
        enable.cram_format ? "crai" : "csi",
    )
    user_input_bam_cram = samtools_sort_out.bam
        .mix(samtools_sort_out.cram)
        .join(samtools_sort_out.index)

    // INGEST_BAM_OR_CRAM:ALIGNMENT_QC
    outputs_input_flagstat = channel.empty()
    outputs_input_riker    = channel.empty()
    outputs_input_qualimap = channel.empty()
    if ( enable.align_qc ) {
        alignment_qc_out = ALIGNMENT_QC(
            user_input_bam_cram,
            ch_reference_and_optional_fai,
            enable,
            'input'
        )
        ch_multiqc_files = ch_multiqc_files
            .mix(
                alignment_qc_out.flagstat_outputs.map{ _meta, file -> file },
                alignment_qc_out.riker_outputs.map{ _meta, file -> file },
                alignment_qc_out.qualimap_outputs.map{ _meta, file -> file }
            )
        outputs_input_flagstat = alignment_qc_out.flagstat_outputs
        outputs_input_riker    = alignment_qc_out.riker_outputs
        outputs_input_qualimap = alignment_qc_out.qualimap_outputs
    }

    emit:
    user_input_bam_cram    // channel: <Map> meta, <Path> bam/cram, <Path> csi/crai
    outputs_input_flagstat
    outputs_input_riker
    outputs_input_qualimap
    ch_multiqc_files

}
