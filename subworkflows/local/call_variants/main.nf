include { SPLITGENOME                  } from '../../../modules/local/splitgenome/main'
include { BCFTOOLS_MPILEUP_MULTISAMPLE } from '../../../modules/local/bcftools/mpileup_multisample/main'
include { BCFTOOLS_CONCAT              } from '../../../modules/nf-core/bcftools/concat/main'
include { GATK4_HAPLOTYPECALLER        } from '../../../modules/nf-core/gatk4/haplotypecaller/main'
include { GATK4_GENOMICSDBIMPORT       } from '../../../modules/nf-core/gatk4/genomicsdbimport/main'
include { GATK4_GENOTYPEGVCFS          } from '../../../modules/nf-core/gatk4/genotypegvcfs/main'
include { VARIANT_QC                   } from '../variant_qc/main'

workflow CALL_VARIANTS {
    take:
    variant_caller         // string: variant caller to use
    chunk_size             // string: chunk size for splitting genome into chunks for parallelization
    min_length             // string: minimum contig length when splitting genome into chunks for parallelization
    ch_alignment_and_index
    ch_sample_metadata     // channel: sample metadata for population grouping during variant calling
    requires               // map: stage/tool gating flags
    ch_reference_and_fai
    ch_reference_dict      // channel: [ meta, dict ] sequence dictionary, [[], []] unless requires.dict
    dataset_name
    enable
    ch_multiqc_files

    main:
    // Every caller emits per-chunk calls as [ meta (id, group_id, samples, chunk), vcf, index ], gathered below
    ch_chunk_vcfs_indexed = channel.empty()
    ch_mpileup            = channel.empty()

    // Branch on platform to avoid calling mixed-platform samples together
    platform_alignments_for_calling = ch_alignment_and_index
        .branch { meta, _alignment, _index ->
            illumina: meta.pl == 'ILLUMINA'
            unsupported: true
        }

    // Only Illumina is currently called; warn once, listing every sample/platform left out
    platform_alignments_for_calling.unsupported
        .map { meta, _alignment, _index -> "${meta.id} (${meta.pl})" }
        .collect(sort: true)
        .subscribe { skipped ->
            log.warn(
                "Variant calling currently supports only ILLUMINA alignments. " +
                "These sample alignments are excluded from variant calling: ${skipped.join(', ')}"
            )
        }

    // Split the reference genome into chunks (BED intervals) for parallelization
    splitgenome_out  = SPLITGENOME(
        ch_reference_and_fai.map { meta, _fasta, fai -> [meta, fai] },
        chunk_size ?: '',
        min_length ?: ''
    )
    ch_bed_intervals = splitgenome_out.chunks
        .transpose()
        .map { _meta_ref, chunk_bed -> chunk_bed }
    ch_multiqc_files = ch_multiqc_files.mix(splitgenome_out.summary.map { _meta, file -> [file] })

    // Make contig exclusions visible on the console when they cover more than 5% of the reference
    splitgenome_out.summary.subscribe { _meta, summary ->
        def rows = summary.readLines().findAll { line -> line && !line.startsWith('#') }.collect { line -> line.tokenize('\t') }
        if (rows.size() == 2) {
            def stats = [rows[0], rows[1]].transpose().collectEntries { header, value -> [(header): value] }
            if (stats['Excluded %'].toDouble() > 5) {
                log.warn(
                    "--min_length (${min_length} bp) excluded ${stats['Regions excluded']} reference regions " +
                    "(${stats['Bp excluded']} bp, ${stats['Excluded %']}% of the reference) from variant calling. " +
                    "They are listed in genome_chunk_bed_files/excluded_regions.tsv."
                )
            }
        }
    }

    // Prepare population metadata file (used by bcftools mpileup --group-samples)
    ch_population_file = channel.value([])
    if (requires.group_samples) {
        ch_population_file = ch_sample_metadata
            .map { meta -> "${meta.id}\t${meta.population}" }
            .collectFile(
                name: 'sample_population.tsv',
                newLine: true,
                sort: true,
                cache: true,)
            .collect()
    }

    // bcftools: multi-sample joint calling
    if (variant_caller == 'bcftools_multisample') {
        // Group all samples
        ch_grouped_alignments = platform_alignments_for_calling.illumina
            .map { meta, alignment, index -> [dataset_name, meta.id, alignment, index] }
            .groupTuple()
            .map { group, samples, alignments, indexes ->
                // sort by sample id so VCF sample columns don't depend on channel arrival order
                def sorted = [samples, alignments, indexes].transpose().sort { row -> row[0] }
                [[id: group, samples: sorted.collect { row -> row[0] }], sorted.collect { row -> row[1] }, sorted.collect { row -> row[2] }]
            }
        // Combine group with BED intervals for region-specific parallel calling
        ch_alignments_for_bcftools_mpileup = ch_grouped_alignments
            .combine(ch_bed_intervals)
            .map { meta, alignments, indexes, chunk_bed ->
                [
                    [id: "${meta.id}.${chunk_bed.baseName}", group_id: meta.id, samples: meta.samples, chunk: chunk_bed.baseName],
                    alignments, indexes, chunk_bed
                ]
            }
        // Multi-sample variant calling
        bcftools_mpileup_multisample_out = BCFTOOLS_MPILEUP_MULTISAMPLE(
            ch_alignments_for_bcftools_mpileup,
            ch_reference_and_fai,
            enable.save_mpileup,
            requires.group_samples,
            ch_population_file,
        )
        ch_chunk_vcfs_indexed = bcftools_mpileup_multisample_out.vcf.join(bcftools_mpileup_multisample_out.index)
        ch_mpileup            = bcftools_mpileup_multisample_out.mpileup
    }

    // TODO: add bcftools mpileup/call per sample calling and merging/joint genotyping

    // GATK4: per-sample calling and joint genotyping
    if (variant_caller == 'gatk') {
        // Combine each sample with BED intervals for region-specific parallel calling
        ch_alignments_for_gatk4 = platform_alignments_for_calling.illumina
            .combine(ch_bed_intervals)
            .map { meta, alignments, indexes, chunk_bed ->
                [
                    meta + [chunk: chunk_bed.baseName],
                    alignments,
                    indexes,
                    chunk_bed,
                    []         // path: dragstr_model
                ]
            }
        // GATK4_HAPLOTYPECALLER in gvcf mode
        gatk4_haplotypecaller_out = GATK4_HAPLOTYPECALLER(
            ch_alignments_for_gatk4,
            ch_reference_and_fai.map { meta, fasta, _fai -> [meta, fasta] },
            ch_reference_and_fai.map { meta, _fasta, fai -> [meta, fai] },
            ch_reference_dict,
            [ [], [] ], // dbsnp
            [ [], [] ], // dbsbp_tbi index
        )
        // Consolidate GVCFs into one GenomicsDB workspace per chunk
        ch_bed_intervals_by_chunk = ch_bed_intervals.map { chunk_bed -> [chunk_bed.baseName, chunk_bed] }
        ch_gvcfs_for_genomicsdbimport = gatk4_haplotypecaller_out.vcf
            .join(gatk4_haplotypecaller_out.tbi, failOnMismatch: true, failOnDuplicate: true)
            .map { meta, gvcf, tbi -> [meta.chunk, meta.id, gvcf, tbi] }
            .groupTuple()
            .join(ch_bed_intervals_by_chunk, failOnMismatch: true, failOnDuplicate: true)
            .map { chunk, samples, gvcfs, tbis, chunk_bed ->
                // sort by sample id so the workspace sample order doesn't depend on channel arrival order
                def sorted = [samples, gvcfs, tbis].transpose().sort { row -> row[0] }
                [
                    [id: "${dataset_name}.${chunk}", group_id: dataset_name, samples: sorted.collect { row -> row[0] }, chunk: chunk],
                    sorted.collect { row -> row[1] },
                    sorted.collect { row -> row[2] },
                    chunk_bed,
                    [],        // val: interval_value (chunk_bed is used instead)
                    []         // path: wspace (only used when updating an existing workspace)
                ]
            }
        gatk4_genomicsdbimport_out = GATK4_GENOMICSDBIMPORT(
            ch_gvcfs_for_genomicsdbimport,
            false, // run_intlist: create a new workspace rather than list an existing one's intervals
            false, // run_updatewspace: create a new workspace rather than add samples to an existing one
            false, // input_map: pass GVCFs as --variant rather than a sample name map
        )
        // Joint genotyping per chunk, from the GenomicsDB workspace
        ch_genomicsdb_for_genotypegvcfs = gatk4_genomicsdbimport_out.genomicsdb
            .map { meta, workspace -> [meta.chunk, meta, workspace] }
            .join(ch_bed_intervals_by_chunk, failOnMismatch: true, failOnDuplicate: true)
            .map { _chunk, meta, workspace, chunk_bed ->
                [
                    meta,
                    workspace,
                    [],        // path: gvcf_index (not used with a GenomicsDB workspace)
                    chunk_bed,
                    []         // path: intervals_index (not needed for a BED file)
                ]
            }
        gatk4_genotypegvcfs_out = GATK4_GENOTYPEGVCFS(
            ch_genomicsdb_for_genotypegvcfs,
            ch_reference_and_fai.map { meta, fasta, _fai -> [meta, fasta] },
            ch_reference_and_fai.map { meta, _fasta, fai -> [meta, fai] },
            ch_reference_dict,
            [ [], [] ], // dbsnp
            [ [], [] ], // dbsnp_tbi index
        )
        ch_chunk_vcfs_indexed = gatk4_genotypegvcfs_out.vcf.join(gatk4_genotypegvcfs_out.tbi, failOnMismatch: true, failOnDuplicate: true)
    }

    // TODO: add parabricks haplotype caller and genotype gvcfs

    // TODO: convert *.vcf from parabricks to *vcf.gz and index

    // Concatenate the genome chunks of each group using BCFTOOLS_CONCAT
    ch_chunk_vcfs = ch_chunk_vcfs_indexed
        .map { meta, vcf, index ->
            // tag the joint VCF (and the variant QC named after it) with the caller, e.g. <dataset_name>.gatk
            def group_meta = [id: "${meta.group_id}.${variant_caller}", samples: meta.samples]
            // keep chunk id (e.g. "chunk_00002") for sorting later
            return [group_meta, meta.chunk, vcf, index]
        }
        .groupTuple()
        .map { meta, chunk_ids, vcfs, indexes ->
            // sort files by chunk_id to preserve genomic order
            def sorted = [chunk_ids, vcfs, indexes].transpose().sort { row -> row[0] }
            [meta, sorted.collect { row -> row[1] }, sorted.collect { row -> row[2] }]
        }
        // A single chunk skips concatenation; it is renamed to the group meta id when published (main.nf)
        .branch { meta, vcfs, indexes ->
            skip_concat: vcfs.size() == 1
                return [meta, vcfs[0], indexes[0]]
            for_concat: vcfs.size() > 1
        }
    bcftools_concat_out = BCFTOOLS_CONCAT(ch_chunk_vcfs.for_concat)
    // Join concatenated vcf files with their indexes, for variant QC and publishing.
    ch_variant_calls_indexed = bcftools_concat_out.vcf
        .join(bcftools_concat_out.index)
        .mix(ch_chunk_vcfs.skip_concat)

    // CALL_VARIANTS:VARIANT_QC
    outputs_bcftools_stats          = channel.empty()
    outputs_vcftools_tstv_counts    = channel.empty()
    outputs_vcftools_tstv_qual      = channel.empty()
    outputs_vcftools_filter_summary = channel.empty()
    outputs_vcftools_relatedness2   = channel.empty()
    if (enable.variant_qc) {
        variant_qc_out = VARIANT_QC(
            ch_variant_calls_indexed,
            ch_reference_and_fai,
        )
        ch_multiqc_files                = ch_multiqc_files.mix(variant_qc_out.multiqc_files)
        outputs_bcftools_stats          = variant_qc_out.outputs_bcftools_stats
        outputs_vcftools_tstv_counts    = variant_qc_out.outputs_vcftools_tstv_counts
        outputs_vcftools_tstv_qual      = variant_qc_out.outputs_vcftools_tstv_qual
        outputs_vcftools_filter_summary = variant_qc_out.outputs_vcftools_filter_summary
        outputs_vcftools_relatedness2   = variant_qc_out.outputs_vcftools_relatedness2
    }

    emit:
    ch_genome_chunks         = splitgenome_out.chunks.join(splitgenome_out.excluded) // channel: [ meta, chunk_*.bed, excluded_regions.tsv ]
    ch_variant_calls_indexed // channel: [ meta, *.vcf.gz ] and [ meta, *.tbi/csi ]
    ch_mpileup               // channel: [ meta, *.mpileup.gz ], empty unless enable_save_mpileup
    ch_multiqc_files
    outputs_bcftools_stats
    outputs_vcftools_tstv_counts
    outputs_vcftools_tstv_qual
    outputs_vcftools_filter_summary
    outputs_vcftools_relatedness2
}
