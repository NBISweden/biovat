nextflow.enable.types = true

include { SAMTOOLS_FAIDX                 } from '../../../modules/nf-core/samtools/faidx/main'
include { GATK4_CREATESEQUENCEDICTIONARY } from '../../../modules/nf-core/gatk4/createsequencedictionary/main'

workflow REFERENCE_UTILS {

    take:
    reference: Path   // reference fasta
    requires : Record // internal dependency relationships

    main:
    ref = record(meta: record(id: reference.baseName), fasta: reference, fai: null)

    if ( requires.fai ) {
        faidx = SAMTOOLS_FAIDX(
            channel.value(
                record(id: ref.meta.id, meta: ref.meta, fasta: reference, fai: null, get_sizes: false, samtools_faidx_args: null)
            )
        )
        reference_and_optional_fai = faidx.map { out -> record(meta: out.meta, fasta: reference, fai: out.fai) }
    } else {
        reference_and_optional_fai = channel.value(ref)
    }

    // Sequence dictionary (<basename>.dict) for GATK tools
    if ( requires.dict ) {
        gatk4_dict = GATK4_CREATESEQUENCEDICTIONARY(
            channel.value(record(id: ref.meta.id, meta: ref.meta, fasta: reference, gatk4_createsequencedictionary_args: null))
        )
        // requires.dict is set only for GATK variant calling. Checked in the channel itself, so that nothing
        // using the fai starts before the check passes
        reference_with_dict = reference_and_optional_fai
            .map { r ->
                checkGatkContigLengths(r.fai)
                r
            }
            .combine(gatk4_dict)
            .map { r, d -> record(meta: r.meta, fasta: r.fasta, fai: r.fai, dict: d.dict) }
    } else {
        reference_with_dict = reference_and_optional_fai.map { r -> record(meta: r.meta, fasta: r.fasta, fai: r.fai, dict: null) }
    }

    emit:
    reference_and_dict: Value<Record> = reference_with_dict // record(meta, fasta, fai, dict)
}

//
// Build the reference record from optional fasta and fai values.
// A stage pipeline takes the two files as separate Value params, so that they can come from the command line or from a calling pipeline.
// When the stage needs the fai index and only the fasta is given, the index is created
//
workflow REFERENCE_VALUE {

    take:
    fasta    : Value<Path>? // reference fasta
    fai      : Value<Path>? // fai index of the reference fasta
    needs_fai: Boolean      // whether the stage needs the fasta and its fai

    main:
    if ( needs_fai && !fasta ) {
        error "A reference fasta (--fasta) is required by the enabled tools, for example Riker, CRAM output and variant calling"
    }

    // No reference, unless a fasta is given
    reference = channel.value(record(meta: record(id: 'no_reference'), fasta: null, fai: null)) as Value<Record>
    if ( fasta && fai ) {
        reference = fasta.combine(fai).map { f, i -> record(meta: record(id: f.baseName), fasta: f, fai: i) }
    } else if ( fasta && needs_fai ) {
        faidx = SAMTOOLS_FAIDX(
            fasta.map { f -> record(id: f.baseName, meta: record(id: f.baseName), fasta: f, fai: null, get_sizes: false, samtools_faidx_args: null) }
        )
        reference = fasta.combine(faidx).map { f, out -> record(meta: out.meta, fasta: f, fai: out.fai) }
    } else if ( fasta ) {
        reference = fasta.map { f -> record(meta: record(id: f.baseName), fasta: f, fai: null) }
    }

    emit:
    reference: Value<Record> = reference // record(meta, fasta, fai)
}

// GATK writes a .tbi for every .vcf.gz it creates, and tbi can't index positions past 2^29 bp, so fail fast on longer contigs
def checkGatkContigLengths(fai: Path) {
    def too_long = fai.readLines()
        .collect { line -> line.tokenize('\t') }
        .findAll { fields -> fields[1].toLong() > 2**29 }
    if ( too_long ) {
        error(
            "--variant_caller gatk does not support indexing contigs longer than 2^29 bp (536,870,912): " +
            "${too_long.collect { fields -> "${fields[0]} (${fields[1]} bp)" }.join(', ')}. " +
            "Please use a different variant caller or split the reference into smaller contigs on runs of N."
        )
    }
}
