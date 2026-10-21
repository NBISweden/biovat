nextflow.enable.types = true

process BWAMEM3_INDEX {
    tag "${id}"
    // NOTE bwa-mem3 builds an FM-index with libsais; peak memory scales with the reference size.
    memory 280.MB * Math.ceil(fasta.size() / 10000000) * task.attempt

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/09/09c0e84ac22ba722bae6f75c5c450d72dfdc06e7224ad2c0bd042849632ca70e/data'
        : 'community.wave.seqera.io/library/bwa-mem3:0.8.0--a430e1e1df49a92e'}"

    ext [
        prefix: { output_prefix ?: "${fasta}" },
        args: { bwamem3_index_args ?: '' }
    ]

    input:
    record(
        id: String,
        meta: Record?,
        fasta: Path,
        bwamem3_index_args: String?,
        output_prefix: String?
    )

    output:
    record(
        id: id,
        meta: meta,
        index: file("bwamem3")
    )

    topic:
    record(process: "${task.process}", tool: 'bwamem3', version: eval("bwa-mem3 version | sed -nE '1 s/^([0-9]+(\\.[0-9]+)+).*/\\1/p'")) >> 'versions'

    script:
    """
    mkdir bwamem3
    bwa-mem3 \\
        index \\
        ${task.ext.args} \\
        -t ${task.cpus} \\
        -p bwamem3/${task.ext.prefix} \\
        $fasta
    """

    stub:
    """
    mkdir bwamem3
    touch bwamem3/${task.ext.prefix}.0123
    touch bwamem3/${task.ext.prefix}.amb
    touch bwamem3/${task.ext.prefix}.ann
    touch bwamem3/${task.ext.prefix}.bwt.2bit.64
    touch bwamem3/${task.ext.prefix}.pac
    """
}
