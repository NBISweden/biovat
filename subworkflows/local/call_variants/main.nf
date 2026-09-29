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
    ch_samplesheet
    ch_reference_and_fai
    dataset_name
    enable
    ch_multiqc_files

    main:
    // Split the reference genome into chunks of chromosomes for parallelization
    ch_genome_chunks = channel.empty()
    ch_fai = ch_reference_and_fai.map { meta, fasta, fai -> [meta, fai] }
    SPLITGENOME(ch_fai, chunk_size ?: '', min_length ?: '')
    ch_genome_chunks = SPLITGENOME.out.chunks

    // Group all samples into a single joint call
    ch_joint_alignments = ch_alignment_and_index
        .map { meta, alignment, index -> [dataset_name, meta.id, alignment, index] }
        .groupTuple()
        .map { group, samples, alignments, indexes ->
            [[id: group, samples: samples], alignments, indexes]
        }

    // Call variants with four alternative variant callers
    ch_variant_calls_indexed = channel.empty()
    ch_mpileup = channel.empty()

    if (variant_caller == 'bcftools') {
        // TODO: If ch_population_file is re-used in future modules, move the following code to PIPELINE_INITIALISATION
        ch_population_file = channel.value([])
        if (enable.group_samples) {
            ch_population_file = ch_samplesheet
                .map { meta, _reads -> "${meta.id}\t${meta.population}" }
                .unique()
                .collectFile(
                    name: 'sample_population.tsv',
                    newLine: true,
                    sort: true,
                    cache: true,
                )
        }

        ch_intervals = ch_genome_chunks.transpose()
            .map { _meta_ref, chunk_bed -> chunk_bed }

        ch_joint_alignments_per_chunk = ch_joint_alignments
            .combine(ch_intervals)
            .map { meta, alignments, indexes, chunk_bed ->
                [[id: "${meta.id}.${chunk_bed.baseName}", samples: meta.samples], alignments, indexes, chunk_bed]
            }

        BCFTOOLS_MPILEUP_MULTISAMPLE(
            ch_joint_alignments_per_chunk.map { meta, alignments, indexes, _chunk_bed -> [meta, alignments, indexes] },
            ch_reference_and_fai,
            ch_joint_alignments_per_chunk.map { _meta, _alignments, _indexes, chunk_bed -> chunk_bed },
            enable.save_mpileup,
            enable.group_samples,
            ch_population_file,
        )
        ch_variant_calls_indexed = BCFTOOLS_MPILEUP_MULTISAMPLE.out.vcf.join(BCFTOOLS_MPILEUP_MULTISAMPLE.out.index)
        ch_mpileup = BCFTOOLS_MPILEUP_MULTISAMPLE.out.mpileup

        // TODO: concatenate the genome chunks using BCFTOOLS_CONCAT
        // input channel: tuple val(meta), path(vcfs), path(tbi)
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
        VARIANT_QC(
            ch_variant_calls_indexed,
            ch_reference_and_fai,
        )
        ch_multiqc_files = ch_multiqc_files.mix(
            VARIANT_QC.out.bcftools_stats_output.map { _meta, file -> [file] },
            VARIANT_QC.out.vcftools_tstv_counts_output.map { _meta, file -> [file] },
            VARIANT_QC.out.vcftools_tstv_qual_output.map { _meta, file -> [file] },
            VARIANT_QC.out.vcftools_filter_summary_output.map { _meta, file -> [file] },
            VARIANT_QC.out.vcftools_relatedness2_output.map { _meta, file -> [file] },
        )
        outputs_bcftools_stats = VARIANT_QC.out.bcftools_stats_output
        outputs_vcftools_tstv_counts = VARIANT_QC.out.vcftools_tstv_counts_output
        outputs_vcftools_tstv_qual = VARIANT_QC.out.vcftools_tstv_qual_output
        outputs_vcftools_filter_summary = VARIANT_QC.out.vcftools_filter_summary_output
        outputs_vcftools_relatedness2 = VARIANT_QC.out.vcftools_relatedness2_output
    }

    emit:
    ch_variant_calls_indexed // channel: [ meta, *.vcf.gz ] and [ meta, *.tbi/csi ]
    ch_mpileup // channel: [ meta, *.mpileup.gz ], empty unless enable_save_mpileup
    ch_multiqc_files
    outputs_bcftools_stats
    outputs_vcftools_tstv_counts
    outputs_vcftools_tstv_qual
    outputs_vcftools_filter_summary
    outputs_vcftools_relatedness2
}
