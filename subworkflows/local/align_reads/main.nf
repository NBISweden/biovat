include { BWAMEM3_INDEX     } from '../../../modules/nf-core/bwamem3/index/main'
include { BWAMEM3_MEM       } from '../../../modules/nf-core/bwamem3/mem/main'
include { BWA_INDEX         } from '../../../modules/nf-core/bwa/index/main'
include { PARABRICKS_FQ2BAM } from '../../../modules/nf-core/parabricks/fq2bam/main'
include { SAMTOOLS_INDEX    } from '../../../modules/nf-core/samtools/index/main'
include { ALIGNMENT_QC      } from '../alignment_qc/main'

workflow ALIGN_READS {
    take:
    aligner                       // string: Aligner to use for read alignment (e.g. bwa, parabricks)
    ch_reference_and_optional_fai // value channel: reference fasta and (optional) fai index
    reads                         // channel: reads to align
    enable                        // map: stage/tool gating flags
    ch_multiqc_files              // channel: MultiQC files

    main:
    reference = ch_reference_and_optional_fai.map { meta, fasta, _fai -> [meta, fasta] }

    // Alignment
    if (aligner == 'bwa-mem3') {
        bwamem3_index_out = BWAMEM3_INDEX(reference)
        bwamem3_mem_out = BWAMEM3_MEM(
            reads,
            bwamem3_index_out.index,
            reference,
            true, // Enforce sorting of BAM/CRAM
        )
        ch_read_group_alignments_indexed = bwamem3_mem_out.aligned.join(bwamem3_mem_out.index)
    }
    else if (aligner == 'parabricks') {
        // Parabricks requires BWA v0.7.x indexes
        bwa_index_out = BWA_INDEX(reference)
        parabricks_fq2bam_out = PARABRICKS_FQ2BAM(
            reads,
            reference,
            bwa_index_out.index,
            [[], []], // intervals
            [[], []], // known_sites
            enable.cram_format ? 'cram' : 'bam',
        )
        samtools_index_out = SAMTOOLS_INDEX(parabricks_fq2bam_out.bam)
        ch_read_group_alignments_indexed = parabricks_fq2bam_out.bam.join(samtools_index_out.index)
    }

    // ALIGN_READS:ALIGNMENT_QC
    outputs_read_group_flagstat = channel.empty()
    outputs_read_group_riker = channel.empty()
    outputs_read_group_qualimap = channel.empty()
    if (enable.align_qc) {
        alignment_qc_out = ALIGNMENT_QC(
            ch_read_group_alignments_indexed,
            ch_reference_and_optional_fai,
            enable,
            'readgroup',
        )
        ch_multiqc_files = ch_multiqc_files.mix(
            alignment_qc_out.flagstat_outputs.map { _meta, file -> file },
            alignment_qc_out.riker_outputs.map { _meta, file -> file },
            alignment_qc_out.qualimap_outputs.map { _meta, file -> file },
        )
        outputs_read_group_flagstat = alignment_qc_out.flagstat_outputs
        outputs_read_group_riker = alignment_qc_out.riker_outputs
        outputs_read_group_qualimap = alignment_qc_out.qualimap_outputs
    }

    emit:
    ch_read_group_alignments_indexed // channel: <Map> meta, <Path> bam, <Path> csi
    outputs_read_group_flagstat
    outputs_read_group_riker
    outputs_read_group_qualimap
    ch_multiqc_files
}
