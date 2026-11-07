nextflow.enable.types = true

process BCFTOOLS_CONCAT {
    tag "${id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/0b/0b4d52ca9a56d07be3f78a12af654e5116f5112908dba277e6796fd9dfb83fe5/data'
        : 'community.wave.seqera.io/library/bcftools_htslib:1.23.1--9f08ec665533d64a'}"

    ext [
        prefix: { output_prefix ?: "${id}" },
        args: { bcftools_concat_args ?: '' }
    ]

    input:
    record(
        id: String,
        meta: Record?,
        vcfs: List<Path>,
        tbi: Bag<Path>,
        bcftools_concat_args: String?,
        output_prefix: String?
    )

    output:
    record(
        id: id,
        meta: meta,
        vcf: file("${task.ext.prefix}.{vcf,vcf.gz,bcf,bcf.gz}"),
        index: file("${task.ext.prefix}.*.{tbi,csi}", optional: true)
    )

    topic:
    record(process: "${task.process}", tool: 'bcftools', version: eval("bcftools --version | sed '1!d; s/^.*bcftools //'")) >> 'versions'

    script:
    def tbi_names = tbi.collect { file -> file.name }
    def create_input_index = vcfs.collect { vcf -> tbi_names.contains(vcf.name + ".tbi") || tbi_names.contains(vcf.name + ".csi") ? "" : "tabix ${vcf}" }.join("\n    ")
    def extension = task.ext.args.contains("--output-type b") || task.ext.args.contains("-Ob")
        ? "bcf.gz"
        : task.ext.args.contains("--output-type u") || task.ext.args.contains("-Ou")
            ? "bcf"
            : task.ext.args.contains("--output-type z") || task.ext.args.contains("-Oz")
                ? "vcf.gz"
                : task.ext.args.contains("--output-type v") || task.ext.args.contains("-Ov")
                    ? "vcf"
                    : "vcf"
    def input = vcfs.toSorted { a, b -> a.name <=> b.name }.join(" ")
    """
    ${create_input_index}

    bcftools concat \\
        --output ${task.ext.prefix}.${extension} \\
        ${task.ext.args} \\
        --threads ${task.cpus} \\
        ${input}
    """

    stub:
    def extension = task.ext.args.contains("--output-type b") || task.ext.args.contains("-Ob")
        ? "bcf.gz"
        : task.ext.args.contains("--output-type u") || task.ext.args.contains("-Ou")
            ? "bcf"
            : task.ext.args.contains("--output-type z") || task.ext.args.contains("-Oz")
                ? "vcf.gz"
                : task.ext.args.contains("--output-type v") || task.ext.args.contains("-Ov")
                    ? "vcf"
                    : "vcf"
    def index_extension = task.ext.args.contains("--write-index=tbi") || task.ext.args.contains("-W=tbi")
        ? "tbi"
        : task.ext.args.contains("--write-index=csi") || task.ext.args.contains("-W=csi")
            ? "csi"
            : task.ext.args.contains("--write-index") || task.ext.args.contains("-W")
                ? "csi"
                : ""
    def create_cmd = extension.endsWith(".gz") ? "echo '' | gzip >" : "touch"
    def create_index = extension.endsWith(".gz") && (index_extension == "csi" || index_extension == "tbi") ? "touch ${task.ext.prefix}.${extension}.${index_extension}" : ""

    """
    ${create_cmd} ${task.ext.prefix}.${extension}
    ${create_index}
    """
}
