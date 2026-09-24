process PARABRICKS_MARKDUP {
    tag "${meta.id}"
    label 'process_high'
    label 'process_gpu'

    container "nvcr.io/nvidia/clara/clara-parabricks:4.7.1-1"

    input:
    tuple val(meta), path(bam)
    tuple val(meta2), path(fasta), path(fai)

    output:
    tuple val(meta), path("*.bam"), emit: bam, optional: true
    tuple val(meta), path("*.cram"), emit: cram, optional: true
    tuple val(meta), path("*.metrics.txt"), emit: metrics
    tuple val("${task.process}"), val('parabricks'), eval("pbrun version | grep -m1 '^pbrun:' | sed 's/^pbrun:[[:space:]]*//'"), topic: versions, emit: versions_parabricks

    when:
    task.ext.when == null || task.ext.when

    script:
    // Exit if running this module with -profile conda / -profile mamba
    if (workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1) {
        error("Parabricks module does not support Conda. Please use Docker / Singularity / Podman instead.")
    }
    def args      = task.ext.args ?: ''
    def args2     = task.ext.args2 ?: ''
    def prefix    = task.ext.prefix ?: "${meta.id}"
    def reference = fasta ? "--ref ${fasta}" : ''
    // pbrun infers the output format (BAM or CRAM) from the --out-bam filename
    // extension, so match whatever format the input alignment is in.
    def suffix    = bam.getExtension()
    """
    # pbrun markdup requires queryname-sorted input, but the pipeline supplies
    # coordinate-sorted, indexed BAMs/CRAMs, so presort with bamsort first. The
    # intermediate is kept as BAM regardless of the final format: queryname
    # order defeats CRAM's reference-based compression, and it is deleted
    # immediately after markdup runs.
    pbrun \\
        bamsort \\
        ${reference} \\
        --in-bam ${bam} \\
        --out-bam queryname_sorted.bam \\
        --sort-order queryname \\
        ${args}

    # NOT passing --markdups-assume-sortorder-queryname to markdup: leaving it
    # unset keeps markdup's output equivalent to GATK MarkDuplicates run on a
    # coordinate-sorted BAM, matching the picard/samtools duplicate_marker options.
    pbrun \\
        markdup \\
        ${reference} \\
        --in-bam queryname_sorted.bam \\
        --out-bam ${prefix}.${suffix} \\
        --out-duplicate-metrics ${prefix}.metrics.txt \\
        ${args2}

    rm queryname_sorted.bam
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = bam.getExtension()
    """
    touch ${prefix}.${suffix}
    touch ${prefix}.metrics.txt
    """

}
