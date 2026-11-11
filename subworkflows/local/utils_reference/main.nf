nextflow.enable.types = true

include { SAMTOOLS_FAIDX                 } from '../../../modules/nf-core/samtools/faidx/main'
include { GATK4_CREATESEQUENCEDICTIONARY } from '../../../modules/nf-core/gatk4/createsequencedictionary/main'
include { stageError                     } from '../utils_stage_help/main'
include { inputError                     } from '../utils_stage_help/main'

workflow REFERENCE_UTILS {

    take:
    reference: Path   // reference fasta
    requires : Record // internal dependency relationships

    main:
    ref = record(id: reference.baseName, fasta: reference, fai: null)

    if ( requires.fai ) {
        faidx = SAMTOOLS_FAIDX(
            channel.value(
                record(id: ref.id, meta: null, fasta: reference, fai: null, get_sizes: false, samtools_faidx_args: null)
            )
        )
        reference_and_optional_fai = faidx.map { out -> record(id: out.id, fasta: reference, fai: out.fai) }
    } else {
        reference_and_optional_fai = channel.value(ref)
    }

    // Sequence dictionary (<basename>.dict) for GATK tools
    if ( requires.dict ) {
        gatk4_dict = GATK4_CREATESEQUENCEDICTIONARY(
            channel.value(record(id: ref.id, meta: null, fasta: reference, gatk4_createsequencedictionary_args: null))
        )
        // requires.dict is set only for GATK variant calling. Checked in the channel itself, so that nothing
        // using the fai starts before the check passes
        reference_with_dict = reference_and_optional_fai
            .map { r ->
                checkGatkContigLengths(r.fai)
                r
            }
            .combine(gatk4_dict)
            .map { r, d -> record(id: r.id, fasta: r.fasta, fai: r.fai, dict: d.dict) }
    } else {
        reference_with_dict = reference_and_optional_fai.map { r -> record(id: r.id, fasta: r.fasta, fai: r.fai, dict: null) }
    }

    emit:
    reference_and_dict: Value<Record> = reference_with_dict // record(id, fasta, fai, dict)
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
    reference = channel.value(record(id: 'no_reference', fasta: null, fai: null))
    if ( fasta && fai ) {
        reference = fasta.combine(fai).map { f, i -> record(id: f.baseName, fasta: f, fai: i) }
    } else if ( fasta && needs_fai ) {
        faidx = SAMTOOLS_FAIDX(
            fasta.map { f -> record(id: f.baseName, meta: null, fasta: f, fai: null, get_sizes: false, samtools_faidx_args: null) }
        )
        reference = fasta.combine(faidx).map { f, out -> record(id: out.id, fasta: f, fai: out.fai) }
    } else if ( fasta ) {
        reference = fasta.map { f -> record(id: f.baseName, fasta: f, fai: null) }
    }

    emit:
    reference: Value<Record> = reference // record(id, fasta, fai)
}

// GATK writes a .tbi for every .vcf.gz it creates, and tbi can't index positions past 2^29 bp, so fail fast on longer contigs.
// Runs inside an operator closure, so the message is logged before the error (stageError)
def checkGatkContigLengths(fai: Path) {
    def too_long = fai.readLines()
        .collect { line -> line.tokenize('\t') }
        .findAll { fields -> fields[1].toLong() > 2**29 }
    if ( too_long ) {
        stageError("--variant_caller gatk does not support indexing contigs longer than 2^29 bp (536,870,912): " +
            "${too_long.collect { fields -> "${fields[0]} (${fields[1]} bp)" }.join(', ')}. " +
            "Please use a different variant caller or split the reference into smaller contigs on runs of N.")
    }
}

// GATK finds the fai and the dictionary of a reference by name, next to the fasta: <fasta>.fai and <fasta without extension>.dict.
// The stages are given the three files as separate params, so check that their names agree. Runs inside an operator closure
def checkGatkReferenceNames(fasta: Path, fai: Path, dict: Path) {
    def fasta_name = fasta.name
    def expected_fai = "${fasta_name}.fai"
    def expected_dict = "${fasta_name.replaceFirst(/\.(fasta|fa|fna)$/, '')}.dict"
    if ( fai.name != expected_fai ) {
        inputError("GATK looks for the fai next to the fasta, as '${expected_fai}', but --fai is named '${fai.name}'. Rename the fai to '${expected_fai}'")
    }
    if ( dict.name != expected_dict ) {
        inputError("GATK looks for the sequence dictionary next to the fasta, as '${expected_dict}', but --dict is named '${dict.name}'. Rename the dictionary to '${expected_dict}'")
    }
}
