nextflow.enable.types = true

process FASTQC {
    tag "${id}"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
?         'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/81/816bda6dd014e810753f642611232443ddeabb2b47f9681ad43f9044816f00ff/data'
:         'community.wave.seqera.io/library/fastqc:0.13.0--b342db7b694c9af4' }"

    ext [
        prefix: { output_prefix ?: "${id}" },
        args: { fastqc_args ?: '' }
    ]

    input:
    record(
        id: String,
        meta: Record?,
        reads: List<Path>,
        fastqc_args: String?,
        output_prefix: String?
    )

    stage:
    stageAs reads, '?/*'

    output:
    record(
        id: id,
        meta: meta,
        html: files("*.html"),
        zip: files("*.zip")
    )

    topic:
    record(process: "${task.process}", tool: 'fastqc', version: eval('fastqc --version | sed "/FastQC v/!d; s/.*v//"')) >> 'versions'

    script:
    // Link the reads as <prefix>.<ext>, or <prefix>_1.<ext>, <prefix>_2.<ext>, ... for several reads
    def links = reads.withIndex().collect { read, i ->
        def number = reads.size() == 1 ? '' : "_${i + 1}"
        record(old_name: read, new_name: "${task.ext.prefix}${number}.${read.extension}")
    }
    def rename_to = links.collect { link -> "${link.old_name} ${link.new_name}" }.join(' ')
    def renamed_files = links.collect { link -> link.new_name }.join(' ')

    // The total amount of allocated RAM by FastQC is equal to the number of threads defined (--threads) time the amount of RAM defined (--memory)
    // https://github.com/s-andrews/FastQC/blob/1faeea0412093224d7f6a07f777fad60a5650795/fastqc#L211-L222
    // Dividing the task.memory by task.cpus allows to stick to requested amount of RAM in the label
    def memory_in_mb = task.memory
        ? (task.memory.toUnit('MB') / task.cpus).intValue()
        : null
    // FastQC memory value allowed range (100 - 10000)
    def fastqc_memory = memory_in_mb > 10000 ? 10000 : (memory_in_mb < 100 ? 100 : memory_in_mb)
    def fastqc_memory_arg = fastqc_memory ? "--memory ${fastqc_memory}" : ''

    """
    printf "%s %s\\n" ${rename_to} | while read old_name new_name; do
        [ -f "\${new_name}" ] || ln -s \$old_name \$new_name
    done

    fastqc \\
        ${task.ext.args} \\
        --threads ${task.cpus} \\
        ${fastqc_memory_arg} \\
        ${renamed_files}
    """

    stub:
    """
    touch ${task.ext.prefix}.html
    touch ${task.ext.prefix}.zip
    """
}
