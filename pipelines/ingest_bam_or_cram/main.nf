nextflow.enable.types = true

//
// BAM/CRAM ingestion pipeline
//

include { VALIDATE_READGROUP_HEADER } from '../../modules/local/validate_readgroup_header/main'
include { SAMTOOLS_ADDREPLACERG     } from '../../modules/nf-core/samtools/addreplacerg/main'
include { SAMTOOLS_SORT             } from '../../modules/nf-core/samtools/sort/main'
include { ALIGNMENT_QC              } from '../../subworkflows/local/alignment_qc/main'
include { REFERENCE_VALUE           } from '../../subworkflows/local/utils_reference/main'
include { STAGE_HELP                } from '../../subworkflows/local/utils_stage_help/main'
include { sampleToRow               } from '../../subworkflows/local/utils_nfcore_biovat_pipeline'

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

record BamCram {
    meta    : Record // sample information, requires id, library, pl, platform_unit and read_group
    bam_cram: Path   // aligned BAM or CRAM file
}

params {
    samplesheet: Channel<Sample>?  // BioVAT samplesheet (CSV). Rows with fastq files instead of a bam are skipped
    bam_cram   : Channel<BamCram>? // alternative to the samplesheet: BAM/CRAM files with their meta record, from a YAML or JSON file or a calling pipeline
    fasta      : Value<Path>?      // reference fasta, needed to decode CRAM
    fai        : Value<Path>?      // fai index of the reference fasta, needed by Riker
    cram_format: Boolean = false   // write CRAM instead of BAM
    align_qc   : Boolean = true    // run quality checks on the alignments
    riker      : Boolean = true    // run Riker during alignment QC
    qualimap   : Boolean = false   // run Qualimap during alignment QC
    help       : Boolean = false
    help_full  : Boolean = false
}

workflow {

    main:
    STAGE_HELP(params.help, params.help_full, "${moduleDir}/nextflow_schema.json", 'nextflow run pipelines/ingest_bam_or_cram --samplesheet samplesheet.csv --fasta genome.fa')
    if ( params.samplesheet && params.bam_cram ) {
        error "Provide either --samplesheet or --bam_cram, not both"
    }
    if ( !params.samplesheet && !params.bam_cram ) {
        error "Missing required parameter --samplesheet"
    }
    bam_cram = channel.empty()
    if ( params.samplesheet ) {
        bam_cram = params.samplesheet
            .filter { sample -> sample.bam != null }
            .map { sample ->
                def row = sampleToRow(sample)
                record(meta: record(row[0]), bam_cram: row[1][0])
            }
    } else {
        bam_cram = params.bam_cram
    }

    reference = REFERENCE_VALUE(params.fasta, params.fai, (params.align_qc && params.riker) || params.cram_format)

    // Reject a BAM/CRAM with several @RG lines, or one whose @RG tags are missing or disagree with its samplesheet row
    validated = VALIDATE_READGROUP_HEADER(
        bam_cram.map { r ->
            record(id: r.meta.id, meta: r.meta, library: "${r.meta.library}", platform: r.meta.pl, platform_unit: r.meta.platform_unit, bam_cram: r.bam_cram)
        }
    )

    // A BAM/CRAM with no @RG line gets one built from its samplesheet row
    missing_rg = validated.filter { v -> v.rg_status == 'missing' }
    present_rg = validated.filter { v -> v.rg_status != 'missing' }
    addreplacerg = SAMTOOLS_ADDREPLACERG(
        missing_rg
            .combine(reference)
            .map { v, ref ->
                log.warn "No @RG header line in '${v.bam_cram.name}' (sample '${v.meta.id}', library '${v.meta.library}'): adding one from the samplesheet and tagging the reads"
                record(
                    id                        : v.id,
                    meta                      : v.meta,
                    input                     : v.bam_cram,
                    index                     : null,
                    read_group                : '',
                    fasta                     : ref.fasta,
                    fai                       : ref.fai,
                    gzi                       : null,
                    // only reached by inputs with no @RG line. BAM out, as SAMTOOLS_SORT sets the final format
                    samtools_addreplacerg_args: [
                        "-m overwrite_all",
                        "--output-fmt bam",
                        "-r '@RG\\tID:${v.meta.platform_unit}\\tSM:${v.meta.id}\\tLB:${v.meta.library}\\tPU:${v.meta.platform_unit}\\tPL:${v.meta.pl}'"
                    ].join(" "),
                    output_prefix             : "${v.meta.read_group}_rg"
                )
            }
    )

    // Ensure compatible sort order, index, and convert CRAM to BAM/BAM to CRAM if required
    to_sort = present_rg
        .map { v -> record(meta: v.meta, alignment: v.bam_cram) }
        .mix(addreplacerg.map { out -> record(meta: out.meta, alignment: out.bam) })
    sorted = SAMTOOLS_SORT(
        to_sort
            .combine(reference)
            .map { a, ref ->
                record(
                    id                : a.meta.id,
                    meta              : a.meta,
                    bam               : [ a.alignment ],
                    fasta             : ref.fasta,
                    fai               : ref.fai,
                    index_format      : params.cram_format ? 'crai' : 'csi',
                    samtools_sort_args: params.cram_format ? '--output-fmt cram' : null,
                    output_prefix     : a.meta.read_group
                )
            }
    )
    alignments = sorted.map { out -> record(meta: out.meta, alignment: out.bam ?: out.cram, index: out.index) }

    // INGEST_BAM_OR_CRAM:ALIGNMENT_QC
    qc_flagstat      = channel.empty()
    qc_riker         = channel.empty()
    qc_qualimap      = channel.empty()
    qc_multiqc_files = channel.empty()
    if ( params.align_qc ) {
        alignment_qc     = ALIGNMENT_QC(alignments, reference, params.riker, params.qualimap, 'input')
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
