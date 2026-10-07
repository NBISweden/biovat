//
// Variant calling subworkflow
//

include { SPLITGENOME                  } from '../../../modules/local/splitgenome/main'
include { BCFTOOLS_MPILEUP_MULTISAMPLE } from '../../../modules/local/bcftools/mpileup_multisample/main'
include { BCFTOOLS_CONCAT              } from '../../../modules/nf-core/bcftools/concat/main'
include { VARIANT_QC                   } from '../variant_qc/main'

workflow CALL_VARIANTS {
    take:
    variant_caller
    chunk_size
    min_length
    ch_alignment_and_index
    ch_sample_metadata
    ch_reference_and_fai
    dataset_name
    enable
    ch_multiqc_files

    main:
    // Split the reference genome into chunks of chromosomes for parallelization
    ch_fai           = ch_reference_and_fai.map { meta, _fasta, fai -> [meta, fai] }
    splitgenome_out  = SPLITGENOME(ch_fai, chunk_size ?: '', min_length ?: '')
    ch_genome_chunks = splitgenome_out.chunks

    // Call variants with four alternative variant callers
    ch_variant_calls_indexed = channel.empty()
    ch_mpileup               = channel.empty()

    if (variant_caller == 'bcftools_multisample') {
        // Provide the option to pass population information to bcftools call (-G)
        ch_population_file = channel.value([])
        if (enable.group_samples) {
            ch_population_file = ch_sample_metadata
                .map { meta -> "${meta.id}\t${meta.population}" }
                .collectFile(
                    name: 'sample_population.tsv',
                    newLine: true,
                    sort: true,
                    cache: true,)
                .collect()
        }

        // Group all samples into a single joint call
        ch_joint_alignments = ch_alignment_and_index
            .map { meta, alignment, index -> [dataset_name, meta.id, alignment, index] }
            .groupTuple()
            .map { group, samples, alignments, indexes ->
                // sort by sample id so VCF sample columns don't depend on channel arrival order
                def sorted = [samples, alignments, indexes].transpose().sort { row -> row[0] }
                [[id: group, samples: sorted.collect { row -> row[0] }], sorted.collect { row -> row[1] }, sorted.collect { row -> row[2] }]
            }

        // Split into genome chunks for parallelization
        ch_intervals = ch_genome_chunks
            .transpose()
            .map { _meta_ref, chunk_bed -> chunk_bed }

        ch_joint_alignments_per_chunk = ch_joint_alignments
            .combine(ch_intervals)
            .map { meta, alignments, indexes, chunk_bed ->
                [
                    [id: "${meta.id}.${chunk_bed.baseName}", group_id: meta.id, samples: meta.samples, chunk: chunk_bed.baseName],
                    alignments, indexes, chunk_bed
                ]
            }

        // Multi-sample variant calling
        bcftools_mpileup_multisample_out = BCFTOOLS_MPILEUP_MULTISAMPLE(
            ch_joint_alignments_per_chunk,
            ch_reference_and_fai,
            enable.save_mpileup,
            enable.group_samples,
            ch_population_file,
        )
        ch_chunk_variant_calls_indexed = bcftools_mpileup_multisample_out.vcf.join(bcftools_mpileup_multisample_out.index)
        ch_mpileup = bcftools_mpileup_multisample_out.mpileup

        // Concatenate the genome chunks using BCFTOOLS_CONCAT
        ch_variant_calls = ch_chunk_variant_calls_indexed
            .map { meta, vcf, index ->
                def group_meta = [id: meta.group_id, samples: meta.samples]
                // keep chunk id (e.g. "chunk_00002") for sorting later
                    return [group_meta, meta.chunk, vcf, index]
            }
            .groupTuple()
            .map { meta, chunk_ids, vcfs, indexes ->
                // sort files by chunk_id to preserve genomic order
                def order = chunk_ids
                    .withIndex()
                    .sort { a, b -> a[0] <=> b[0] }
                    .collect { pair -> pair[1] }
                def sorted_vcfs = order.collect { idx -> vcfs[idx] }
                def sorted_indexes = order.collect { idx -> indexes[idx] }
                    return [meta, sorted_vcfs, sorted_indexes]
            }
            .branch { meta, vcfs, indexes ->
                skip_concat: vcfs.size() == 1
                    return [meta, vcfs[0], indexes[0]]
                for_concat: vcfs.size() > 1
            }

        bcftools_concat_out = BCFTOOLS_CONCAT(ch_variant_calls.for_concat)
        // Join concatenated vcf files with their indexes, for variant QC and publishing.
        ch_variant_calls_indexed = bcftools_concat_out.vcf
            .join(bcftools_concat_out.index)
            .mix(ch_variant_calls.skip_concat)
    }

    // TODO: add bcftools mpileup/call per sample calling and merging/joint genotyping

    // TODO: add GATK4 haplotype caller and genotype gvcfs

    // TODO: add parabricks haplotype caller and genotype gvcfs

    // TODO: convert *.vcf from parabricks to *vcf.gz and index

    // CALL_VARIANTS:VARIANT_QC
    outputs_bcftools_stats = channel.empty()
    outputs_vcftools_tstv_counts = channel.empty()
    outputs_vcftools_tstv_qual = channel.empty()
    outputs_vcftools_filter_summary = channel.empty()
    outputs_vcftools_relatedness2 = channel.empty()
    if (enable.variant_qc) {
        variant_qc_out = VARIANT_QC(
            ch_variant_calls_indexed,
            ch_reference_and_fai,
        )
        ch_multiqc_files = ch_multiqc_files.mix(
            variant_qc_out.bcftools_stats_output.map { _meta, file -> [file] },
            variant_qc_out.vcftools_tstv_counts_output.map { _meta, file -> [file] },
            variant_qc_out.vcftools_tstv_qual_output.map { _meta, file -> [file] },
            variant_qc_out.vcftools_filter_summary_output.map { _meta, file -> [file] },
            variant_qc_out.vcftools_relatedness2_output.map { _meta, file -> [file] },
        )
        outputs_bcftools_stats = variant_qc_out.bcftools_stats_output
        outputs_vcftools_tstv_counts = variant_qc_out.vcftools_tstv_counts_output
        outputs_vcftools_tstv_qual = variant_qc_out.vcftools_tstv_qual_output
        outputs_vcftools_filter_summary = variant_qc_out.vcftools_filter_summary_output
        outputs_vcftools_relatedness2 = variant_qc_out.vcftools_relatedness2_output
    }

    emit:
    ch_genome_chunks
    ch_variant_calls_indexed // channel: [ meta, *.vcf.gz ] and [ meta, *.tbi/csi ]
    ch_mpileup // channel: [ meta, *.mpileup.gz ], empty unless enable_save_mpileup
    ch_multiqc_files
    outputs_bcftools_stats
    outputs_vcftools_tstv_counts
    outputs_vcftools_tstv_qual
    outputs_vcftools_filter_summary
    outputs_vcftools_relatedness2
}
