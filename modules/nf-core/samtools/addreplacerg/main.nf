nextflow.enable.types = true

process SAMTOOLS_ADDREPLACERG {
    tag "${id}"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/e9/e994bf4eb3731150511a14f5706b7bdfd64df1b6d40898fff334286c027e0859/data'
        : 'community.wave.seqera.io/library/htslib_samtools:1.24--d697cfb9dce007cd'}"

    ext [
        prefix: { output_prefix ?: "${id}" },
        args: { samtools_addreplacerg_args ?: '' }
    ]

    input:
    record(
        id: String,
        meta: Record?,
        input: Path,
        index: Path?,
        read_group: String?,
        fasta: Path?,
        fai: Path?,
        gzi: Path?,
        samtools_addreplacerg_args: String?,
        output_prefix: String?
    )

    output:
    record(
        id: id,
        meta: meta,
        bam: file("${task.ext.prefix}.bam", optional: true),
        cram: file("${task.ext.prefix}.cram", optional: true),
        sam: file("${task.ext.prefix}.sam", optional: true),
        index: file("${task.ext.prefix}.{bam,cram,sam}.{crai,csi,bai}", optional: true)
    )

    topic:
    record(process: "${task.process}", tool: 'samtools', version: eval("samtools version | sed '1!d;s/.* //'")) >> 'versions'

    script:
    def reference = fasta ? "--reference ${fasta}" : ''
    def read_group_arg = read_group ? "-r ${read_group}" : ''
    def file_type = task.ext.args =~ /--output-fmt\s+sam|-O\s+sam/
        ? "sam"
        : task.ext.args =~ /--output-fmt\s+bam|-O\s+bam/
            ? "bam"
            : task.ext.args =~ /--output-fmt\s+cram|-O\s+cram/
                ? "cram"
                : input.getExtension()
    if ("${input}" == "${task.ext.prefix}.${file_type}") {
        error("Input and output names are the same, use \"task.ext.prefix\" to disambiguate!")
    }
    """
    # Note: --threads value represents *additional* CPUs to allocate (total CPUs = 1 + --threads).
    samtools \\
        addreplacerg \\
        --threads ${task.cpus - 1} \\
        ${task.ext.args} \\
        ${read_group_arg} \\
        ${reference} \\
        -o ${task.ext.prefix}.${file_type} \\
        ${input}
    """

    stub:
    def file_type = input.getExtension()
    if ("${input}" == "${task.ext.prefix}.${file_type}") {
        error("Input and output names are the same, use \"task.ext.prefix\" to disambiguate!")
    }
    """
    touch ${task.ext.prefix}.${file_type}
    """
}
