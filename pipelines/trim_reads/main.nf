nextflow.enable.types = true

//
// Read trimming pipeline
//

include { FASTP           } from '../../modules/nf-core/fastp/main'
include { STAGE_HELP      } from '../../subworkflows/local/utils_stage_help/main'
include { checkStageInput } from '../../subworkflows/local/utils_stage_help/main'
include { readGroupMeta             } from '../../subworkflows/local/utils_nfcore_biovat_pipeline'
include { attachSingleEnd            } from '../../subworkflows/local/utils_stage_help/main'
include { sampleToRow     } from '../../subworkflows/local/utils_nfcore_biovat_pipeline'
include { MULTIQC_REPORT        } from '../../subworkflows/local/multiqc_report/main'
include { paramsSummaryMap       } from 'plugin/nf-schema'
include { paramsSummaryMultiqc   } from '../../subworkflows/nf-core/utils_nfcore_pipeline'

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
    id        : String     // sample name
    meta      : Record     // read group information, requires read_group
    reads     : List<Path> // fastq files, in order
    single_end: Boolean    // whether the reads are single-end
}

params {
    samplesheet      : Channel<Sample>? // BioVAT samplesheet (CSV). Rows with a bam instead of fastq files are skipped
    reads            : Channel<Reads>?  // alternative to the samplesheet: reads with their meta record, from a YAML or JSON file or a calling pipeline
    adapter_fasta    : Path?           // adapter fasta file, if provided
    save_trimmed_fail: Boolean = false // save files that failed to pass trimming thresholds
    save_merged      : Boolean = false // save all merged reads
    stage_multiqc              : Boolean = true // run MultiQC on the files of this stage. A calling pipeline that runs MultiQC on the files of all its stages sets it to false. multiqc_files is emitted either way
    multiqc_config             : Path?
    multiqc_title              : String?
    multiqc_logo               : Path?
    multiqc_methods_description: Path?
    help             : Boolean = false
    help_full        : Boolean = false
}

workflow {

    main:
    STAGE_HELP(params.help, params.help_full, "${moduleDir}/nextflow_schema.json", 'nextflow run pipelines/trim_reads --samplesheet samplesheet.csv')
    checkStageInput(params.samplesheet, params.reads, 'reads')
    reads = channel.empty()
    if ( params.samplesheet ) {
        reads = params.samplesheet
            // Every row is checked, including the ones this stage skips
            .map { sample -> sampleToRow(sample) }
            .filter { row -> row[0].input_type == 'fastq' }
            .map { row -> record(id: row[0].id, meta: readGroupMeta(row[0]), reads: row[1], single_end: row[0].single_end) }
    } else {
        reads = params.reads
    }

    // Run fastp for read trimming
    fastp = FASTP(
        reads.map { r ->
            record(
                id                  : r.id,
                meta                : r.meta,
                single_end          : r.single_end,
                reads               : r.reads,
                adapter_fasta       : params.adapter_fasta,
                discard_trimmed_pass: false,                      // Never discard reads that pass trimming thresholds, so fastp can still be used for the report only
                save_trimmed_fail   : params.save_trimmed_fail,   // Whether to save files that failed to pass trimming thresholds ending in *.fail.fastq.gz
                save_merged         : params.save_merged,         // Whether to save all merged reads to a file ending in *.merged.fastq.gz
                fastp_args          : null,
                output_prefix       : r.meta.read_group
            )
        }
    )

    multiqc_files = fastp.map { out -> out.json }

    // MultiQC and software versions of this stage
    multiqc  = channel.empty()
    versions = channel.empty()
    if ( params.stage_multiqc ) {
        report   = MULTIQC_REPORT(
            multiqc_files,
            params.multiqc_config,
            params.multiqc_logo,
            params.multiqc_title,
            params.multiqc_methods_description,
            paramsSummaryMultiqc(paramsSummaryMap(workflow, parameters_schema: "${moduleDir}/nextflow_schema.json"))
        )
        multiqc  = channel.empty().mix(report.multiqc)
        versions = report.versions
    }

    publish:
    fastp         = fastp                                                                                                     // record(meta, reads, json, html, log, reads_fail, reads_merged)
    trimmed_reads = attachSingleEnd(fastp, reads)
        .map { j -> record(id: j.out.id, meta: j.out.meta, reads: j.out.reads.toList().toSorted { a, b -> a.name <=> b.name }, single_end: j.single_end) } // record(id, meta, reads, single_end)
    multiqc_files = multiqc_files
    multiqc       = multiqc
    versions      = versions

}

output {
    fastp        : Channel<Record> { path 'fastp' }
    trimmed_reads: Channel<Record> { path 'trimmed_reads' }
    multiqc_files: Channel<Path> {
        path 'multiqc_files'
        enabled !params.stage_multiqc // published only when the stage report is off, for a MultiQC run of your own
    }
    multiqc      : Channel<Record> { path 'multiqc' }
    versions     : Channel<Path> { path 'pipeline_info' }
}
