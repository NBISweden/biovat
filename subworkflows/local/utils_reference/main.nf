include { SAMTOOLS_FAIDX } from '../../../modules/nf-core/samtools/faidx/main'

workflow REFERENCE_UTILS {

    take:
    reference
    requires

    main:
    if ( requires.fai ) {
        SAMTOOLS_FAIDX(
            reference.map { meta, fasta -> [ meta, fasta, [] ] },
            false // Create sizes file
        )
        ch_reference_and_fai = reference.join(SAMTOOLS_FAIDX.out.fai).collect()
    } else {
        ch_reference_and_fai = reference.map { meta, fasta -> [ meta, fasta, [] ] }.collect()
    }

    emit:
    ch_reference_and_fai = ch_reference_and_fai // value channel: <Map> meta, <Path> fasta, <Path> fai

}
