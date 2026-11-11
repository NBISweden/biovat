nextflow.enable.types = true

//
// Records of the samplesheet rows, shared by BioVAT and its stage pipelines
//

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

// A row of the samplesheet of the stages that start from alignments
record AlignmentSample {
    sample    : String   // sample name
    library_id: String?  // library, needed to merge, deduplicate or run QC at library level
    platform  : String   // sequencing platform
    single_end: Boolean  // whether the reads are single-end
    alignment : Path     // BAM or CRAM file
    index     : Path     // index of the BAM or CRAM file
}
