nextflow.enable.types = true

process FASTP {
    tag "${id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
?         'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/d0/d013aad5427d824afe472e6607ea47685ff0181f1fb09e52a179e0ec39e43e88/data'
:         'community.wave.seqera.io/library/fastp:1.3.6--4df8d6c11b471bde' }"

    ext [
        prefix: { output_prefix ?: "${id}" },
        args: { fastp_args ?: '' }
    ]

    input:
    record(
        id: String,
        meta: Record?,
        reads: List<Path>,
        single_end: Boolean, // single-end reads (one file) or paired-end reads (two files). An interleaved file is paired-end
        adapter_fasta: Path?,
        discard_trimmed_pass: Boolean,
        save_trimmed_fail: Boolean,
        save_merged: Boolean,
        fastp_args: String?,
        output_prefix: String?
    )

    output:
    record(
        id: id,
        meta: meta,
        reads: files('*.fastp.fastq.gz', optional: true),
        json: file('*.json'),
        html: file('*.html'),
        log: file('*.log'),
        reads_fail: files('*.fail.fastq.gz', optional: true),
        reads_merged: file('*.merged.fastq.gz', optional: true)
    )

    topic:
    record(process: "${task.process}", tool: 'fastp', version: eval('fastp --version 2>&1 | sed -e "s/fastp //g"')) >> 'versions'

    script:
    def adapter_list = adapter_fasta ? "--adapter_fasta ${adapter_fasta}" : ""
    def fail_fastq = save_trimmed_fail && single_end ? "--failed_out ${task.ext.prefix}.fail.fastq.gz" : save_trimmed_fail && !single_end ? "--failed_out ${task.ext.prefix}.paired.fail.fastq.gz --unpaired1 ${task.ext.prefix}_R1.fail.fastq.gz --unpaired2 ${task.ext.prefix}_R2.fail.fastq.gz" : ''
    def out_fq1 = discard_trimmed_pass ? '' : ( single_end ? "--out1 ${task.ext.prefix}.fastp.fastq.gz" : "--out1 ${task.ext.prefix}_R1.fastp.fastq.gz" )
    def out_fq2 = discard_trimmed_pass ? '' : "--out2 ${task.ext.prefix}_R2.fastp.fastq.gz"
    // Added soft-links to original fastqs for consistent naming in MultiQC
    // Use single ended for interleaved. Add --interleaved_in in config.
    if ( task.ext.args.contains('--interleaved_in') ) {
        """
        [ ! -f  ${task.ext.prefix}.fastq.gz ] && ln -sf ${reads[0]} ${task.ext.prefix}.fastq.gz

        fastp \\
            --stdout \\
            --in1 ${task.ext.prefix}.fastq.gz \\
            --thread $task.cpus \\
            --json ${task.ext.prefix}.fastp.json \\
            --html ${task.ext.prefix}.fastp.html \\
            $adapter_list \\
            $fail_fastq \\
            ${task.ext.args} \\
            2>| >(tee ${task.ext.prefix}.fastp.log >&2) \\
        | gzip -c > ${task.ext.prefix}.fastp.fastq.gz
        """
    } else if (single_end) {
        """
        [ ! -f  ${task.ext.prefix}.fastq.gz ] && ln -sf ${reads[0]} ${task.ext.prefix}.fastq.gz

        fastp \\
            --in1 ${task.ext.prefix}.fastq.gz \\
            $out_fq1 \\
            --thread $task.cpus \\
            --json ${task.ext.prefix}.fastp.json \\
            --html ${task.ext.prefix}.fastp.html \\
            $adapter_list \\
            $fail_fastq \\
            ${task.ext.args} \\
            2>| >(tee ${task.ext.prefix}.fastp.log >&2)
        """
    } else {
        def merge_fastq = save_merged ? "-m --merged_out ${task.ext.prefix}.merged.fastq.gz" : ''
        """
        [ ! -f  ${task.ext.prefix}_R1.fastq.gz ] && ln -sf ${reads[0]} ${task.ext.prefix}_R1.fastq.gz
        [ ! -f  ${task.ext.prefix}_R2.fastq.gz ] && ln -sf ${reads[1]} ${task.ext.prefix}_R2.fastq.gz
        fastp \\
            --in1 ${task.ext.prefix}_R1.fastq.gz \\
            --in2 ${task.ext.prefix}_R2.fastq.gz \\
            $out_fq1 \\
            $out_fq2 \\
            --json ${task.ext.prefix}.fastp.json \\
            --html ${task.ext.prefix}.fastp.html \\
            $adapter_list \\
            $fail_fastq \\
            $merge_fastq \\
            --thread $task.cpus \\
            --detect_adapter_for_pe \\
            ${task.ext.args} \\
            2>| >(tee ${task.ext.prefix}.fastp.log >&2)
        """
    }

    stub:
    def is_single_output    = task.ext.args.contains('--interleaved_in') || single_end
    def touch_reads         = (discard_trimmed_pass) ? "" : (is_single_output) ? "echo '' | gzip > ${task.ext.prefix}.fastp.fastq.gz" : "echo '' | gzip > ${task.ext.prefix}_R1.fastp.fastq.gz ; echo '' | gzip > ${task.ext.prefix}_R2.fastp.fastq.gz"
    def touch_merged        = (!is_single_output && save_merged) ? "echo '' | gzip >  ${task.ext.prefix}.merged.fastq.gz" : ""
    def touch_fail_fastq    = (!save_trimmed_fail) ? "" : single_end ? "echo '' | gzip > ${task.ext.prefix}.fail.fastq.gz" : "echo '' | gzip > ${task.ext.prefix}.paired.fail.fastq.gz ; echo '' | gzip > ${task.ext.prefix}_R1.fail.fastq.gz ; echo '' | gzip > ${task.ext.prefix}_R2.fail.fastq.gz"
    """
    $touch_reads
    $touch_fail_fastq
    $touch_merged
    touch "${task.ext.prefix}.fastp.json"
    touch "${task.ext.prefix}.fastp.html"
    touch "${task.ext.prefix}.fastp.log"
    """
}
