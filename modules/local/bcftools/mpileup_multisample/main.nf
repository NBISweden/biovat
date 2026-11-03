// Local module: joint multi-sample calling variant of nf-core/bcftools/mpileup
nextflow.enable.types = true

process BCFTOOLS_MPILEUP_MULTISAMPLE {
    tag "${id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/0b/0b4d52ca9a56d07be3f78a12af654e5116f5112908dba277e6796fd9dfb83fe5/data'
        : 'community.wave.seqera.io/library/bcftools_htslib:1.23.1--9f08ec665533d64a'}"

    ext [
        prefix: { output_prefix ?: "${id}" },
        args: { bcftools_mpileup_args ?: '' },
        args2: { bcftools_call_args ?: '' }
    ]

    input:
    record(
        id: String,
        meta: Record?,
        bams: List<Path>,
        indexes: List<Path>,
        intervals: Path,
        fasta: Path,
        fai: Path?,
        save_mpileup: Boolean,
        group_samples: Boolean,
        population_file: Path?,
        bcftools_mpileup_args: String?,
        bcftools_call_args: String?,
        output_prefix: String?
    )

    output:
    record(
        id: id,
        meta: meta,
        vcf: file("*.vcf.gz"),
        index: file("*.csi", optional: true),
        mpileup: file("*.mpileup.bcf", optional: true)
    )

    topic:
    record(process: "${task.process}", tool: 'bcftools', version: eval("bcftools --version | sed '1!d; s/^.*bcftools //'")) >> 'versions'

    script:
    def mpileup                = save_mpileup ? "| tee ${task.ext.prefix}.mpileup.u.bcf" : ""
    def compress_mpileup       = save_mpileup ? "bcftools view --output-type b --output ${task.ext.prefix}.mpileup.bcf ${task.ext.prefix}.mpileup.u.bcf && rm ${task.ext.prefix}.mpileup.u.bcf" : ""
    def group_samples_cmd      = group_samples ? "--group-samples ${population_file}" : ""
    """
    # Note: AD tag is a bcftools default, but we add it explicitly as a guard against future version changes
    bcftools \\
        mpileup \\
        --fasta-ref ${fasta} \\
        --output-type u \\
        --annotate FORMAT/DP,FORMAT/AD \\
        ${task.ext.args} \\
        ${bams.join(' ')} \\
        -R ${intervals} \\
        ${mpileup} \\
        | bcftools call \\
        --output-type z \\
        ${task.ext.args2} \\
        ${group_samples_cmd} \\
        --output ${task.ext.prefix}.vcf.gz

    ${compress_mpileup}

    bcftools index --csi -f ${task.ext.prefix}.vcf.gz
    """

    stub:
    """
    echo "" | gzip > ${task.ext.prefix}.vcf.gz
    touch ${task.ext.prefix}.vcf.gz.csi
    echo "" | gzip > ${task.ext.prefix}.mpileup.bcf
    """
}
