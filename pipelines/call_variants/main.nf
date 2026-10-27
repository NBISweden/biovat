nextflow.enable.types = true

//
// Variant calling pipeline: splits the genome into chunks, calls variants per chunk with bcftools or GATK,
// and concatenates the chunks into one joint callset
//

include { SPLITGENOME                  } from '../../modules/local/splitgenome/main'
include { BCFTOOLS_MPILEUP_MULTISAMPLE } from '../../modules/local/bcftools/mpileup_multisample/main'
include { BCFTOOLS_CONCAT              } from '../../modules/nf-core/bcftools/concat/main'
include { GATK4_HAPLOTYPECALLER        } from '../../modules/nf-core/gatk4/haplotypecaller/main'
include { GATK4_GENOMICSDBIMPORT       } from '../../modules/nf-core/gatk4/genomicsdbimport/main'
include { GATK4_GENOTYPEGVCFS          } from '../../modules/nf-core/gatk4/genotypegvcfs/main'
include { workflow as VARIANT_QC       } from '../variant_qc'
include { REFERENCE_VALUE              } from '../../subworkflows/local/utils_reference/main'
include { STAGE_HELP                   } from '../../subworkflows/local/utils_stage_help/main'
include { checkStageInput              } from '../../subworkflows/local/utils_stage_help/main'

// A row of the alignments samplesheet (CSV)
record AlignmentSample {
    sample    : String  // sample name
    library_id: String? // library of the alignment
    platform  : String  // sequencing platform, only ILLUMINA is called
    single_end: Boolean // whether the reads are single-end
    alignment : Path    // BAM or CRAM file
    index     : Path    // index of the BAM or CRAM file
}

record Alignment {
    meta     : Record // sample information, requires id and pl
    alignment: Path   // BAM or CRAM file
    index    : Path   // index of the BAM or CRAM file
}

record SampleMetadata {
    sample    : String  // sample name
    population: String? // population of the sample, needed for every sample when grouping samples
}

params {
    samplesheet           : Channel<AlignmentSample>? // alignments to call, as a CSV with the columns sample, library_id, platform, single_end, alignment and index
    alignments            : Channel<Alignment>?     // alternative to the samplesheet: alignments with their meta record, from a YAML or JSON file or a calling pipeline
    sample_metadata       : Channel<SampleMetadata>? // sample metadata (CSV with the columns sample and population), only used with group_samples
    variant_caller        : String = 'bcftools_multisample' // variant caller: 'bcftools_multisample' or 'gatk'
    chunk_size            : Integer?                // chunk size (bp) for splitting the genome, default is dynamic
    min_length            : Integer = 1000          // minimum contig length (bp) to be called
    callset_prefix        : String = 'all_samples'  // file name prefix of the VCF with all samples
    group_samples         : Boolean = false         // group samples into populations (bcftools_multisample only), needs sample_metadata
    save_mpileup          : Boolean = false         // keep the bcftools mpileup output (bcftools_multisample only)
    bcftools_mpileup_extra: String = '--no-BAQ'     // extra arguments for bcftools mpileup
    bcftools_call_extra   : String = '--variants-only' // extra arguments for bcftools call
    variant_qc            : Boolean = true          // run quality checks on the joint callset
    fasta                 : Value<Path>?            // reference fasta, required
    fai                   : Value<Path>?            // fai index of the reference fasta, required
    dict                  : Value<Path>?            // sequence dictionary of the reference fasta, required for gatk
    help                  : Boolean = false
    help_full             : Boolean = false
}

