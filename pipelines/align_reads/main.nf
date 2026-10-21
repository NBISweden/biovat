nextflow.enable.types = true

//
// Read alignment pipeline
//

include { BWAMEM3_INDEX     } from '../../modules/nf-core/bwamem3/index/main'
include { BWAMEM3_MEM       } from '../../modules/nf-core/bwamem3/mem/main'
include { BWA_INDEX         } from '../../modules/nf-core/bwa/index/main'
include { PARABRICKS_FQ2BAM } from '../../modules/nf-core/parabricks/fq2bam/main'
include { SAMTOOLS_INDEX    } from '../../modules/nf-core/samtools/index/main'
include { ALIGNMENT_QC      } from '../../subworkflows/local/alignment_qc/main'
include { REFERENCE_VALUE   } from '../../subworkflows/local/utils_reference/main'
include { STAGE_HELP        } from '../../subworkflows/local/utils_stage_help/main'
include { sampleToRow       } from '../../subworkflows/local/utils_nfcore_biovat_pipeline'

// A row of the BioVAT samplesheet
record Sample {
    sample     : String
    library_id : String
    flowcell_id: String
    lane       : Integer
    platform   : String
    fastq_1    : Path?
    fastq_2    : Path?
    bam        : Path?
    single_end : Boolean?
}

record Reads {
    meta : Record     // sample information, requires id, library, pl, platform_unit and read_group
    reads: List<Path> // fastq files, in order
}

params {
    samplesheet: Channel<Sample>? // BioVAT samplesheet (CSV). Rows with a bam instead of fastq files are skipped
    reads     : Channel<Reads>?  // alternative to the samplesheet: reads with their meta record, from a YAML or JSON file or a calling pipeline
    aligner   : String = 'bwa-mem3' // alignment tool: bwa-mem3 or parabricks
    fasta     : Value<Path>?    // reference fasta
    fai       : Value<Path>?    // fai index of the reference fasta, needed by Riker
    cram_format: Boolean = false // write CRAM instead of BAM
    align_qc  : Boolean = true  // run quality checks on the alignments
    riker     : Boolean = true  // run Riker during alignment QC
    qualimap  : Boolean = false // run Qualimap during alignment QC
    help      : Boolean = false
    help_full : Boolean = false
}

workflow {

    main:
    STAGE_HELP(params.help, params.help_full, "${moduleDir}/nextflow_schema.json", 'nextflow run pipelines/align_reads --samplesheet samplesheet.csv --fasta genome.fa')
    if ( params.samplesheet && params.reads ) {
        error "Provide either --samplesheet or --reads, not both"
    }
    if ( !params.samplesheet && !params.reads ) {
        error "Missing required parameter --samplesheet"
    }
    reads = channel.empty()
    if ( params.samplesheet ) {
        reads = params.samplesheet
            .filter { sample -> sample.fastq_1 != null }
            .map { sample ->
                def row = sampleToRow(sample)
                record(meta: record(row[0]), reads: row[1])
            }
    } else {
        reads = params.reads
    }
    if ( !params.fasta ) {
        error "Missing required parameter --fasta"
    }

    reference = REFERENCE_VALUE(params.fasta, params.fai, (params.align_qc && params.riker) || params.cram_format)

    alignments = channel.empty()

    // Alignment
    if ( params.aligner == 'bwa-mem3' ) {
        index = BWAMEM3_INDEX(
            reference.map { ref -> record(id: ref.meta.id, meta: ref.meta, fasta: ref.fasta, bwamem3_index_args: null, output_prefix: null) }
        )
        mem = BWAMEM3_MEM(
            reads
                .combine(index)
                .combine(reference)
                .map { r, idx, ref ->
                    record(
                        id              : r.meta.id,
                        meta            : r.meta,
                        reads           : r.reads,
                        index           : idx.index,
                        fasta           : ref.fasta,
                        sort_bam        : true, // Enforce sorting of BAM/CRAM
                        bwamem3_mem_args: "-R '@RG\\tID:${r.meta.platform_unit}\\tSM:${r.meta.id}\\tLB:${r.meta.library}\\tPU:${r.meta.platform_unit}\\tPL:${r.meta.pl}'",
                        samtools_args   : [ "--write-index", params.cram_format ? "--output-fmt cram" : "" ].findAll { arg -> arg != "" }.join(" "),
                        output_prefix   : r.meta.read_group
                    )
                }
        )
        alignments = mem.map { out -> record(meta: out.meta, alignment: out.aligned, index: out.index) }
    } else if ( params.aligner == 'parabricks' ) {
        // Parabricks requires BWA v0.7.x indexes
        index = BWA_INDEX(
            reference.map { ref -> record(id: ref.meta.id, meta: ref.meta, fasta: ref.fasta, bwa_index_args: null, output_prefix: null) }
        )
        fq2bam = PARABRICKS_FQ2BAM(
            reads
                .combine(index)
                .combine(reference)
                .map { r, idx, ref ->
                    record(
                        id                    : r.meta.id,
                        meta                  : r.meta,
                        single_end            : r.meta.single_end,
                        reads                 : r.reads,
                        fasta                 : ref.fasta,
                        index                 : idx.index,
                        intervals             : null,
                        known_sites           : null,
                        known_sites_index     : null,
                        output_fmt            : params.cram_format ? 'cram' : 'bam',
                        parabricks_fq2bam_args: [
                            "--read-group-sm ${r.meta.id}",
                            "--read-group-lb ${r.meta.library}",
                            "--read-group-pl ${r.meta.pl}",
                            "--read-group-id-prefix ${r.meta.platform_unit}",
                            "--gpusort",
                            "--no-markdups",
                            "--gpuwrite"
                        ].findAll { arg -> arg != "" }.join(" "),
                        output_prefix         : r.meta.read_group
                    )
                }
        )
        indexed = SAMTOOLS_INDEX(
            fq2bam.map { out -> record(id: out.id, meta: out.meta, input: out.bam ?: out.cram, samtools_index_args: '--csi') }
        )
        alignments = fq2bam
            .map { out -> record(meta: out.meta, alignment: out.bam ?: out.cram) }
            .join(indexed.map { out -> record(meta: out.meta, index: out.index) }, by: 'meta')
    } else {
        error "Unknown aligner '${params.aligner}', expected bwa-mem3 or parabricks"
    }

    // ALIGN_READS:ALIGNMENT_QC
    qc_flagstat      = channel.empty()
    qc_riker         = channel.empty()
    qc_qualimap      = channel.empty()
    qc_multiqc_files = channel.empty()
    if ( params.align_qc ) {
        alignment_qc = ALIGNMENT_QC(alignments, reference, params.riker, params.qualimap, 'readgroup')
        qc_flagstat      = alignment_qc.flagstat
        qc_riker         = alignment_qc.riker
        qc_qualimap      = alignment_qc.qualimap
        qc_multiqc_files = alignment_qc.multiqc_files
    }

    publish:
    alignments    = alignments // record(meta, alignment, index)
    flagstat      = qc_flagstat
    riker         = qc_riker
    qualimap      = qc_qualimap
    multiqc_files = qc_multiqc_files

}

output {
    alignments   : Channel<Record> { path 'alignments' }
    flagstat     : Channel<Record> { path 'flagstat' }
    riker        : Channel<Record> { path 'riker' }
    qualimap     : Channel<Record> { path 'qualimap' }
    multiqc_files: Channel<Path> { path 'multiqc_files' }
}
