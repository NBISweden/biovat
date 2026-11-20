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
    // Make list of old name and new name pairs to use for renaming in the bash while loop
    def indices = 0..<reads.size()
    def new_names = indices.collect { i ->
        reads.size() == 1 ? "${task.ext.prefix}.${reads[i].extension}" : "${task.ext.prefix}_${i + 1}.${reads[i].extension}"
    }
    def rename_to = indices.collect { i -> "${reads[i]} ${new_names.toList()[i]}" }.join(' ')
    def renamed_files = new_names.join(' ')

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