workflow {

    main:
    STAGE_HELP(params.help, params.help_full, "${moduleDir}/nextflow_schema.json", 'nextflow run pipelines/call_variants --samplesheet alignments.csv --fasta reference.fasta --fai reference.fasta.fai')
    checkStageInput(params.samplesheet, params.alignments, 'alignments')
    if ( !params.fasta || !params.fai ) {
        error "Variant calling requires --fasta and --fai"
    }
    if ( !(params.variant_caller in [ 'bcftools_multisample', 'gatk' ]) ) {
        error "Unknown variant_caller '${params.variant_caller}', expected bcftools_multisample or gatk"
    }
    if ( params.variant_caller == 'gatk' && !params.dict ) {
        error "--variant_caller gatk requires --dict"
    }
    if ( params.group_samples && !params.sample_metadata ) {
        error "--group_samples requires --sample_metadata"
    }
    reference = REFERENCE_VALUE(params.fasta, params.fai, true)

    // Alignments: from the samplesheet, or given with their meta record
    samplesheet_alignments = channel.empty()
    if ( params.samplesheet ) {
        samplesheet_alignments = params.samplesheet.map { s ->
            record(
                meta     : record(id: s.sample, pl: s.platform),
                alignment: s.alignment,
                index    : s.index
            )
        }
    }
    given_alignments = channel.empty()
    if ( params.alignments ) {
        given_alignments = params.alignments.map { a -> record(meta: record(id: a.meta.id, pl: a.meta.pl), alignment: a.alignment, index: a.index) }
    }
    alignments = samplesheet_alignments.mix(given_alignments)

    // Branch on platform to avoid calling mixed-platform samples together. Only Illumina is currently called
    illumina    = alignments.filter { aln -> aln.meta.pl == 'ILLUMINA' }
    unsupported = alignments.filter { aln -> aln.meta.pl != 'ILLUMINA' }

    // Warn once, listing every sample/platform left out
    unsupported
        .map { aln -> "${aln.meta.id} (${aln.meta.pl})" }
        .collect()
        .subscribe { skipped ->
            if ( skipped.size() > 0 ) {
                log.warn(
                    "Variant calling currently supports only ILLUMINA alignments. " +
                    "These sample alignments are excluded from variant calling: ${skipped.toList().toSorted().join(', ')}"
                )
            }
        }

    // Split the reference genome into chunks (BED intervals) for parallelization
    splitgenome = SPLITGENOME(
        reference.map { ref -> record(id: ref.meta.id, meta: ref.meta, fai: ref.fai, chunk_size: params.chunk_size, min_length: params.min_length, splitgenome_args: null) }
    )
    // Carry the chunk count so that concatenation knows when all chunks are there
    bed_intervals = splitgenome.flatMap { out ->
        def beds = out.chunks.toList()
        beds.collect { bed -> record(chunk: bed.baseName, chunk_bed: bed, n_chunks: beds.size()) }
    }

    // Make contig exclusions visible on the console when they cover more than 5% of the reference
    splitgenome.subscribe { out -> warnExcludedRegions(out.summary, params.min_length) }

    // Population file for bcftools call --group-samples, listing every sample in the sample metadata.
    // Names in the population file but not in the VCF are ignored
    population = channel.value(record(file: null))
    if ( params.group_samples ) {
        population = params.sample_metadata
            .map { sample ->
                if ( sample.population == null ) {
                    error "--group_samples requires a population for every sample in --sample_metadata. Missing for: ${sample.sample}"
                }
                "${sample.sample}\t${sample.population}"
            }
            .collectFile(name: 'sample_population.tsv', newLine: true, sort: true)
            .collect()
            .map { files -> record(file: files.toList()[0]) }
    }

    // Every caller makes per-chunk calls as record(meta, chunk, vcf, index), concatenated below
    chunk_calls = channel.empty()
    mpileup     = channel.empty()

    // bcftools: multi-sample joint calling
    if ( params.variant_caller == 'bcftools_multisample' ) {
        // Group all samples
        grouped = illumina
            .map { aln -> tuple(params.callset_prefix, aln) }
            .groupBy()
            .map { group, alns ->
                // sort by sample id so the VCF sample columns don't depend on channel arrival order
                // a sample can have several alignments (e.g. one per library), so order those by file name as well
                def sorted = alns.toSorted { a, b -> "${a.meta.id}/${a.alignment.name}" <=> "${b.meta.id}/${b.alignment.name}" }
                record(
                    id     : group,
                    samples: sorted.collect { aln -> aln.meta.id }.toList(),
                    bams   : sorted.collect { aln -> aln.alignment }.toList(),
                    indexes: sorted.collect { aln -> aln.index }.toList()
                )
            }
        // Combine each group with BED intervals for region-specific parallel calling
        mpileup_calls = BCFTOOLS_MPILEUP_MULTISAMPLE(
            grouped
                .combine(bed_intervals)
                .combine(reference)
                .combine(population)
                .map { group, bed, ref, pop ->
                    record(
                        id                   : "${group.id}.${bed.chunk}",
                        meta                 : record(id: "${group.id}.${bed.chunk}", group_id: group.id, samples: group.samples, chunk: bed.chunk, n_chunks: bed.n_chunks),
                        bams                 : group.bams,
                        indexes              : group.indexes,
                        intervals            : bed.chunk_bed,
                        fasta                : ref.fasta,
                        fai                  : ref.fai,
                        save_mpileup         : params.save_mpileup,
                        group_samples        : params.group_samples,
                        population_file      : pop.file,
                        bcftools_mpileup_args: params.bcftools_mpileup_extra,
                        bcftools_call_args   : [ '--multiallelic-caller', params.bcftools_call_extra ].findAll { arg -> arg != '' }.join(' '),
                        output_prefix        : null
                    )
                }
        )
        chunk_calls = mpileup_calls.map { out -> record(meta: out.meta, chunk: out.meta.chunk, vcf: out.vcf, index: out.index) }
        mpileup     = mpileup_calls
            .filter { out -> out.mpileup != null }
            .map { out -> record(meta: out.meta, mpileup: out.mpileup) }
    }

    // GATK4: per-sample calling and joint genotyping
    if ( params.variant_caller == 'gatk' ) {
        // GATK4_HAPLOTYPECALLER in gvcf mode, for each sample and chunk
        haplotypecaller = GATK4_HAPLOTYPECALLER(
            illumina
                .combine(bed_intervals)
                .combine(reference)
                .combine(params.dict)
                .map { aln, bed, ref, dict ->
                    record(
                        id                        : aln.meta.id,
                        meta                      : record(id: aln.meta.id, chunk: bed.chunk),
                        input                     : aln.alignment,
                        input_index               : aln.index,
                        intervals                 : bed.chunk_bed,
                        dragstr_model             : null,
                        fasta                     : ref.fasta,
                        fai                       : ref.fai,
                        dict                      : dict,
                        dbsnp                     : null,
                        dbsnp_tbi                 : null,
                        // Per-sample GVCFs for joint genotyping. The .g suffix gives *.g.vcf.gz, which GATK expects for GVCFs
                        gatk4_haplotypecaller_args: '--emit-ref-confidence GVCF',
                        output_prefix             : "${aln.meta.id}.${bed.chunk}.g"
                    )
                }
        )
        // Consolidate the GVCFs of a chunk into one GenomicsDB workspace per chunk. The index files are only staged next
        // to the GVCFs, so they are grouped on their own to get a bag
        gvcfs_by_chunk = haplotypecaller
            .map { out -> tuple(out.meta.chunk, record(sample: out.meta.id, gvcf: out.vcf)) }
            .groupBy()
            .map { chunk, gvcfs ->
                // sort by sample id so the workspace sample order doesn't depend on channel arrival order
                def sorted = gvcfs.toSorted { a, b -> a.sample <=> b.sample }
                record(chunk: chunk, samples: sorted.collect { g -> g.sample }.toList(), gvcfs: sorted.collect { g -> g.gvcf }.toList())
            }
        tbis_by_chunk = haplotypecaller
            .map { out -> tuple(out.meta.chunk, out.tbi) }
            .groupBy()
            .map { chunk, tbis -> record(chunk: chunk, tbis: tbis) }
        genomicsdbimport = GATK4_GENOMICSDBIMPORT(
            gvcfs_by_chunk
                .join(tbis_by_chunk, by: 'chunk')
                .join(bed_intervals, by: 'chunk')
                .map { chunk ->
                    record(
                        id                         : "${params.callset_prefix}.${chunk.chunk}",
                        meta                       : record(id: "${params.callset_prefix}.${chunk.chunk}", group_id: params.callset_prefix, samples: chunk.samples, chunk: chunk.chunk, n_chunks: chunk.n_chunks),
                        vcf                        : chunk.gvcfs,
                        tbi                        : chunk.tbis,
                        interval_file              : chunk.chunk_bed,
                        interval_value             : null,
                        wspace                     : null,
                        run_intlist                : false, // create a new workspace rather than list an existing one's intervals
                        run_updatewspace           : false, // create a new workspace rather than add samples to an existing one
                        input_map                  : false, // pass GVCFs as --variant rather than a sample name map
                        // Import samples in batches of 50, per "broadinstitute/warp" repo code & GATK recommendation
                        // https://gatk.broadinstitute.org/hc/en-us/articles/360035889971--How-to-Consolidate-GVCFs-for-joint-calling-with-GenotypeGVCFs
                        // Store all contigs of a chunk in one GenomicsDB partition instead of one per contig (better performance for fragmented regions/genomes)
                        // https://github.com/broadinstitute/gatk/pull/6681
                        gatk4_genomicsdbimport_args: '--batch-size 50 --merge-contigs-into-num-partitions 1',
                        output_prefix              : null
                    )
                }
        )
        // Joint genotyping per chunk, from the GenomicsDB workspace
        // Note: chunks are whole contigs, so no call can span a chunk boundary and no boundary filtering is needed.
        // However, if we eventually support splitting contigs (e.g. contigs too long for a .tbi index), add
        // gatk4_genotypegvcfs_args '--variant-output-filtering STARTS_IN' here to avoid duplicate calls at chunk boundaries,
        // and drop --merge-contigs-into-num-partitions from GATK4_GENOMICSDBIMPORT, which needs whole contigs
        genotypegvcfs = GATK4_GENOTYPEGVCFS(
            genomicsdbimport
                .map { out -> record(meta: out.meta, chunk: out.meta.chunk, genomicsdb: out.genomicsdb) }
                .join(bed_intervals, by: 'chunk')
                .combine(reference)
                .combine(params.dict)
                .map { chunk, ref, dict ->
                    record(
                        id                      : chunk.meta.id,
                        meta                    : chunk.meta,
                        input                   : chunk.genomicsdb,
                        gvcf_index              : null,
                        intervals               : chunk.chunk_bed,
                        intervals_index         : null,
                        fasta                   : ref.fasta,
                        fai                     : ref.fai,
                        dict                    : dict,
                        dbsnp                   : null,
                        dbsnp_tbi               : null,
                        gatk4_genotypegvcfs_args: null,
                        output_prefix           : null
                    )
                }
        )
        chunk_calls = genotypegvcfs.map { out -> record(meta: out.meta, chunk: out.meta.chunk, vcf: out.vcf, index: out.tbi) }
    }

    // TODO: add parabricks haplotype caller and genotype gvcfs

    // Concatenate the genome chunks of each group using BCFTOOLS_CONCAT
    vcf_groups = chunk_calls
        .map { call ->
            // tag the joint VCF (and the variant QC named after it) with the caller, e.g. <callset_prefix>.gatk
            tuple(record(id: "${call.meta.group_id}.${params.variant_caller}", samples: call.meta.samples), call)
        }
        .groupBy()
        .map { group, calls ->
            // sort files by chunk id (e.g. "chunk_00002") to preserve genomic order
            def sorted = calls.toSorted { a, b -> a.chunk <=> b.chunk }
            record(meta: group, vcfs: sorted.collect { c -> c.vcf }.toList())
        }
    // The index files are only staged next to the VCFs, so they are grouped on their own to get a bag
    chunk_indexes = chunk_calls
        .map { call -> tuple(record(id: "${call.meta.group_id}.${params.variant_caller}", samples: call.meta.samples), call.index) }
        .groupBy()
        .map { group, indexes -> record(meta: group, tbi: indexes) }
    chunk_groups = vcf_groups.join(chunk_indexes, by: 'meta')
    // A single chunk skips concatenation. It is renamed to the group meta id when published
    to_concat = chunk_groups.filter { group -> group.vcfs.size() > 1 }
    skipped   = chunk_groups
        .filter { group -> group.vcfs.size() == 1 }
        .map { group -> record(meta: group.meta, vcf: group.vcfs[0], index: group.tbi.toList()[0]) }
    concat = BCFTOOLS_CONCAT(
        to_concat.map { group ->
            record(
                id                  : group.meta.id,
                meta                : group.meta,
                vcfs                : group.vcfs,
                tbi                 : group.tbi,
                bcftools_concat_args: '--write-index=csi --output-type z',
                output_prefix       : null
            )
        }
    )
    // The concatenated VCFs with their indexes, for variant QC and publishing
    variant_calls = concat
        .map { out -> record(meta: out.meta, vcf: out.vcf, index: out.index) }
        .mix(skipped)

    // CALL_VARIANTS:VARIANT_QC
    bcftools_stats          = channel.empty()
    vcftools_tstv_counts    = channel.empty()
    vcftools_tstv_qual      = channel.empty()
    vcftools_filter_summary = channel.empty()
    vcftools_relatedness2   = channel.empty()
    qc_multiqc_files        = channel.empty()
    if ( params.variant_qc ) {
        variant_qc = VARIANT_QC(
            record(
                variant_calls: variant_calls,
                fasta        : params.fasta
            )
        )
        bcftools_stats          = variant_qc.bcftools_stats
        vcftools_tstv_counts    = variant_qc.vcftools_tstv_counts
        vcftools_tstv_qual      = variant_qc.vcftools_tstv_qual
        vcftools_filter_summary = variant_qc.vcftools_filter_summary
        vcftools_relatedness2   = variant_qc.vcftools_relatedness2
        qc_multiqc_files        = variant_qc.multiqc_files
    }

    publish:
    genome_chunks           = splitgenome.map { out -> record(meta: out.meta, chunks: out.chunks, excluded: out.excluded) } // record(meta, chunks, excluded)
    variant_calls           = variant_calls                                                                                  // record(meta, vcf, index)
    mpileup                 = mpileup                                                                                        // record(meta, mpileup)
    bcftools_stats          = bcftools_stats
    vcftools_tstv_counts    = vcftools_tstv_counts
    vcftools_tstv_qual      = vcftools_tstv_qual
    vcftools_filter_summary = vcftools_filter_summary
    vcftools_relatedness2   = vcftools_relatedness2
    multiqc_files           = splitgenome.map { out -> out.summary }.mix(qc_multiqc_files)

}

