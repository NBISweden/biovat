nextflow.enable.types = true

//
// Variant QC pipeline: statistics of the called variants with bcftools stats and vcftools
//

include { BCFTOOLS_STATS                    } from '../../modules/nf-core/bcftools/stats/main'
include { VCFTOOLS as VCFTOOLS_SUMMARY      } from '../../modules/nf-core/vcftools/main'
include { VCFTOOLS as VCFTOOLS_TSTV_COUNT   } from '../../modules/nf-core/vcftools/main'
include { VCFTOOLS as VCFTOOLS_TSTV_QUAL    } from '../../modules/nf-core/vcftools/main'
include { VCFTOOLS as VCFTOOLS_RELATEDNESS2 } from '../../modules/nf-core/vcftools/main'
include { REFERENCE_VALUE                   } from '../../subworkflows/local/utils_reference/main'
include { STAGE_HELP                        } from '../../subworkflows/local/utils_stage_help/main'
include { checkStageInput                   } from '../../subworkflows/local/utils_stage_help/main'

// A row of the variant calls samplesheet (CSV)
record VariantCallSample {
    id   : String // name of the callset
    vcf  : Path   // VCF file
    index: Path   // index of the VCF file
}

record VariantCall {
    meta : Record // callset information, requires id
    vcf  : Path   // VCF file
    index: Path   // index of the VCF file
}

params {
    samplesheet  : Channel<VariantCallSample>? // variant calls to check, as a CSV with the columns id, vcf and index
    variant_calls: Channel<VariantCall>?       // alternative to the samplesheet: variant calls with their meta record, from a YAML or JSON file or a calling pipeline
    fasta        : Value<Path>?          // reference fasta, used by bcftools stats
    level        : String?               // prefix of the output files, to tell apart calls from different stages (default: none)
    help         : Boolean = false
    help_full    : Boolean = false
}

workflow {

    main:
    STAGE_HELP(params.help, params.help_full, "${moduleDir}/nextflow_schema.json", 'nextflow run pipelines/variant_qc --samplesheet variant_calls.csv --fasta reference.fasta')
    checkStageInput(params.samplesheet, params.variant_calls, 'variant_calls')
    reference = REFERENCE_VALUE(params.fasta, null, false)

    // Variant calls: from the samplesheet, or given with their meta record
    samplesheet_calls = channel.empty()
    if ( params.samplesheet ) {
        samplesheet_calls = params.samplesheet.map { s -> record(meta: record(id: s.id), vcf: s.vcf, index: s.index) }
    }
    given_calls = channel.empty()
    if ( params.variant_calls ) {
        given_calls = params.variant_calls.map { c -> record(meta: record(id: c.meta.id), vcf: c.vcf, index: c.index) }
    }
    variant_calls = samplesheet_calls.mix(given_calls)

    // BCFTOOLS_STATS
    bcftools_stats = BCFTOOLS_STATS(
        variant_calls
            .combine(reference)
            .map { call, ref ->
                record(
                    id                 : call.meta.id,
                    meta               : call.meta,
                    vcf                : call.vcf,
                    tbi                : call.index,
                    regions            : null,
                    targets            : null,
                    samples            : null,
                    exons              : null,
                    fasta              : ref.fasta,
                    bcftools_stats_args: null,
                    output_prefix      : qcPrefix(call.meta, params.level)
                )
            }
    )

    // VCFTOOLS: the index is not used
    vcftools_calls = variant_calls.map { call -> record(meta: call.meta, variant_file: call.vcf) }
    vcftools_tstv_counts = VCFTOOLS_TSTV_COUNT(
        vcftools_calls.map { call -> vcftoolsInput(call, params.level, '--TsTv-by-count') }
    )
    vcftools_tstv_qual = VCFTOOLS_TSTV_QUAL(
        vcftools_calls.map { call -> vcftoolsInput(call, params.level, '--TsTv-by-qual') }
    )
    vcftools_filter_summary = VCFTOOLS_SUMMARY(
        vcftools_calls.map { call -> vcftoolsInput(call, params.level, '--FILTER-summary') }
    )
    vcftools_relatedness2 = VCFTOOLS_RELATEDNESS2(
        vcftools_calls.map { call -> vcftoolsInput(call, params.level, '--relatedness2') }
    )

    publish:
    bcftools_stats        = bcftools_stats.map { out -> record(meta: out.meta, stats: out.stats) }
    vcftools_tstv_counts  = vcftools_tstv_counts.map { out -> record(meta: out.meta, tstv_count: out.tstv_count) }
    vcftools_tstv_qual    = vcftools_tstv_qual.map { out -> record(meta: out.meta, tstv_qual: out.tstv_qual) }
    vcftools_filter_summary = vcftools_filter_summary.map { out -> record(meta: out.meta, filter_summary: out.filter_summary) }
    vcftools_relatedness2 = vcftools_relatedness2.map { out -> record(meta: out.meta, relatedness2: out.relatedness2) }
    multiqc_files         = bcftools_stats.map { out -> out.stats }
        .mix(vcftools_tstv_counts.map { out -> out.tstv_count })
        .mix(vcftools_tstv_qual.map { out -> out.tstv_qual })
        .mix(vcftools_filter_summary.map { out -> out.filter_summary })
        .mix(vcftools_relatedness2.map { out -> out.relatedness2 })

}

output {
    bcftools_stats         : Channel<Record> { path 'bcftools_stats' }
    vcftools_tstv_counts   : Channel<Record> { path 'vcftools' }
    vcftools_tstv_qual     : Channel<Record> { path 'vcftools' }
    vcftools_filter_summary: Channel<Record> { path 'vcftools' }
    vcftools_relatedness2  : Channel<Record> { path 'vcftools' }
    multiqc_files          : Channel<Path> { path 'multiqc_files' }
}

// Output file prefix: the callset id, behind the level when one is given
def qcPrefix(meta: Record, level: String?) {
    return level ? "${level}_${meta.id}" : null
}

def vcftoolsInput(call: Record, level: String?, vcftools_args: String) {
    return record(id: call.meta.id, meta: call.meta, variant_file: call.variant_file, bed: null, diff_variant_file: null, vcftools_args: vcftools_args, output_prefix: qcPrefix(call.meta, level))
}
