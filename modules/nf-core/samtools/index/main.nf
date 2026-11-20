nextflow.enable.types = true

process SAMTOOLS_INDEX {
    tag "${id}"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/e9/e994bf4eb3731150511a14f5706b7bdfd64df1b6d40898fff334286c027e0859/data'
        : 'community.wave.seqera.io/library/htslib_samtools:1.24--d697cfb9dce007cd'}"

    ext [
        args: { samtools_index_args ?: '' }
    ]

    input:
    record(
        id: String,
        meta: Record?,
        input: Path,
        samtools_index_args: String?
    )

    output:
    record(
        id: id,
        meta: meta,
        index: file("*.{bai,csi,crai}")
    )

    topic:
    record(process: "${task.process}", tool: 'samtools', version: eval("samtools version | sed '1!d;s/.* //'")) >> 'versions'

    script:
    """
    samtools \\
        index \\
        -@ ${task.cpus} \\
        ${task.ext.args} \\
        ${input}
    """

    stub:
    def extension = input.getExtension() == 'cram'
        ? "crai"
        : task.ext.args.contains("-c") ? "csi" : "bai"
    """
    touch ${input}.${extension}
    """
}
