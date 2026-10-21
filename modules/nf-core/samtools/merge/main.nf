nextflow.enable.types = true

process SAMTOOLS_MERGE {
    tag "${id}"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/e9/e994bf4eb3731150511a14f5706b7bdfd64df1b6d40898fff334286c027e0859/data'
        : 'community.wave.seqera.io/library/htslib_samtools:1.24--d697cfb9dce007cd'}"

    ext [
        prefix: { output_prefix ?: "${id}" },
        args: { samtools_merge_args ?: '' }
    ]

    input:
    record(
        id: String,
        meta: Record?,
        input_files: List<Path>,
        index_files: List<Path>,
        fasta: Path?,
        fai: Path?,
        gzi: Path?,
        index_format: String?,
        samtools_merge_args: String?,
        output_prefix: String?
    )

    stage:
    stageAs input_files, "?/*"
    stageAs index_files, "?/*"

    output:
    record(
        id: id,
        meta: meta,
        bam: file("${task.ext.prefix}.bam", optional: true),
        cram: file("${task.ext.prefix}.cram", optional: true),
        index: file("${task.ext.prefix}.*.{bai,crai,csi}", optional: true)
    )

    topic:
    record(process: "${task.process}", tool: 'samtools', version: eval("samtools version | sed '1!d;s/.* //'")) >> 'versions'

    script:
    def file_type = input_files[0].getExtension()
    def reference = fasta ? "--reference ${fasta}" : ""
    //setting default values
    def write_index = ""
    def output_file = "${task.ext.prefix}.${file_type}"
    // Update if index is requested
    if (index_format != '' && index_format) {
        if (!(index_format ==~ /bai|csi|crai/)) {
            error("Index format not one of bai, csi, crai.")
        }
        write_index = "--write-index"
        output_file = "${task.ext.prefix}.${file_type}##idx##${task.ext.prefix}.${file_type}.${index_format}"
    }
    """
    # Note: --threads value represents *additional* CPUs to allocate (total CPUs = 1 + --threads).
    samtools \\
        merge \\
        --threads ${task.cpus - 1} \\
        ${write_index} \\
        ${task.ext.args} \\
        ${reference} \\
        ${output_file} \\
        ${input_files.join(' ')}
    """

    stub:
    def file_type = input_files[0].getExtension()
    if (index_format) {
        if (!(index_format ==~ /bai|csi|crai/)) {
            error("Index format not one of bai, csi, crai.")
        }
    }
    def index = index_format ? "touch ${task.ext.prefix}.${file_type}.${index_format}" : ""
    """
    touch ${task.ext.prefix}.${file_type}
    ${index}
    """
}
