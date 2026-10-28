nextflow.enable.types = true

process SPLITGENOME {
    tag "${id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'oras://community.wave.seqera.io/library/python:3.14.7--19b091bddc2db8c8'
        : 'community.wave.seqera.io/library/python:3.14.7--629fbce4f44dac86'}"

    ext [
        args: { splitgenome_args ?: '' }
    ]

    input:
    record(
        id: String,
        meta: Record?,
        fai: Path,
        chunk_size: Integer?,
        min_length: Integer?,
        splitgenome_args: String?
    )

    stage:
    stageAs file("${moduleDir}/bin/split_genome_chunks.py"), '*'

    output:
    record(
        id: id,
        meta: meta,
        chunks: files("chunk_*.bed"),
        excluded: file("excluded_regions.tsv"),
        summary: file("genome_chunking_mqc.tsv")
    )

    topic:
    record(process: "${task.process}", tool: 'python', version: eval("python --version | sed '1!d;s/.* //'")) >> 'versions'

    script:
    def chunk_size_cmd = chunk_size ? "--chunk_size ${chunk_size}" : ""
    def min_length_cmd = min_length ? "--min_length ${min_length}" : ""
    """
    ./split_genome_chunks.py \\
        --input ${fai} \\
        ${chunk_size_cmd} \\
        ${min_length_cmd} \\
        ${task.ext.args}
    """

    stub:
    """
    touch chunk_00001.bed
    touch excluded_regions.tsv
    touch genome_chunking_mqc.tsv
    """
}
