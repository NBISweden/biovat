nextflow.enable.types = true

process SAMTOOLS_SORMADUP {
    tag "${id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/e9/e994bf4eb3731150511a14f5706b7bdfd64df1b6d40898fff334286c027e0859/data'
        : 'community.wave.seqera.io/library/htslib_samtools:1.24--d697cfb9dce007cd'}"

    ext [
        prefix: { output_prefix ?: "${id}" },
        args: { samtools_cat_args ?: '' },
        args2: { samtools_collate_args ?: '' },
        args3: { samtools_fixmate_args ?: '' },
        args4: { samtools_sort_args ?: '' },
        args5: { samtools_markdup_args ?: '' }
    ]

    input:
    record(
        id: String,
        meta: Record?,
        input: Path,
        fasta: Path?,
        fai: Path?,
        samtools_cat_args: String?,
        samtools_collate_args: String?,
        samtools_fixmate_args: String?,
        samtools_sort_args: String?,
        samtools_markdup_args: String?,
        output_prefix: String?
    )

    output:
    record(
        id: id,
        meta: meta,
        bam: file("*.bam", optional: true),
        cram: file("*.cram", optional: true),
        csi: file("*.csi", optional: true),
        crai: file("*.crai", optional: true),
        metrics: file("*.metrics")
    )

    topic:
    record(process: "${task.process}", tool: 'samtools', version: eval("samtools version | sed '1!d;s/.* //'")) >> 'versions'

    script:
    def extension = task.ext.args5.contains("--output-fmt sam")
        ? "sam"
        : task.ext.args5.contains("--output-fmt cram")
            ? "cram"
            : "bam"
    def reference = fasta ? "--reference ${fasta}" : ""
    """
    samtools cat \\
        ${task.ext.args} \\
        ${input}  \\
    | \\
    samtools collate \\
        ${task.ext.args2} \\
        -O \\
        -u \\
        -T ${task.ext.prefix}.collate \\
        --threads ${task.cpus} \\
        ${reference} \\
        - \\
    | \\
    samtools fixmate \\
        ${task.ext.args3} \\
        -m \\
        -u \\
        --threads ${task.cpus} \\
        - \\
        - \\
    | \\
    samtools sort \\
        ${task.ext.args4} \\
        -u \\
        -T ${task.ext.prefix}.sort \\
        --threads ${task.cpus} \\
        - \\
    | \\
    samtools markdup \\
        -T ${task.ext.prefix} \\
        -f ${task.ext.prefix}.metrics \\
        --threads ${task.cpus} \\
        ${reference} \\
        ${task.ext.args5} \\
        - \\
        ${task.ext.prefix}.${extension}
    """

    stub:
    def extension = task.ext.args5.contains("--output-fmt sam")
        ? "sam"
        : task.ext.args5.contains("--output-fmt cram")
            ? "cram"
            : "bam"
    def index = task.ext.args5.contains("--write-index")
        ? "touch ${task.ext.prefix}.${extension}.${extension == 'cram' ? 'crai' : 'csi'}"
        : ""
    """
    touch ${task.ext.prefix}.${extension}
    touch ${task.ext.prefix}.metrics
    ${index}
    """
}
