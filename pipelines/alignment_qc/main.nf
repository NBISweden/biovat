nextflow.enable.types = true

//
// Alignment QC pipeline: samtools flagstat, Riker and Qualimap on alignments.
// The level at which the alignments were produced names the output files. The stages that make alignments
// include this pipeline under their own alias, with their level
//

include { SAMTOOLS_FLAGSTAT } from '../../modules/nf-core/samtools/flagstat/main'
include { RIKER_MULTI       } from '../../modules/nf-core/riker/multi/main'
include { QUALIMAP_BAMQC    } from '../../modules/nf-core/qualimap/bamqc/main'
include { REFERENCE_VALUE   } from '../../subworkflows/local/utils_reference/main'
include { STAGE_HELP        } from '../../subworkflows/local/utils_stage_help/main'
include { checkStageInput   } from '../../subworkflows/local/utils_stage_help/main'
include { stageError      } from '../../subworkflows/local/utils_stage_help/main'

// A row of the alignments samplesheet (CSV)
record AlignmentSample {
    sample    : String  // sample name
    library_id: String? // library, needed at the library and markdup levels
    platform  : String  // sequencing platform
    single_end: Boolean // whether the reads are single-end
    alignment : Path    // BAM or CRAM file
    index     : Path    // index of the BAM or CRAM file
}

record Alignment {
    meta     : Record // sample information, requires id, pl, single_end, and read_group (input and readgroup levels) or library (library and markdup levels)
    alignment: Path   // BAM or CRAM file
    index    : Path   // index of the BAM or CRAM file
}

params {
    samplesheet: Channel<AlignmentSample>? // alignments samplesheet (CSV with the columns sample, library_id, platform, single_end, alignment, index)
    alignments : Channel<Alignment>?       // alternative to the samplesheet: alignments with their meta record, from a YAML or JSON file or a calling pipeline
    level      : String?                   // level at which the alignments were produced: 'input', 'readgroup', 'library', 'markdup' or 'sample'
    fasta      : Value<Path>?              // reference fasta, needed by Riker and to decode CRAM
    fai        : Value<Path>?              // fai index of the reference fasta, needed by Riker and to decode CRAM
    riker      : Boolean = true            // run Riker
    qualimap   : Boolean = false           // run Qualimap
    help       : Boolean = false
    help_full  : Boolean = false
}

workflow {

    main:
    STAGE_HELP(params.help, params.help_full, "${moduleDir}/nextflow_schema.json", 'nextflow run pipelines/alignment_qc --samplesheet alignments.csv --level sample --fasta reference.fasta --fai reference.fasta.fai')
    checkStageInput(params.samplesheet, params.alignments, 'alignments')
    if ( !(params.level in [ 'input', 'readgroup', 'library', 'markdup', 'sample' ]) ) {
        error "--level is required, one of input, readgroup, library, markdup, sample"
    }
    reference = REFERENCE_VALUE(params.fasta, params.fai, params.riker)

    alignments = channel.empty()
    if ( params.samplesheet ) {
        alignments = params.samplesheet.map { s ->
            if ( params.level in [ 'library', 'markdup' ] && s.library_id == null ) {
                stageError "Level '${params.level}' needs a library_id for every row of the samplesheet (missing for sample '${s.sample}')"
            }
            def meta = [ id: s.sample, library: s.library_id, pl: s.platform, single_end: s.single_end, read_group: s.alignment.baseName ]
            record(meta: record(meta), alignment: s.alignment, index: s.index)
        }
    } else {
        alignments = params.alignments
    }

    // Tag each alignment with a level-scoped prefix so each output file is named by its level and read group/library/sample
    qc_input = alignments
        .map { aln ->
            // Input (user BAM/CRAM) and read-group-level records still carry all meta, library/markdup have readgroups
            // merged to library level, sample-level merging groups on {id, pl}, dropping library
            def prefix = params.level in [ 'input', 'readgroup' ]
                ? aln.meta.read_group
                : params.level == 'sample'
                    ? "${aln.meta.id}_${aln.meta.pl}"
                    : "${aln.meta.id}_${aln.meta.library}_${aln.meta.pl}" // else 'library' or 'markdup'
            record(meta: aln.meta, alignment: aln.alignment, index: aln.index, qc_prefix: "${params.level}_${prefix}")
        }

    // SAMTOOLS_FLAGSTAT
    flagstat = SAMTOOLS_FLAGSTAT(
        qc_input.map { qc -> record(id: qc.meta.id, meta: qc.meta, bam: qc.alignment, bai: qc.index, output_prefix: qc.qc_prefix) }
    )

    // RIKER
    riker_out = channel.empty()
    if ( params.riker ) {
        riker_out = RIKER_MULTI(
            qc_input
                .combine(reference)
                .map { qc, ref ->
                    record(
                        id                      : qc.meta.id,
                        meta                    : qc.meta,
                        bam                     : qc.alignment,
                        bai                     : qc.index,
                        error_vcf               : null,
                        error_vcf_idx           : null,
                        error_intervals         : null,
                        gcbias_exclude_intervals: null,
                        hybcap_baits            : null,
                        hybcap_targets          : null,
                        rna_gene_model          : null,
                        rna_ribosomal_intervals : null,
                        wgs_intervals           : null, // TODO: Potentially support optional inputs, except RNA-seq specific.
                        fasta                   : ref.fasta,
                        fai                     : ref.fai,
                        riker_multi_args        : '--tools alignment basic isize wgs gcbias',
                        output_prefix           : qc.qc_prefix
                    )
                }
        )
    }

    // QUALIMAP
    qualimap_out = channel.empty()
    if ( params.qualimap ) {
        qualimap_out = QUALIMAP_BAMQC(
            qc_input.map { qc ->
                record(
                    id                  : qc.meta.id,
                    meta                : qc.meta,
                    single_end          : qc.meta.single_end,
                    bam                 : qc.alignment,
                    gff                 : null, // TODO: Potentially support optional input (gff file)
                    qualimap_bamqc_args : null,
                    output_prefix       : qc.qc_prefix
                )
            }
        )
    }

    publish:
    flagstat      = flagstat.map { out -> record(meta: out.meta, flagstat: out.flagstat) }
    riker         = riker_out // record(meta, <riker metric files>)
    qualimap      = qualimap_out.map { out -> record(meta: out.meta, results: out.results) }
    multiqc_files = flagstat
        .map { out -> out.flagstat }
        .mix(riker_out.flatMap { out -> rikerFiles(out) })
        .mix(qualimap_out.map { out -> out.results })

}

output {
    flagstat     : Channel<Record> { path 'flagstat' }
    riker        : Channel<Record> { path 'riker' }
    qualimap     : Channel<Record> { path 'qualimap' }
    multiqc_files: Channel<Path> { path 'multiqc_files' }
}

def rikerFiles(riker: Record) {
    def single = [
        riker.alignment_metrics, riker.base_dist, riker.error_indel, riker.error_mismatch, riker.error_overlap,
        riker.gcbias_detail, riker.gcbias_summary, riker.hybcap_metrics, riker.hybcap_per_target,
        riker.isize_histogram, riker.isize_metrics, riker.mean_qual, riker.qual_dist, riker.rna_biotype,
        riker.rna_insert_size_histogram, riker.rna_insert_size, riker.rna_metrics, riker.wgs_coverage, riker.wgs_metrics
    ].findAll { file -> file != null }
    return single + riker.hybcap_per_base.toList() + riker.pdf.toList()
}
