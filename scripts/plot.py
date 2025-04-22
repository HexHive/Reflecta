#!/usr/bin/env python3

import re
import argparse


import polars as pl
import seaborn as sns
import numpy as np
import matplotlib.pyplot as plt
import plotly.express as px
import plotly

from os import path
from glob import glob

import matplotlib

plt.rcParams['pdf.fonttype'] = 42
plt.rcParams['ps.fonttype'] = 42
plt.rcParams.update({'font.size': 11})

benchdir = "/workspaces/FuzzIR/bench"

def parse_bench_config(rundir):
    s = path.basename(rundir.rstrip("/")).split(",")
    d = {}
    for e in s:
        k, *v = e.split(":")
        d[k] = ":".join(v)

    return d


def load_coverage_over_time_normalized(csv):
    df = pl.read_csv(csv)

    assert "timestamp" in df.columns and "coverage" in df.columns

    if len(df) == 0:
        print("empty coverage file")
        return

    config = parse_bench_config(path.dirname(path.dirname(csv)))
    fuzzer = config["fuzzer"].split("-")[0]
    target = config["target"].split("-")[0]

    # normalize timestamps to minutes and start at 0
    xp = df.get_column("timestamp").to_numpy()
    xp = (xp - xp[0]) / 60
    fp = df.get_column("coverage").to_numpy().copy()
    fp[0] = 0

    x = np.arange(0, 24 * 60, 10)
    y = np.interp(x, xp, fp)

    df = pl.DataFrame({"time": x, "coverage": y, "fuzzer": fuzzer, "target": target})

    return df


def plot_coverage_over_time(df, output=None):
    for c in ["time", "coverage", "fuzzer", "target"]:
        assert c in df.columns

    df = df.sort("fuzzer")

    target = df.get_column("target").to_list()[0]

    title_map = {"micropython": "MicroPython", "cpython": "Python", "ruby": "Ruby", "mruby": "MRuby", "php": "PHP", "v8": "V8"}
    legend_map = {"trifuzz": "Reflecta", "reflecta": "Reflecta", "reflecta_ext": "Reflecta+Ext", "reflecta_sem": "Reflecta-Sem", "nautilus": "Nautilus", "polyglot": "PolyGlot", "polyglot_corpus": "PolyGlot+C", "fuzzilli":"Fuzzilli"}
    palette= {"aflplusplus":"orange", "trifuzz": "tab:blue",  "reflecta": "tab:blue", "reflecta_ext": "tab:purple", "reflecta_sem": "tab:cyan", "nautilus": "tab:orange", "polyglot": "tab:green", "fuzzilli": "tab:red", "polyglot_corpus": "tab:olive"}

    ax = sns.lineplot(
        data=df.to_dict(),
        x="time",
        y="coverage",
        hue="fuzzer",
        errorbar="ci",
        err_style="band",
        # palette=palette,
    )
    ax.get_yaxis().set_major_formatter(matplotlib.ticker.FuncFormatter(lambda x, _: f"{int(x // 1000)}k"))
    ax.legend_.set_title(None)

    # for t in ax.legend(fontsize="8").get_texts():
    #     t.set_text(legend_map[t.get_text()])

    # ax.set_title(title_map[target])
    ax.set_xlabel("Time (minutes)")
    ax.set_ylabel("Coverage (edges)")

    plt.savefig(output if output else target + ".pdf", bbox_inches="tight")


def plot_multiple_over_time(pattern, output=None):
    acc = pl.DataFrame()
    for d in glob(path.join(benchdir, "bench:*")):
        csv = path.join(d, "cov", "coverage_over_time.csv")
        if (re.search(pattern, d) or pattern in d) and path.exists(csv):
            print(path.basename(d))
            try:
                df = load_coverage_over_time_normalized(csv)
                acc = acc.vstack(df)
            except Exception as e:
                print(e)

    if len(acc) == 0:
        print("no coverage files found")
        return

    plot_coverage_over_time(acc, output=output)


