nextflow.enable.types = true

process BWA_INDEX {
    tag "${id}"
    // NOTE requires 5.37N memory where N is the size of the database
    // source: https://bio-bwa.sourceforge.net/bwa.shtml#8
    memory 7.B * fasta.size()

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/d7/d7e24dc1e4d93ca4d3a76a78d4c834a7be3985b0e1e56fddd61662e047863a8a/data' :
        'community.wave.seqera.io/library/bwa_htslib_samtools:83b50ff84ead50d0' }"

    ext [
        prefix: { output_prefix ?: "${fasta.baseName}" },
        args: { bwa_index_args ?: '' }
    ]

    input:
    record(
        id: String,
        meta: Record?,
        fasta: Path,
        bwa_index_args: String?,
        output_prefix: String?
    )

    output:
    record(
        id: id,
        meta: meta,
        index: file("bwa")
    )

    topic:
    record(process: "${task.process}", tool: 'bwa', version: eval('bwa 2>&1 | sed -n "s/^Version: //p"')) >> 'versions'

    script:
    """
    mkdir bwa
    bwa \\
        index \\
        ${task.ext.args} \\
        -p bwa/${task.ext.prefix} \\
        $fasta
    """

    stub:
    """
    mkdir bwa
    touch bwa/${task.ext.prefix}.amb
    touch bwa/${task.ext.prefix}.ann
    touch bwa/${task.ext.prefix}.bwt
    touch bwa/${task.ext.prefix}.pac
    touch bwa/${task.ext.prefix}.sa
    """
}
