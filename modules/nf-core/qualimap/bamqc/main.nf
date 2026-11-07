nextflow.enable.types = true

process QUALIMAP_BAMQC {
    tag "${id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/2b/2b795495fdae4cb3319d19ed4a694302366aa574ba15a0613b85c602f0de4911/data' :
        'community.wave.seqera.io/library/qualimap:2.3--c1797c2253925b3a' }"

    ext [
        prefix: { output_prefix ?: "${id}" },
        args: { qualimap_bamqc_args ?: '' }
    ]

    input:
    record(
        id: String,
        meta: Record?,
        single_end: Boolean,
        bam: Path,
        gff: Path?,
        qualimap_bamqc_args: String?,
        output_prefix: String?
    )

    output:
    record(
        id: id,
        meta: meta,
        results: file(task.ext.prefix)
    )

    topic:
    record(process: "${task.process}", tool: 'qualimap', version: eval("qualimap -h | sed -n 's/^QualiMap v.//p'")) >> 'versions'

    script:
    def collect_pairs = single_end ? '' : '--collect-overlap-pairs'
    def memory = "${(task.memory.toMega() * 0.8).intValue()}M"
    def regions = gff ? "--gff $gff" : ''
    """
    unset DISPLAY
    mkdir -p tmp
    export _JAVA_OPTIONS=-Djava.io.tmpdir=./tmp
    qualimap \\
        --java-mem-size=$memory \\
        bamqc \\
        ${task.ext.args} \\
        -bam $bam \\
        $regions \\
        $collect_pairs \\
        -outdir ${task.ext.prefix} \\
        -nt $task.cpus
    """

    stub:
    """
    mkdir -p ${task.ext.prefix}/css
    mkdir ${task.ext.prefix}/images_qualimapReport
    mkdir ${task.ext.prefix}/raw_data_qualimapReport
    cd ${task.ext.prefix}/css
    touch agogo.css
    touch basic.css
    touch bgtop.png
    touch comment-close.png
    touch doctools.js
    touch down-pressed.png
    touch jquery.js
    touch plus.png
    touch qualimap_logo_small.png
    touch searchtools.js
    touch up.png
    touch websupport.js
    touch ajax-loader.gif
    touch bgfooter.png
    touch comment-bright.png
    touch comment.png
    touch down.png
    touch file.png
    touch minus.png
    touch pygments.css
    touch report.css
    touch underscore.js
    touch up-pressed.png
    cd ../images_qualimapReport/
    touch genome_coverage_0to50_histogram.png
    touch genome_coverage_quotes.png
    touch genome_insert_size_across_reference.png
    touch genome_mapping_quality_histogram.png
    touch genome_uniq_read_starts_histogram.png
    touch genome_coverage_across_reference.png
    touch genome_gc_content_per_window.png
    touch genome_insert_size_histogram.png
    touch genome_reads_clipping_profile.png
    touch genome_coverage_histogram.png
    touch genome_homopolymer_indels.png
    touch genome_mapping_quality_across_reference.png
    touch genome_reads_content_per_read_position.png
    cd ../raw_data_qualimapReport
    touch coverage_across_reference.txt
    touch genome_fraction_coverage.txt
    touch insert_size_histogram.txt
    touch mapped_reads_nucleotide_content.txt
    touch coverage_histogram.txt
    touch homopolymer_indels.txt
    touch mapped_reads_clipping_profile.txt
    touch mapping_quality_across_reference.txt
    touch duplication_rate_histogram.txt
    touch insert_size_across_reference.txt
    touch mapped_reads_gc-content_distribution.txt
    touch mapping_quality_histogram.txt
    cd ../
    touch genome_results.txt
    touch qualimapReport.html
    cd ../
    """
}
