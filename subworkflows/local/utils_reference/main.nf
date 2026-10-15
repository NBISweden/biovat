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

        // requires.dict is set only for GATK variant calling (enable_variant_calling && variant_caller == 'gatk', main.nf).
        // Checked in the channel itself so nothing using the fai starts before the check passes
        ch_reference_and_optional_fai = ch_reference_and_optional_fai.map { meta, fasta, fai ->
            checkGatkContigLengths(fai)
            [meta, fasta, fai]
        }
    }

    emit:
    ch_reference_and_optional_fai
    ch_reference_dict

}

// GATK writes a .tbi for every .vcf.gz it creates, and tbi can't index positions past 2^29 bp, so fail fast on longer contigs
def checkGatkContigLengths(fai) {
    def too_long = fai.readLines()
        .collect { line -> line.tokenize('\t') }
        .findAll { fields -> fields[1].toLong() > 2**29 }
    if (too_long) {
        error(
            "--variant_caller gatk does not support indexing contigs longer than 2^29 bp (536,870,912): " +
            "${too_long.collect { fields -> "${fields[0]} (${fields[1]} bp)" }.join(', ')}. " +
            "Please use a different variant caller or split the reference into smaller contigs on runs of N."
        )
    }
}