def join_coverage_symbol(coverage, symbol):
    cov = pl.read_csv(coverage)
    sym = pl.read_csv(
        symbol, has_header=False, new_columns=["file", "function", "pc", "line"]
    ).with_columns(pl.col("pc").str.to_integer(base=16).cast(pl.Int64))

    df = cov.select(
        pl.col("pc"),
        pl.lit(True).alias("covered"),
    ).unique()

    df = sym.join(df, on="pc", how="left").with_columns(
        pl.col("covered").fill_null(False).cast(pl.Int64)
    )
    df = df.with_columns(
        pl.col("file").str.split("/").list.get(-1),
        pl.col("file").str.split("/").list.get(-2).alias("dir"),
    )

    return df

def plot_coverage_treemap(coverage, symbol, output=None):
    df = join_coverage_symbol(coverage, symbol)
    df = df.group_by(["dir", "file", "function"]).agg(
        [
            (pl.col("covered") * 100).mean().alias("Covered Percentage (%)"),
            pl.count("covered").alias("edges"),
        ]
    )

    fig = px.treemap(
        df.to_dict(),
        path=["dir", "file", "function"],
        values="edges",
        color="Covered Percentage (%)",
        color_continuous_scale="RdYlGn",
        color_continuous_midpoint=50,
        maxdepth=2,
        width=1500,
        height=900,
    )
    fig.update_layout(
        uniformtext=dict(minsize=20),
        margin=dict(t=0, l=0, r=0, b=0),
        coloraxis_colorbar_title_side="right",
    )
    fig.write_html(output if output else "treemap.html")
    # plotly.io.write_image(fig, 'treemap.png', format='png')



def plot_coverage_treemap_diff(coverage1, coverage2, symbol, output=None):
    df1 = join_coverage_symbol(coverage1, symbol)
    df2 = join_coverage_symbol(coverage2, symbol)

    df = df1.join(df2, on=["dir", "file", "function", "pc"], how="outer").with_columns((pl.col("covered") - pl.col("covered_right")).alias("diff")).drop(["covered", "covered_right"])
    df = df.group_by(["dir", "file", "function"]).agg(
        [
            (pl.col("diff") * 100).mean().alias("Coverage Differential (%)"),
            pl.count("diff").alias("edges"),
        ]
    )

    fig = px.treemap(
        df.to_dict(),
        path=["dir", "file"],
        values="edges",
        color="Coverage Differential (%)",
        color_continuous_scale="RdYlGn",
        color_continuous_midpoint=0,
        maxdepth=2,
        title=f"",
        width=1000,
        height=600,
    )
    fig.update_layout(
        uniformtext=dict(minsize=20),
        margin=dict(t=0, l=0, r=0, b=0),
        coloraxis_colorbar_title_side="right",
    )
    fig.write_html(output if output else "treemap-diff.html")

    plotly.io.write_image(fig, "treemap-diff.pdf", format='pdf')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Coverage plotting utility")
    parser.add_argument("--benchdir", required=False, type=str, help="bench folder prefix")
    parser.add_argument("--overtime", required=False, type=str, help="plot coverage over time")
    parser.add_argument("--treemap", required=False, type=str, help="plot hierarchical coverage treemap")
    parser.add_argument("--treemap-diff", required=False, nargs=2, type=str, help="plot coverage treemap diff")
    parser.add_argument("--symbol", required=False, type=str, help="symbol file")
    parser.add_argument("--output", default=None, type=str, help="output file")

    args = parser.parse_args()

    if args.benchdir:
        if path.exists(args.benchdir):
            benchdir = args.benchdir
        else:
            raise Exception(f"{args.benchdir} does not exist")
    if args.overtime:
        plot_multiple_over_time(args.overtime, output=args.output)
    elif args.treemap:
        if not args.symbol:
            raise Exception("symbol file required")
        plot_coverage_treemap(args.treemap, args.symbol, output=args.output)
    elif args.treemap_diff:
        if not args.symbol:
            raise Exception("symbol file required")
        plot_coverage_treemap_diff(args.treemap_diff[0], args.treemap_diff[1], args.symbol, output=args.output)
