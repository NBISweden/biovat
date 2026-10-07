process SPLITGENOME {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'oras://community.wave.seqera.io/library/python:3.14.7--19b091bddc2db8c8'
        : 'community.wave.seqera.io/library/python:3.14.7--629fbce4f44dac86'}"

    input:
    tuple val(meta), path(fai)
    val chunk_size
    val min_length

    output:
    tuple val(meta), path("chunk_*.bed"), emit: chunks
    tuple val("${task.process}"), val('python'), eval("python --version | sed '1!d;s/.* //'"), topic: versions, emit: versions_python

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def chunk_size_cmd = chunk_size ? "--chunk_size ${chunk_size}" : ""
    def min_length_cmd = min_length ? "--min_length ${min_length}" : ""
    """
    split_genome_chunks.py \\
        --input ${fai} \\
        ${chunk_size_cmd} \\
        ${min_length_cmd} \\
        ${args}

    """

    stub:
    """
    touch chunk_00001.bed
    """
}
