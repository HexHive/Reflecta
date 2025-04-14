#!/usr/bin/env python3

import sys
import statistics
import argparse

import numpy as np
import polars as pl

from os import path
from glob import glob
from tqdm import tqdm


def profdata_over_time(tmpdir):
    cov = {}
    for c in tqdm(glob(path.join(tmpdir, "*.csv"))):
        try:
            timestamp = float(path.basename(c)[:-4])
            data = pl.read_csv(c, has_header=False).to_numpy().transpose()[0]
            cov[timestamp] = data
        except:
            pass

    if len(cov) == 0:
        return

    length = statistics.mode([len(c) for c in cov.values()])

    # filter out all that are not the most common length
    # sort by timestamp
    cov = {k: v for k, v in cov.items() if len(v) == length}
    cov = dict(sorted(cov.items(), key=lambda item: item[0]))

    mat = np.array(list(cov.values()))
    cum = np.cumsum(mat, axis=0)
    acc = np.count_nonzero(cum, axis=1)

    print(cum)
    print(acc)


def sancov_over_time(df):
    acc, ts, cs = set(), [], []
    for t, c in df.group_by("timestamp").agg(pl.col("pc")).sort("timestamp").iter_rows():
        acc |= set(c)
        ts.append(t)
        cs.append(len(acc))

    return pl.DataFrame({"timestamp": ts, "coverage": cs})


def merge(tmpdir):
    acc = pl.DataFrame()
    for c in tqdm(glob(path.join(tmpdir, "*.sancov.csv"))):
        try:
            timestamp = float(path.basename(c).rstrip(".sancov.csv"))
            df = (
                pl.read_csv(c, has_header=False)
                .select(
                    [
                        pl.lit(timestamp).alias("timestamp"),
                        pl.col("column_1").str.slice(2).str.to_integer(base=16).alias("pc"),
                    ]
                )
            )
            acc.vstack(df, in_place=True)
        except Exception as e:
            tqdm.write(str(e), file=sys.stderr)

    if len(acc) == 0:
        print("failed to parse any coverage files")
        return

    acc.rechunk()
    acc.write_csv(path.join(tmpdir, "coverage.csv"))

    overtime = sancov_over_time(acc)
    overtime.write_csv(path.join(tmpdir, "coverage_over_time.csv"))

    return acc


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Merge coverage data")
    # parser.add_argument("pattern", type=str, help="pattern to match")
    parser.add_argument("tmpdir", type=str, help="directory containing coverage output")
    args = parser.parse_args()

    if args.tmpdir:
        merge(args.tmpdir)
