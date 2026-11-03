nextflow.enable.types = true

process PARABRICKS_FQ2BAM {
    tag "${id}"
    label 'process_high'
    label 'process_gpu'
    // needed by the module to run on a cluster because we need to copy the fasta reference, see https://github.com/nf-core/modules/issues/9230
    stageInMode 'copy'

    container "nvcr.io/nvidia/clara/clara-parabricks:4.7.1-1"

    ext [
        prefix: { output_prefix ?: "${id}" },
        args: { parabricks_fq2bam_args ?: '' }
    ]

    input:
    record(
        id: String,
        meta: Record?,
        single_end: Boolean,
        reads: List<Path>,
        fasta: Path,
        index: Path,
        intervals: Bag<Path>?,
        known_sites: Bag<Path>?,
        known_sites_index: Bag<Path>?,
        output_fmt: String,
        parabricks_fq2bam_args: String?,
        output_prefix: String?
    )

    output:
    record(
        id: id,
        meta: meta,
        bam: file("*.bam", optional: true),
        bai: file("*.bai", optional: true),
        cram: file("*.cram", optional: true),
        crai: file("*.crai", optional: true),
        bqsr_table: file("*.table", optional: true),
        qc_metrics: file("*_qc_metrics", optional: true),
        duplicate_metrics: file("*.duplicate-metrics.txt", optional: true),
        compatible_versions: file("compatible_versions.yml", optional: true)
    )

    topic:
    record(process: "${task.process}", tool: 'parabricks', version: eval("pbrun version | grep -m1 '^pbrun:' | sed 's/^pbrun:[[:space:]]*//'")) >> 'versions'

    script:
    // Exit if running this module with -profile conda / -profile mamba
    if (workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1) {
        error("Parabricks module does not support Conda. Please use Docker / Singularity / Podman instead.")
    }

    def in_fq_command = single_end ? "--in-se-fq ${reads.join(' ')}" : "--in-fq ${reads.join(' ')}"
    def extension = "${output_fmt}"

    def known_sites_command = known_sites ? known_sites.collect { knownSite -> "--knownSites ${knownSite}" }.join(' ') : ""
    def known_sites_output_cmd = known_sites ? "--out-recal-file ${task.ext.prefix}.table" : ""
    def intervals_command = intervals ? intervals.collect { interval -> "--interval-file ${interval}" }.join(' ') : ""

    def num_gpus = task.accelerator ? "--num-gpus ${task.accelerator.request}" : ''
    """
    INDEX=`find -L ./ -name "*.amb" | sed 's/\\.amb\$//'`
    cp ${fasta} \$INDEX

    pbrun \\
        fq2bam \\
        --ref \$INDEX \\
        ${in_fq_command} \\
        --out-bam ${task.ext.prefix}.${extension} \\
        ${known_sites_command} \\
        ${known_sites_output_cmd} \\
        ${intervals_command} \\
        ${num_gpus} \\
        --bwa-cpu-thread-pool ${task.cpus} \\
        --monitor-usage \\
        ${task.ext.args}
    """

    stub:
    // Exit if running this module with -profile conda / -profile mamba
    if (workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1) {
        error("Parabricks module does not support Conda. Please use Docker / Singularity / Podman instead.")
    }
    def extension = "${output_fmt}"
    def extension_index = "${output_fmt}" == "cram" ? "crai" : "bai"
    def known_sites_output = known_sites ? "touch ${task.ext.prefix}.table" : ""
    def qc_metrics_output = task.ext.args.contains("--out-qc-metrics-dir") ? "mkdir ${task.ext.prefix}_qc_metrics" : ""
    def duplicate_metrics_output = task.ext.args.contains("--out-duplicate-metrics") ? "touch ${task.ext.prefix}.duplicate-metrics.txt" : ""
    """
    touch ${task.ext.prefix}.${extension}
    touch ${task.ext.prefix}.${extension}.${extension_index}
    ${known_sites_output}
    ${qc_metrics_output}
    ${duplicate_metrics_output}

    # Capture once and build single-line compatible_with (spaces only, no tabs)
    pbrun_version_output=\$(pbrun fq2bam --version 2>&1)

    # Because of a space between BWA and mem in the version output this is handled different to the other modules
    compat_line=\$(echo "\$pbrun_version_output" | awk -F':' '
        /Compatible With:/ {on=1; next}
        /^---/ {on=0}
        on && /:/ {
            key=\$1; val=\$2
            gsub(/[ \\t]+/, " ", key); gsub(/^[ \\t]+|[ \\t]+\$/, "", key)
            gsub(/[ \\t]+/, " ", val); gsub(/^[ \\t]+|[ \\t]+\$/, "", val)
            a[++i]=key ": " val
        }
        END { for (j=1;j<=i;j++) printf "%s%s", (j>1?", ":""), a[j] }
    ')

    cat <<EOF > compatible_versions.yml
    "${task.process}":
    pbrun_version: \$(echo "\$pbrun_version_output" | awk '/^pbrun:/ {print \$2; exit}')
    compatible_with: "\$compat_line"
    EOF
    """
}
