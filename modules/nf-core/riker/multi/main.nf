nextflow.enable.types = true

process RIKER_MULTI {
    tag "${id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/54/54c7820b49cfb5fada32c1825ac8a46c05d0085105c50055cbce4c37701ab95e/data' :
        'community.wave.seqera.io/library/riker:0.4.0--4e7eeb0beed906c0' }"

    ext [
        prefix: { output_prefix ?: "${id}" },
        args: { riker_multi_args ?: '' }
    ]

    input:
    record(
        id: String,
        meta: Record?,
        bam: Path,
        bai: Path,
        error_vcf: Path?,
        error_vcf_idx: Path?,
        error_intervals: Path?,
        gcbias_exclude_intervals: Path?,
        hybcap_baits: Path?,
        hybcap_targets: Path?,
        rna_gene_model: Path?,
        rna_ribosomal_intervals: Path?,
        wgs_intervals: Path?,
        fasta: Path?,
        fai: Path?,
        riker_multi_args: String?,
        output_prefix: String?
    )

    stage:
    stageAs hybcap_baits, 'baits/*'
    stageAs hybcap_targets, 'targets/*'

    output:
    record(
        id: id,
        meta: meta,
        alignment_metrics: file("*.alignment-metrics.txt", optional: true),
        base_dist: file("*.base-distribution-by-cycle.txt", optional: true),
        error_indel: file("*.error-indel.txt", optional: true),
        error_mismatch: file("*.error-mismatch.txt", optional: true),
        error_overlap: file("*.error-overlap.txt", optional: true),
        gcbias_detail: file("*.gcbias-detail.txt", optional: true),
        gcbias_summary: file("*.gcbias-summary.txt", optional: true),
        hybcap_metrics: file("*.hybcap-metrics.txt", optional: true),
        hybcap_per_base: files("*.hybcap-per-base.txt*", optional: true),
        hybcap_per_target: file("*.hybcap-per-target.txt", optional: true),
        isize_histogram: file("*.isize-histogram.txt", optional: true),
        isize_metrics: file("*.isize-metrics.txt", optional: true),
        mean_qual: file("*.mean-quality-by-cycle.txt", optional: true),
        pdf: files("*.pdf", optional: true),
        qual_dist: file("*.quality-score-distribution.txt", optional: true),
        rna_biotype: file("*.rna-biotype.txt", optional: true),
        rna_insert_size_histogram: file("*.rna-insert-size-histogram.txt", optional: true),
        rna_insert_size: file("*.rna-insert-size.txt", optional: true),
        rna_metrics: file("*.rna-metrics.txt", optional: true),
        wgs_coverage: file("*.wgs-coverage.txt", optional: true),
        wgs_metrics: file("*.wgs-metrics.txt", optional: true)
    )

    topic:
    record(process: "${task.process}", tool: 'riker', version: eval("riker --version 2>&1 | sed 's/riker //'")) >> 'versions'

    script:
    def reference_arg = fasta ? "--reference ${fasta}" : ''
    if ((hybcap_baits != null) != (hybcap_targets != null)) {
        error "RIKER_MULTI: both 'baits' and 'targets' must be provided together, or neither"
    }
    def error_vcf_arg = error_vcf && error_vcf_idx ? "--error::vcf ${error_vcf}" : ''
    def error_intervals_arg = error_intervals ? "--error::intervals ${error_intervals}" : ''
    def gcbias_exclude_intervals_arg = gcbias_exclude_intervals ? "--gcbias::exclude-intervals ${gcbias_exclude_intervals}" : ''
    def hybcap_opts = (hybcap_baits && hybcap_targets) ? "--hybcap::baits ${hybcap_baits} --hybcap::targets ${hybcap_targets}" : ''
    def rna_gene_model_arg = rna_gene_model ? "--rna::gene-model ${rna_gene_model}" : ''
    def rna_ribosomal_intervals_arg = rna_ribosomal_intervals ? "--rna::ribosomal-intervals ${rna_ribosomal_intervals}" : ''
    def wgs_intervals_arg = wgs_intervals ? "--wgs::intervals ${wgs_intervals}" : ''

    """
    riker multi \\
        -i ${bam} \\
        ${reference_arg} \\
        -o ${task.ext.prefix} \\
        --threads ${task.cpus} \\
        ${hybcap_opts} \\
        ${error_vcf_arg} \\
        ${error_intervals_arg} \\
        ${gcbias_exclude_intervals_arg} \\
        ${rna_gene_model_arg} \\
        ${rna_ribosomal_intervals_arg} \\
        ${wgs_intervals_arg} \\
        ${task.ext.args}
    """

    stub:
    """
    touch ${task.ext.prefix}.alignment-metrics.txt
    touch ${task.ext.prefix}.base-distribution-by-cycle.txt
    touch ${task.ext.prefix}.mean-quality-by-cycle.txt
    touch ${task.ext.prefix}.quality-score-distribution.txt
    touch ${task.ext.prefix}.error-mismatch.txt
    touch ${task.ext.prefix}.error-overlap.txt
    touch ${task.ext.prefix}.error-indel.txt
    touch ${task.ext.prefix}.gcbias-detail.txt
    touch ${task.ext.prefix}.gcbias-summary.txt
    touch ${task.ext.prefix}.hybcap-metrics.txt
    touch ${task.ext.prefix}.hybcap-per-target.txt
    touch ${task.ext.prefix}.hybcap-per-base.txt
    touch ${task.ext.prefix}.isize-metrics.txt
    touch ${task.ext.prefix}.isize-histogram.txt
    touch ${task.ext.prefix}.wgs-metrics.txt
    touch ${task.ext.prefix}.wgs-coverage.txt
    touch ${task.ext.prefix}.base-distribution-by-cycle.pdf
    touch ${task.ext.prefix}.gcbias-chart.pdf
    touch ${task.ext.prefix}.isize-histogram.pdf
    touch ${task.ext.prefix}.mean-quality-by-cycle.pdf
    touch ${task.ext.prefix}.quality-score-distribution.pdf
    touch ${task.ext.prefix}.wgs-coverage.pdf
    """
}
