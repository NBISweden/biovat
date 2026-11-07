nextflow.enable.types = true

process BWAMEM3_MEM {
    tag "${id}"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/86/86147f304683f83e8c20d9cf8aebae945f7751402d84553efd735a4f5edfd9e6/data'
        : 'community.wave.seqera.io/library/bwa-mem3_findutils_htslib_samtools:06f7d72b721717bd'}"

    ext [
        prefix: { output_prefix ?: "${id}" },
        args: { bwamem3_mem_args ?: '' },
        args2: { samtools_args ?: '' }
    ]

    input:
    record(
        id: String,
        meta: Record?,
        reads: List<Path>,
        index: Path,
        fasta: Path?,
        sort_bam: Boolean,
        bwamem3_mem_args: String?,
        samtools_args: String?, // samtools sort (sort_bam) or samtools view arguments
        output_prefix: String?
    )

    output:
    record(
        id: id,
        meta: meta,
        aligned: file("*.{sam,bam,cram}"),
        index: file("*.{bai,csi,crai}", optional: true)
    )

    topic:
    record(process: "${task.process}", tool: 'bwamem3', version: eval("bwa-mem3 version | sed -nE '1 s/^([0-9]+(\\.[0-9]+)+).*/\\1/p'")) >> 'versions'
    record(process: "${task.process}", tool: 'samtools', version: eval("samtools version | sed '1!d;s/.* //'")) >> 'versions'

    script:
    def samtools_command = sort_bam ? 'sort' : 'view'

    def args2_tokens = task.ext.args2.tokenize()
    def format_index = args2_tokens.indexOf('--output-fmt') >= 0 ? args2_tokens.indexOf('--output-fmt') : args2_tokens.indexOf('-O')
    def extension = format_index >= 0 && format_index + 1 < args2_tokens.size() ? args2_tokens[format_index + 1].toLowerCase() : "bam"
    def reference = fasta && extension == "cram" ? "--reference ${fasta}" : ""
    if (!fasta && extension == "cram") {
        error("Fasta reference is required for CRAM output")
    }
    """
    INDEX=`find -L ./ -name "*.amb" | sed 's/\\.amb\$//'`

    bwa-mem3 \\
        mem \\
        ${task.ext.args} \\
        -t ${task.cpus} \\
        \$INDEX \\
        ${reads.join(' ')} \\
        | samtools ${samtools_command} ${task.ext.args2} -@ ${task.cpus} ${reference} -o ${task.ext.prefix}.${extension} -
    """

    stub:
    def args2_tokens = task.ext.args2.tokenize()
    def format_index = args2_tokens.indexOf('--output-fmt') >= 0 ? args2_tokens.indexOf('--output-fmt') : args2_tokens.indexOf('-O')
    def extension = format_index >= 0 && format_index + 1 < args2_tokens.size() ? args2_tokens[format_index + 1].toLowerCase() : "bam"
    if (!fasta && extension == "cram") {
        error("Fasta reference is required for CRAM output")
    }

    def create_index = ""
    if (extension == "cram") {
        create_index = "touch ${task.ext.prefix}.crai"
    }
    else if (extension == "bam") {
        create_index = "touch ${task.ext.prefix}.csi"
    }
    """
    touch ${task.ext.prefix}.${extension}
    ${create_index}
    """
}
