nextflow.enable.types = true

process GATK4_CREATESEQUENCEDICTIONARY {
    tag "${id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/ce/ce8f4142326abbb74e28b97633a200b09439c54480803343b1cf13dc19e51ae5/data'
        : 'community.wave.seqera.io/library/gatk4-lite:4.7.0.0--79918b8b2632f4b1'}"

    ext [
        args: { gatk4_createsequencedictionary_args ?: '' }
    ]

    input:
    record(
        id: String,
        meta: Record?,
        fasta: Path,
        gatk4_createsequencedictionary_args: String?
    )

    output:
    record(
        id: id,
        meta: meta,
        dict: file('*.dict')
    )

    topic:
    record(process: "${task.process}", tool: 'gatk4', version: eval("gatk --version | sed -n '/GATK.*v/s/.*v//p'")) >> 'versions'

    script:
    def avail_mem = 6144
    if (!task.memory) {
        log.info('[GATK CreateSequenceDictionary] Available memory not known - defaulting to 6GB. Specify process memory requirements to change this.')
    }
    else {
        avail_mem = (task.memory.toMega() * 0.8).intValue()
    }
    """
    gatk --java-options "-Xmx${avail_mem}M -XX:-UsePerfData" \\
        CreateSequenceDictionary \\
        --REFERENCE ${fasta} \\
        --URI ${fasta} \\
        --TMP_DIR . \\
        ${task.ext.args}
    """

    stub:
    """
    touch ${fasta.baseName}.dict
    """
}
