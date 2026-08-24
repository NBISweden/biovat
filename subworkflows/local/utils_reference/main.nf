include { SAMTOOLS_FAIDX } from '../../../modules/nf-core/samtools/faidx/main'

workflow REFERENCE_UTILS {

    take:
    reference

    main:
    SAMTOOLS_FAIDX(
        reference.map { meta, fasta -> [ meta, fasta, [] ] },
        true // Create sizes file 
    )

    emit:
    reference_fai   = SAMTOOLS_FAIDX.out.fai
    reference_sizes = SAMTOOLS_FAIDX.out.sizes

}
