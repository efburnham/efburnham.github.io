#!/usr/bin/env python3
"""Compile a Typst document to PDF using the typst Python package (typst-py).
Usage: typst_compile.py <input.typ> <output.pdf>
"""
import sys
import pathlib


def main():
    if len(sys.argv) < 3:
        print("Usage: typst_compile.py <input.typ> <output.pdf>", file=sys.stderr)
        sys.exit(1)

    try:
        import typst
    except ImportError:
        print(
            "typst Python package not found. Install via: pip install typst",
            file=sys.stderr,
        )
        sys.exit(1)

    input_path = pathlib.Path(sys.argv[1]).resolve()
    output_path = pathlib.Path(sys.argv[2]).resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # compile() finds yaml("cv_data.yml") relative to the input file's directory
    pdf_bytes = typst.compile(str(input_path))
    output_path.write_bytes(pdf_bytes)
    print(f"Compiled {input_path} -> {output_path}")


if __name__ == "__main__":
    main()
