#!/usr/bin/env python3
"""
split_genome_chunks.py

Split a reference genome, given as a samtools FAI index, into
approximately evenly-sized genome chunks in BED format,
without splitting chromosomes and preserving chromosome order.

Input: a samtools FAI index.
Output: one or more BED files named `chunk_00001.bed` through
`chunk_XXXXX.bed`, plus `excluded_regions.tsv` (regions dropped by
--min_length) and `genome_chunking_mqc.tsv` (a MultiQC custom-content
summary table).

Code was written with assistance from Claude.
"""

import argparse
import sys
from pathlib import Path

# Default chunk size aims for about this many chunks, so fragmented assemblies don't yield thousands of tiny chunks
DEFAULT_TARGET_CHUNKS = 50

def parse_args(argv=None):
    p = argparse.ArgumentParser(description="Split a reference FAI into approximately evenly-sized genome chunks (BED format).",)
    p.add_argument("--input", required=True, type=Path, help="Reference genome samtools FAI index.",)
    p.add_argument("--chunk_size", type=int, default=None, help=f"Target chunk size in bp. Default: the larger between 1) the longest region and 2) retained total bp / {DEFAULT_TARGET_CHUNKS}. If set under the longest region, chunk size will be automatically set to the longest region length.",)
    p.add_argument("--min_length", type=int, default=0, help="Skip regions shorter than this length (bp). Default: 0 (keep all).",)
    p.add_argument("--output_dir", type=Path, default=Path("."), help="Directory to write chunk_*.bed files into. Default: current working directory.",)
    return p.parse_args(argv)


def read_fai(path: Path):
    """Yield (chrom, start, end, length) per FAI record, exiting on malformed lines."""
    with path.open() as fh:
        for line_no, raw_line in enumerate(fh, start=1):
            line = raw_line.rstrip("\n")
            if not line:
                continue
            # FAI: name  length  offset  linebases  linewidth
            fields = line.split("\t")
            try:
                length = int(fields[1])
            except (IndexError, ValueError):
                length = None
            if length is None or length <= 0:
                sys.exit(f"ERROR: {path}:{line_no}: expected a FAI record (name, positive length, ...), got: {line!r}")
            yield (fields[0], 0, length, length)


def kept_regions(regions, min_length):
    kept = []
    dropped = []
    for chrom, start, end, length in regions:
        if length < min_length:
            dropped.append((chrom, length))
            continue
        kept.append((chrom, start, end, length))
    if not kept:
        sys.exit(
            f"ERROR: all chromosomes were filtered out by --min_length={min_length}."
        )
    if dropped:
        # Kept on stderr for the task log; the pipeline also reports exclusions via the output files
        dropped_bp = sum(length for _, length in dropped)
        total_bp = dropped_bp + sum(length for *_, length in kept)
        shown = ", ".join(chrom for chrom, _ in dropped[:10])
        more = f" and {len(dropped) - 10} more" if len(dropped) > 10 else ""
        print(
            f"[split_genome_chunks] WARNING: --min_length ({min_length}) "
            f"excluded {len(dropped)} of {len(regions)} regions "
            f"({dropped_bp} of {total_bp} bp, {100 * dropped_bp / total_bp:.2f}%) "
            f"from variant calling: {shown}{more}.",
            file=sys.stderr,
        )
    return kept, dropped


def find_chunk_size(chunk_size, longest, total):
    if chunk_size is None:
        # Ceiling division, so the target count isn't exceeded just by rounding down
        chunk_size = max(longest, -(-total // DEFAULT_TARGET_CHUNKS))
    elif chunk_size < longest:
        print(
            f"[split_genome_chunks] WARNING: --chunk_size ({chunk_size}) is "
            f"smaller than the longest chromosome ({longest} bp); "
            f"raising --chunk_size to {longest} to avoid splitting chromosomes.",
            file=sys.stderr,
        )
        chunk_size = longest
    return chunk_size


def chunk_regions(regions, chunk_size):
    """Group regions in order into chunks, starting a new chunk when the next region would exceed chunk_size."""
    chunks = []
    current = []
    current_total = 0
    for region in regions:
        length = region[3]
        if current and current_total + length > chunk_size:
            chunks.append(current)
            current = []
            current_total = 0
        current.append(region)
        current_total += length
    if current:
        chunks.append(current)
    return chunks


def write_chunks(chunks, output_dir):
    for idx, chunk in enumerate(chunks, start=1):
        with (output_dir / f"chunk_{idx:05d}.bed").open("w") as out:
            for chrom, start, end, _ in chunk:
                out.write(f"{chrom}\t{start}\t{end}\n")


def write_excluded(dropped, output_dir):
    with (output_dir / "excluded_regions.tsv").open("w") as out:
        out.write("chrom\tlength\n")
        for chrom, length in dropped:
            out.write(f"{chrom}\t{length}\n")


def write_mqc_summary(kept, dropped, chunk_size, n_chunks, input_path, min_length, output_dir):
    kept_bp = sum(length for *_, length in kept)
    dropped_bp = sum(length for _, length in dropped)
    excluded_pct = 100 * dropped_bp / (kept_bp + dropped_bp)
    reference = input_path.name.removesuffix(".fai")
    with (output_dir / "genome_chunking_mqc.tsv").open("w") as out:
        out.write(
            "# id: 'genome_chunking'\n"
            "# section_name: 'Genome chunking'\n"
            f"# description: 'Reference regions used for variant calling. Regions shorter than --min_length ({min_length} bp) are excluded and listed in genome_chunk_bed_files/excluded_regions.tsv.'\n"
            "# plot_type: 'table'\n"
            "# pconfig:\n"
            "#     id: 'genome_chunking_table'\n"
            "#     namespace: 'Genome chunking'\n"
        )
        out.write("Reference\tRegions kept\tRegions excluded\tBp kept\tBp excluded\tExcluded %\tChunk size\tChunks\n")
        out.write(f"{reference}\t{len(kept)}\t{len(dropped)}\t{kept_bp}\t{dropped_bp}\t{excluded_pct:.2f}\t{chunk_size}\t{n_chunks}\n")


def main(argv=None):
    args = parse_args(argv)

    # First pass: read everything
    regions = list(read_fai(args.input))
    if not regions:
        sys.exit(f"ERROR: no regions in {args.input}.")

    # Filter by min_length and find the longest chromosome
    kept, dropped = kept_regions(regions, args.min_length)
    longest = max(length for *_, length in kept)
    kept_bp = sum(length for *_, length in kept)

    # Resolve chunk size
    chunk_size = find_chunk_size(args.chunk_size, longest, kept_bp)

    # Ensure output directory exists
    args.output_dir.mkdir(parents=True, exist_ok=True)

    chunks = chunk_regions(kept, chunk_size)
    write_chunks(chunks, args.output_dir)
    write_excluded(dropped, args.output_dir)
    write_mqc_summary(kept, dropped, chunk_size, len(chunks), args.input, args.min_length, args.output_dir)

    # stderr report
    print(
        f"[split_genome_chunks] input={args.input} "
        f"kept_regions={len(kept)} longest={longest} "
        f"chunk_size={chunk_size} min_length={args.min_length} "
        f"output_dir={args.output_dir} "
        f"chunks_written={len(chunks)}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