output {
    genome_chunks          : Value<Record> { path 'genome_chunk_bed_files' }
    variant_calls          : Channel<Record> { path 'variant_calls' }
    mpileup                : Channel<Record> { path 'mpileup' }
    bcftools_stats         : Channel<Record> { path 'bcftools_stats' }
    vcftools_tstv_counts   : Channel<Record> { path 'vcftools' }
    vcftools_tstv_qual     : Channel<Record> { path 'vcftools' }
    vcftools_filter_summary: Channel<Record> { path 'vcftools' }
    vcftools_relatedness2  : Channel<Record> { path 'vcftools' }
    multiqc_files          : Channel<Path> { path 'multiqc_files' }
}

// Warn when the contigs left out by min_length cover more than 5% of the reference
def warnExcludedRegions(summary: Path, min_length: Integer) {
    def rows = summary.readLines().findAll { line -> line && !line.startsWith('#') }.collect { line -> line.tokenize('\t') }.toList()
    if ( rows.size() == 2 ) {
        def headers = rows[0].toList()
        def values  = rows[1].toList()
        def excluded_percent = values[headers.indexOf('Excluded %')]
        if ( excluded_percent.toDouble() > 5 ) {
            log.warn(
                "--min_length (${min_length} bp) excluded ${values[headers.indexOf('Regions excluded')]} reference regions " +
                "(${values[headers.indexOf('Bp excluded')]} bp, ${excluded_percent}% of the reference) from variant calling. " +
                "They are listed in genome_chunk_bed_files/excluded_regions.tsv."
            )
        }
    }
}
