nextflow.enable.types = true

process BCFTOOLS_STATS {
    tag "${id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/0b/0b4d52ca9a56d07be3f78a12af654e5116f5112908dba277e6796fd9dfb83fe5/data'
        : 'community.wave.seqera.io/library/bcftools_htslib:1.23.1--9f08ec665533d64a'}"

    ext [
        prefix: { output_prefix ?: "${id}" },
        args: { bcftools_stats_args ?: '' }
    ]

    input:
    record(
        id: String,
        meta: Record?,
        vcf: Path,
        tbi: Path?,
        regions: Path?,
        targets: Path?,
        samples: Path?,
        exons: Path?,
        fasta: Path?,
        bcftools_stats_args: String?,
        output_prefix: String?
    )

    output:
    record(
        id: id,
        meta: meta,
        stats: file("*stats.txt")
    )

    topic:
    record(process: "${task.process}", tool: 'bcftools', version: eval("bcftools --version | sed '1!d; s/^.*bcftools //'")) >> 'versions'

    script:
    def regions_file = regions ? "--regions-file ${regions}" : ""
    def targets_file = targets ? "--targets-file ${targets}" : ""
    def samples_file = samples ? "--samples-file ${samples}" : ""
    def reference_fasta = fasta ? "--fasta-ref ${fasta}" : ""
    def exons_file = exons ? "--exons ${exons}" : ""
    """
    bcftools stats \\
        ${task.ext.args} \\
        ${regions_file} \\
        ${targets_file} \\
        ${samples_file} \\
        ${reference_fasta} \\
        ${exons_file} \\
        ${vcf} > ${task.ext.prefix}.bcftools_stats.txt
    """

    stub:
    """
    touch ${task.ext.prefix}.bcftools_stats.txt
    """
}
