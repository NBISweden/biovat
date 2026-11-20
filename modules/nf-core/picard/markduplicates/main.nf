nextflow.enable.types = true

process PICARD_MARKDUPLICATES {
    tag "${id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/b4/b474c6f12c0502377b95062b75ef4b7778864b1353c7fc1d5a3b1f3b3017fd2e/data'
        : 'community.wave.seqera.io/library/picard:3.5.0--842d4c70c98af9b4'}"

    ext [
        prefix: { output_prefix ?: "${id}" },
        args: { picard_markduplicates_args ?: '' }
    ]

    input:
    record(
        id: String,
        meta: Record?,
        reads: Path,
        fasta: Path?,
        fai: Path?,
        picard_markduplicates_args: String?,
        output_prefix: String?
    )

    output:
    record(
        id: id,
        meta: meta,
        bam: file("*.bam", optional: true),
        bai: file("*.bai", optional: true),
        cram: file("*.cram", optional: true),
        metrics: file("*.metrics.txt")
    )

    topic:
    record(process: "${task.process}", tool: 'picard', version: eval("picard MarkDuplicates --version 2>&1 | sed -n 's/.*Version://p'")) >> 'versions'

    script:
    def suffix = reads.getExtension()
    def reference = fasta ? "--REFERENCE_SEQUENCE ${fasta}" : ""
    def avail_mem = 3072
    if (!task.memory) {
        log.info('[Picard MarkDuplicates] Available memory not known - defaulting to 3GB. Specify process memory requirements to change this.')
    }
    else {
        avail_mem = (task.memory.toMega() * 0.8).intValue()
    }

    if ("${reads}" == "${task.ext.prefix}.${suffix}") {
        error("Input and output names are the same, use \"task.ext.prefix\" to disambiguate!")
    }
    """
    picard \\
        -Xmx${avail_mem}M \\
        MarkDuplicates \\
        ${task.ext.args} \\
        --INPUT ${reads} \\
        --OUTPUT ${task.ext.prefix}.${suffix} \\
        ${reference} \\
        --METRICS_FILE ${task.ext.prefix}.metrics.txt
    """

    stub:
    def suffix = reads.getExtension()
    if ("${reads}" == "${task.ext.prefix}.${suffix}") {
        error("Input and output names are the same, use \"task.ext.prefix\" to disambiguate!")
    }
    """
    touch ${task.ext.prefix}.${suffix}
    touch ${task.ext.prefix}.${suffix}.bai
    touch ${task.ext.prefix}.metrics.txt
    """
}
