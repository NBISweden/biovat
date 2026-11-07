nextflow.enable.types = true

process SAMTOOLS_SORT {
    tag "${id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/e9/e994bf4eb3731150511a14f5706b7bdfd64df1b6d40898fff334286c027e0859/data'
        : 'community.wave.seqera.io/library/htslib_samtools:1.24--d697cfb9dce007cd'}"

    ext [
        prefix: { output_prefix ?: "${id}" },
        args: { samtools_sort_args ?: '' }
    ]

    input:
    record(
        id: String,
        meta: Record?,
        bam: List<Path>,
        fasta: Path?,
        fai: Path?,
        index_format: String?,
        samtools_sort_args: String?,
        output_prefix: String?
    )

    stage:
    stageAs bam, "?/*"

    output:
    record(
        id: id,
        meta: meta,
        bam: file("${task.ext.prefix}.bam", optional: true),
        cram: file("${task.ext.prefix}.cram", optional: true),
        sam: file("${task.ext.prefix}.sam", optional: true),
        index: file("${task.ext.prefix}.*.{crai,csi,bai}", optional: true)
    )

    topic:
    record(process: "${task.process}", tool: 'samtools', version: eval("samtools version | sed '1!d;s/.* //'")) >> 'versions'

    script:
    def extension = task.ext.args.contains("--output-fmt sam")
        ? "sam"
        : task.ext.args.contains("--output-fmt cram")
            ? "cram"
            : "bam"
    def reference = fasta ? "--reference ${fasta}" : ""
    //setting default values
    def write_index = ""
    def output_file = "${task.ext.prefix}.${extension}"
    // Update if index is requested
    if (index_format != '' && index_format) {
        write_index = "--write-index"
        output_file = "${task.ext.prefix}.${extension}##idx##${task.ext.prefix}.${extension}.${index_format}"
    }
    def is_sam = bam[0].name.endsWith('.sam')
    if (index_format) {
        if (!(index_format ==~ /bai|csi|crai/)) {
            error("Index format not one of bai, csi, crai.")
        }
        else if (extension == "sam") {
            error("Indexing not compatible with SAM output")
        }
    }
    if ("${bam.join(' ')}" == "${task.ext.prefix}.bam") {
        error("Input and output names are the same, use \"task.ext.prefix\" to disambiguate!")
    }
    def input_source = is_sam ? "${bam.join(' ')}" : "-"
    def pre_command = is_sam ? "" : "samtools cat ${bam.join(' ')} | "
    """
    ${pre_command}samtools sort \\
        ${task.ext.args} \\
        -T ${task.ext.prefix} \\
        --threads ${task.cpus} \\
        ${reference} \\
        -o ${output_file} \\
        ${write_index} \\
        ${input_source}
    """

    stub:
    def extension = task.ext.args.contains("--output-fmt sam")
        ? "sam"
        : task.ext.args.contains("--output-fmt cram")
            ? "cram"
            : "bam"
    if (index_format) {
        if (!(index_format ==~ /bai|csi|crai/)) {
            error("Index format not one of bai, csi, crai.")
        }
        else if (extension == "sam") {
            error("Indexing not compatible with SAM output")
        }
    }
    def index = index_format ? "touch ${task.ext.prefix}.${extension}.${index_format}" : ""
    """
    touch ${task.ext.prefix}.${extension}
    ${index}
    """
}
