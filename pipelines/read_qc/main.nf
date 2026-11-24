nextflow.enable.types = true

//
// Read QC pipeline
//

include { FASTQC          } from '../../modules/nf-core/fastqc/main'
include { STAGE_HELP      } from '../../subworkflows/local/utils_stage_help/main'
include { checkStageInput } from '../../subworkflows/local/utils_stage_help/main'
include { readGroupMeta            } from '../../subworkflows/local/utils_nfcore_biovat_pipeline'
include { sampleToRow     } from '../../subworkflows/local/utils_nfcore_biovat_pipeline'
include { MULTIQC_REPORT  } from '../../subworkflows/local/multiqc_report/main'
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
    id   : String     // sample name
    meta : Record     // read group information, requires read_group
    reads: List<Path> // fastq files, in order
}

params {
    samplesheet: Channel<Sample>? // BioVAT samplesheet (CSV). Rows with a bam instead of fastq files are skipped
    reads      : Channel<Reads>?  // alternative to the samplesheet: reads with their meta record, from a YAML or JSON file or a calling pipeline
    stage_multiqc              : Boolean = true // run MultiQC on the files of this stage. A calling pipeline that runs MultiQC on the files of all its stages sets it to false. multiqc_files is emitted either way
    multiqc_config             : Path?
    multiqc_title              : String?
    multiqc_logo               : Path?
    multiqc_methods_description: Path?
    help     : Boolean = false
    help_full: Boolean = false
}

workflow {

    main:
    STAGE_HELP(params.help, params.help_full, "${moduleDir}/nextflow_schema.json", 'nextflow run pipelines/read_qc --samplesheet samplesheet.csv')
    checkStageInput(params.samplesheet, params.reads, 'reads')
    reads = channel.empty()
    if ( params.samplesheet ) {
        reads = params.samplesheet
            // Every row is checked, including the ones this stage skips
            .map { sample -> sampleToRow(sample) }
            .filter { row -> row[0].input_type == 'fastq' }
            .map { row -> record(id: row[0].id, meta: readGroupMeta(row[0]), reads: row[1]) }
    } else {
        reads = params.reads
    }

    fastqc = FASTQC(
        reads.map { r -> record(id: r.id, meta: r.meta, reads: r.reads, fastqc_args: '--quiet', output_prefix: r.meta.read_group) }
    )

    multiqc_files = fastqc.flatMap { out -> out.zip.toList() }

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
    fastqc        = fastqc                                         // record(meta, html, zip)
    multiqc_files = multiqc_files
    multiqc       = multiqc                                        // record(meta, report, data, plots)
    versions      = versions

}

output {
    fastqc       : Channel<Record> { path 'fastqc' }
    multiqc_files: Channel<Path> {
        path 'multiqc_files'
        enabled !params.stage_multiqc // published only when the stage report is off, for a MultiQC run of your own
    }
    multiqc      : Channel<Record> { path 'multiqc' }
    versions     : Channel<Path> { path 'pipeline_info' }
}
