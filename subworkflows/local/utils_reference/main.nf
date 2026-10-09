include { SAMTOOLS_FAIDX                 } from '../../../modules/nf-core/samtools/faidx/main'
include { GATK4_CREATESEQUENCEDICTIONARY } from '../../../modules/nf-core/gatk4/createsequencedictionary/main'

workflow REFERENCE_UTILS {

    take:
    reference
    requires

    main:
    if ( requires.fai ) {
        samtools_faidx_out = SAMTOOLS_FAIDX(
            reference.map { meta, fasta -> [ meta, fasta, [] ] },
            false // Create sizes file
        )
        ch_reference_and_optional_fai = reference.join(samtools_faidx_out.fai).collect()
    } else {
        ch_reference_and_optional_fai = reference.map { meta, fasta -> [ meta, fasta, [] ] }.collect()
    }

    // Sequence dictionary (<basename>.dict) for GATK tools, which look for it alongside the reference fasta
    ch_reference_dict = channel.value([[], []])
    if ( requires.dict ) {
        gatk4_createsequencedictionary_out = GATK4_CREATESEQUENCEDICTIONARY(
            reference
        )
        ch_reference_dict = gatk4_createsequencedictionary_out.dict.collect()
    }

    emit:
    ch_reference_and_optional_fai
    ch_reference_dict

}
