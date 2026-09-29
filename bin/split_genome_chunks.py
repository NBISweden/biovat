#!/usr/bin/env python3
"""
split_genome_chunks.py

Split a reference genome BED file (or a FAI index) into 
approximately evenly-sized genome chunks in BED format, 
without splitting chromosomes/regions and preserving 
chromosome order.

Input: a BED file specifying reference genome chromosomes 
or regions or a samtools FAI index.
Output: one or more BED files named `chunk_00001.bed` through 
`chunk_XXXXX.bed`.

Code was written with assistance from Claude.
"""

import argparse
import sys
from pathlib import Path


def parse_args(argv=None):
    p = argparse.ArgumentParser(description="Split a reference BED/FAI into approximately evenly-sized genome chunks (BED format).",)
    p.add_argument("--input", required=True, type=Path, help="Input file listing reference genome regions in either BED or FAI format.",)
    p.add_argument("--chunk_size", type=int, default=None, help="Target chunk size in bp. Default: length of the longest region. If smaller than the longest region, chunk size will be automatically set to the longest region length.",)
    p.add_argument("--min_length", type=int, default=0, help="Skip regions shorter than this length (bp). Default: 0 (keep all).",)
    p.add_argument("--output_dir", type=Path, default=Path("."), help="Directory to write chunk_*.bed files into. Default: current working directory.",)
    return p.parse_args(argv)


def read_regions(path: Path):
    is_fai = path.suffix.lower() == ".fai"

    with path.open() as fh:
        for raw_line in fh:
            line = raw_line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            fields = line.split("\t")
            if is_fai:
                # FAI: name  length  offset  linebases  linewidth
                start = 0
                end = int(fields[1])
            else:
                # BED: chrom  start  end  [...]
                start = int(fields[1])
                end = int(fields[2])
            chrom = fields[0]
            length = end - start
            yield (chrom, start, end, length)


def main(argv=None):
    args = parse_args(argv)

    def kept_regions(region_list):
        kept = []
        for chrom, start, end, length in region_list:
            if length < args.min_length:
                continue
            kept.append((chrom, start, end, length))
        if not kept:
            sys.exit(
                f"ERROR: all chromosomes were filtered out by --min_length={args.min_length}."
            )
        return kept

    def find_chunk_size(chunk_size, longest):
        if chunk_size is None:
            chunk_size = longest
        elif chunk_size < longest:
            print(
                f"[split_genome_chunks] WARNING: --chunk_size ({chunk_size}) is "
                f"smaller than the longest chromosome ({longest} bp); "
                f"raising --chunk_size to {longest} to avoid splitting chromosomes.",
                file=sys.stderr,
            )
            chunk_size = longest
        return chunk_size

    # First pass: read everything
    regions = list(read_regions(args.input))

    # Filter by min_length and find the longest chromosome
    kept = kept_regions(regions)
    longest = max(length for *_, length in kept)

    # Resolve chunk size
    chunk_size = find_chunk_size(args.chunk_size, longest)

    # Ensure output directory exists
    args.output_dir.mkdir(parents=True, exist_ok=True)

    # Chunking loop
    chunk_idx = 1
    current_lines = []
    current_total = 0
    written_chunks = 0

    def write_chunk():
        nonlocal chunk_idx, current_lines, current_total, written_chunks
        out_path = args.output_dir / f"chunk_{chunk_idx:05d}.bed"
        with out_path.open("w") as out:
            out.write("\n".join(current_lines) + "\n")
        written_chunks += 1
        chunk_idx += 1
        current_lines = []
        current_total = 0

    for chrom, start, end, length in kept:
        if current_lines and (current_total + length > chunk_size):
            write_chunk()
        current_lines.append(f"{chrom}\t{start}\t{end}")
        current_total += length

    if current_lines:
        write_chunk()  # write the final chunk

    # stderr report
    print(
        f"[split_genome_chunks] input={args.input} "
        f"kept_regions={len(kept)} longest={longest} "
        f"chunk_size={chunk_size} min_length={args.min_length} "
        f"output_dir={args.output_dir} "
        f"chunks_written={written_chunks}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()