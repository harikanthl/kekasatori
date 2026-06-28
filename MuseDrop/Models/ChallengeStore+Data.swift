//
//  ChallengeStore+Data.swift
//  MuseDrop
//
//  Learn — "Data wrangling" track. Hands-on data cleaning / preprocessing with
//  pandas, the unglamorous 80% of real ML work. Each lesson's `setup` generates
//  a small, seeded messy dataset in the container (offline, reproducible) and
//  the hidden `test` asserts on the cleaned result (exit 0 = pass), reusing the
//  existing Learn run/check engine. Runs in a light pandas+numpy image.
//
//  Modules 1–6 (load/inspect, missing, types, duplicates, outliers, encoding &
//  scaling). The bundled-dataset capstone and the optional Kaggle integration
//  land in later slices.
//

import Foundation

extension ChallengeStore {
    /// Light pandas + numpy image (runs as root, writes the mounted workdir).
    static let dataImage = "amancevice/pandas:latest"

    static let dataModules: [String] = [
        "D1 · Load & Inspect",
        "D2 · Missing Data",
        "D3 · Types & Parsing",
        "D4 · Duplicates & Consistency",
        "D5 · Outliers",
        "D6 · Encoding & Scaling",
        "D7 · Capstone",
        "D8 · Real data (Kaggle)"
    ]

    static let dataCleaning: [Challenge] = [

        // MARK: D1 · Load & Inspect

        Challenge(
            id: "data-read-csv", title: "Read a CSV", module: "D1 · Load & Inspect",
            order: 1, difficulty: .easy,
            prompt: """
            Load **data.csv** and implement `dims(path)` returning `(rows, cols)` \
            — the row and column counts. Use `pd.read_csv` and `.shape`.
            """,
            starter: """
            import pandas as pd

            def dims(path):
                # TODO: read the CSV and return (n_rows, n_cols)
                return (0, 0)
            """,
            test: """
            r, c = dims("data.csv")
            assert (r, c) == (3, 3), f"expected (3, 3), got {(r, c)}"
            print("All tests passed")
            """,
            image: dataImage,
            setup: """
            import pandas as pd
            pd.DataFrame({
                "name": ["Alice", "Bob", "Cara"],
                "age": [25, 30, 28],
                "city": ["NYC", "LA", "SF"],
            }).to_csv("data.csv", index=False)
            """),

        Challenge(
            id: "data-missing-counts", title: "Profile missing values", module: "D1 · Load & Inspect",
            order: 2, difficulty: .easy,
            prompt: """
            Implement `missing_counts(path)` returning a dict mapping each column \
            name to its number of missing values. (Hint: `df.isna().sum()` gives \
            per-column counts; turn it into a dict.)
            """,
            starter: """
            import pandas as pd

            def missing_counts(path):
                df = pd.read_csv(path)
                # TODO: return {column: n_missing}
                return {}
            """,
            test: """
            m = missing_counts("data.csv")
            assert m == {"age": 1, "city": 1}, f"got {m}"
            print("All tests passed")
            """,
            image: dataImage,
            setup: """
            import pandas as pd, numpy as np
            pd.DataFrame({
                "age": [25, np.nan, 35, 40],
                "city": ["NYC", "LA", None, "SF"],
            }).to_csv("data.csv", index=False)
            """),

        // MARK: D2 · Missing Data

        Challenge(
            id: "data-drop-missing", title: "Drop incomplete rows", module: "D2 · Missing Data",
            order: 1, difficulty: .easy,
            prompt: """
            Implement `drop_missing(df)` that returns the DataFrame with every row \
            containing a missing value removed. Use `dropna`.
            """,
            starter: """
            import pandas as pd

            def drop_missing(df):
                # TODO: drop rows with any NaN
                return df
            """,
            test: """
            df = pd.read_csv("data.csv")
            out = drop_missing(df)
            assert out.isna().sum().sum() == 0, "rows with missing values remain"
            assert len(out) == 3, f"expected 3 complete rows, got {len(out)}"
            print("All tests passed")
            """,
            image: dataImage,
            setup: """
            import pandas as pd, numpy as np
            pd.DataFrame({
                "age": [25, np.nan, 35, 40, 28],
                "salary": [50000, 60000, np.nan, 80000, 90000],
            }).to_csv("data.csv", index=False)
            """),

        Challenge(
            id: "data-impute", title: "Impute the gaps", module: "D2 · Missing Data",
            order: 2, difficulty: .medium,
            prompt: """
            Implement `impute(df)` so no missing values remain: fill the numeric \
            `age` with its **median** and the categorical `dept` with its **mode** \
            (most common value). Return the filled DataFrame.
            """,
            starter: """
            import pandas as pd

            def impute(df):
                df = df.copy()
                # TODO: age -> median, dept -> mode
                return df
            """,
            test: """
            df = pd.read_csv("data.csv")
            out = impute(df)
            assert out.isna().sum().sum() == 0, "missing values remain"
            assert out.loc[1, "age"] == 35.0, f"age median fill wrong: {out.loc[1, 'age']}"
            assert out.loc[3, "dept"] in ("eng", "sales")
            print("All tests passed")
            """,
            image: dataImage,
            setup: """
            import pandas as pd, numpy as np
            pd.DataFrame({
                "age": [25, np.nan, 35, 40, np.nan],
                "dept": ["eng", "sales", "eng", None, "sales"],
            }).to_csv("data.csv", index=False)
            """),

        // MARK: D3 · Types & Parsing

        Challenge(
            id: "data-fix-types", title: "Coerce to numbers", module: "D3 · Types & Parsing",
            order: 1, difficulty: .medium,
            prompt: """
            `price` loaded as text and contains a bad value (`thirty`). Implement \
            `fix_types(df)` that converts `price` to numeric, turning unparseable \
            values into NaN. Use `pd.to_numeric(..., errors="coerce")`.
            """,
            starter: """
            import pandas as pd

            def fix_types(df):
                df = df.copy()
                # TODO: coerce price to numeric
                return df
            """,
            test: """
            df = pd.read_csv("data.csv")
            out = fix_types(df)
            assert str(out["price"].dtype).startswith("float"), f"price dtype {out['price'].dtype}"
            assert out["price"].isna().sum() == 1, "the bad value should become NaN"
            print("All tests passed")
            """,
            image: dataImage,
            setup: """
            import pandas as pd
            pd.DataFrame({
                "price": ["10", "20", "thirty", "40"],
                "qty": [1, 2, 3, 4],
            }).to_csv("data.csv", index=False)
            """),

        Challenge(
            id: "data-parse-dates", title: "Parse dates", module: "D3 · Types & Parsing",
            order: 2, difficulty: .medium,
            prompt: """
            Implement `add_year(df)` that parses the `date` column to datetime and \
            adds an integer `year` column extracted from it. Use `pd.to_datetime` \
            and `.dt.year`.
            """,
            starter: """
            import pandas as pd

            def add_year(df):
                df = df.copy()
                # TODO: parse date, add df["year"]
                return df
            """,
            test: """
            df = pd.read_csv("data.csv")
            out = add_year(df)
            assert list(out["year"]) == [2021, 2022, 2023], f"got {list(out['year'])}"
            print("All tests passed")
            """,
            image: dataImage,
            setup: """
            import pandas as pd
            pd.DataFrame({
                "event": ["a", "b", "c"],
                "date": ["2021-01-15", "2022-06-30", "2023-12-01"],
            }).to_csv("data.csv", index=False)
            """),

        // MARK: D4 · Duplicates & Consistency

        Challenge(
            id: "data-dedupe", title: "Drop duplicates", module: "D4 · Duplicates & Consistency",
            order: 1, difficulty: .easy,
            prompt: """
            Implement `dedupe(df)` that removes exact duplicate rows, keeping the \
            first occurrence. Use `drop_duplicates`.
            """,
            starter: """
            import pandas as pd

            def dedupe(df):
                # TODO: remove duplicate rows
                return df
            """,
            test: """
            df = pd.read_csv("data.csv")
            out = dedupe(df)
            assert len(out) == 3, f"expected 3 unique rows, got {len(out)}"
            print("All tests passed")
            """,
            image: dataImage,
            setup: """
            import pandas as pd
            pd.DataFrame({
                "id": [1, 2, 2, 3, 3, 3],
                "val": ["a", "b", "b", "c", "c", "c"],
            }).to_csv("data.csv", index=False)
            """),

        Challenge(
            id: "data-normalize-categories", title: "Standardize labels", module: "D4 · Duplicates & Consistency",
            order: 2, difficulty: .medium,
            prompt: """
            The `country` column writes the same place many ways. Implement \
            `normalize(df)` so every variant of the United States becomes exactly \
            `US`. (Hint: lowercase and strip whitespace, then map the known \
            variants to "US".)
            """,
            starter: """
            import pandas as pd

            def normalize(df):
                df = df.copy()
                # TODO: map every variant to "US"
                return df
            """,
            test: """
            df = pd.read_csv("data.csv")
            out = normalize(df)
            assert set(out["country"]) == {"US"}, f"got {set(out['country'])}"
            print("All tests passed")
            """,
            image: dataImage,
            setup: """
            import pandas as pd
            pd.DataFrame({
                "country": ["USA", "U.S.", "us", "USA ", "United States"],
            }).to_csv("data.csv", index=False)
            """),

        // MARK: D5 · Outliers

        Challenge(
            id: "data-iqr-outliers", title: "Detect outliers (IQR)", module: "D5 · Outliers",
            order: 1, difficulty: .medium,
            prompt: """
            Implement `outlier_count(df, col)` returning how many values in `col` \
            are outliers by the **IQR rule**: below Q1 - 1.5·IQR or above \
            Q3 + 1.5·IQR, where IQR = Q3 - Q1. Use `Series.quantile`.
            """,
            starter: """
            import pandas as pd

            def outlier_count(df, col):
                # TODO: Q1, Q3, IQR; count values outside the fences
                return 0
            """,
            test: """
            df = pd.read_csv("data.csv")
            assert outlier_count(df, "x") == 1, f"got {outlier_count(df, 'x')}"
            print("All tests passed")
            """,
            image: dataImage,
            setup: """
            import pandas as pd
            pd.DataFrame({"x": [10, 12, 11, 13, 12, 11, 200]}).to_csv("data.csv", index=False)
            """),

        Challenge(
            id: "data-cap-outliers", title: "Cap outliers (winsorize)", module: "D5 · Outliers",
            order: 2, difficulty: .medium,
            prompt: """
            Implement `cap(df, col)` that clips values in `col` to the IQR fences \
            [Q1 - 1.5·IQR, Q3 + 1.5·IQR] (winsorizing). Use `Series.clip`. Return \
            the modified DataFrame.
            """,
            starter: """
            import pandas as pd

            def cap(df, col):
                df = df.copy()
                # TODO: clip col to the IQR fences
                return df
            """,
            test: """
            df = pd.read_csv("data.csv")
            out = cap(df, "x")
            q1 = df["x"].quantile(0.25); q3 = df["x"].quantile(0.75); iqr = q3 - q1
            hi = q3 + 1.5 * iqr
            assert out["x"].max() <= hi + 1e-9, f"max {out['x'].max()} exceeds fence {hi}"
            assert out["x"].max() < 200, "the outlier was not capped"
            print("All tests passed")
            """,
            image: dataImage,
            setup: """
            import pandas as pd
            pd.DataFrame({"x": [10, 12, 11, 13, 12, 11, 200]}).to_csv("data.csv", index=False)
            """),

        // MARK: D6 · Encoding & Scaling

        Challenge(
            id: "data-one-hot", title: "One-hot encode", module: "D6 · Encoding & Scaling",
            order: 1, difficulty: .medium,
            prompt: """
            Implement `one_hot(df)` that one-hot encodes the `color` column into \
            0/1 (or true/false) indicator columns and drops the original. Keep the \
            numeric `n` column. Use `pd.get_dummies`.
            """,
            starter: """
            import pandas as pd

            def one_hot(df):
                # TODO: one-hot encode "color"
                return df
            """,
            test: """
            df = pd.read_csv("data.csv")
            out = one_hot(df)
            assert "color" not in out.columns, "drop the original color column"
            for c in ["red", "green", "blue"]:
                assert any(str(col).endswith(c) for col in out.columns), f"missing indicator for {c}"
            assert "n" in out.columns, "keep the numeric column"
            print("All tests passed")
            """,
            image: dataImage,
            setup: """
            import pandas as pd
            pd.DataFrame({
                "color": ["red", "green", "blue", "red"],
                "n": [1, 2, 3, 4],
            }).to_csv("data.csv", index=False)
            """),

        Challenge(
            id: "data-scale", title: "Scale & standardize", module: "D6 · Encoding & Scaling",
            order: 2, difficulty: .medium,
            prompt: """
            Implement two transforms on a Series: `minmax(s)` scaling to [0, 1] as \
            (s - min) / (max - min), and `standardize(s)` to zero mean and unit \
            standard deviation as (s - mean) / std.
            """,
            starter: """
            import pandas as pd

            def minmax(s):
                # TODO: scale to [0, 1]
                return s

            def standardize(s):
                # TODO: zero mean, unit std
                return s
            """,
            test: """
            s = pd.read_csv("data.csv")["x"]
            mm = minmax(s)
            assert abs(mm.min()) < 1e-9 and abs(mm.max() - 1.0) < 1e-9, "minmax not in [0,1]"
            st = standardize(s)
            assert abs(st.mean()) < 1e-9, "standardized mean should be ~0"
            assert abs(st.std() - 1.0) < 1e-6, "standardized std should be ~1"
            print("All tests passed")
            """,
            image: dataImage,
            setup: """
            import pandas as pd
            pd.DataFrame({"x": [10.0, 20.0, 30.0, 40.0, 50.0]}).to_csv("data.csv", index=False)
            """),

        // MARK: D7 · Capstone (real bundled dataset)

        Challenge(
            id: "data-capstone-nyc", title: "Capstone: clean NYC inspections", module: "D7 · Capstone",
            order: 1, difficulty: .hard,
            prompt: """
            **nyc_inspections.csv** is a real, messy slice of New York City's \
            restaurant inspection results (one row per violation). Implement \
            `clean(df)` returning a tidy, one-row-per-restaurant table you could \
            model on:

            1. Parse `inspection_date` to datetime and drop the "never inspected" \
            placeholder rows (year 1900).
            2. Drop rows whose `boro` is the invalid value `"0"`.
            3. Keep only real letter grades: `A`, `B`, or `C` (drop special codes \
            like N/Z/P and blanks).
            4. Make `score` numeric and drop rows where it is missing.
            5. Keep one row per restaurant (`camis`): the most recent inspection.

            Return the cleaned DataFrame.
            """,
            starter: """
            import pandas as pd

            def clean(df):
                df = df.copy()
                # 1. parse inspection_date; drop year-1900 placeholders
                # 2. drop boro == "0"
                # 3. keep grade in {A, B, C}
                # 4. score -> numeric; drop missing
                # 5. one row per camis (most recent inspection)
                return df
            """,
            test: """
            df = pd.read_csv("nyc_inspections.csv")
            out = clean(df)
            assert len(out) > 0, "no rows left"
            assert str(out["inspection_date"].dtype).startswith("datetime"), f"date dtype {out['inspection_date'].dtype}"
            assert out["inspection_date"].dt.year.min() > 1900, "1900 placeholder rows remain"
            valid_boro = {"Manhattan", "Brooklyn", "Queens", "Bronx", "Staten Island"}
            assert set(out["boro"].astype(str)).issubset(valid_boro), f"bad boros: {set(out['boro']) - valid_boro}"
            assert set(out["grade"]).issubset({"A", "B", "C"}), f"bad grades: {set(out['grade'])}"
            assert out["camis"].is_unique, "more than one row per restaurant"
            assert out["score"].isna().sum() == 0, "missing scores remain"
            assert pd.api.types.is_numeric_dtype(out["score"]), "score not numeric"
            print("All tests passed")
            """,
            reference: "NYC Open Data · DOHMH",
            image: dataImage,
            dataFiles: ["nyc_inspections.csv"]),

        // MARK: D8 · Real data (Kaggle) — bring-your-own-token

        Challenge(
            id: "data-kaggle-adult", title: "Pull a dataset from Kaggle", module: "D8 · Real data (Kaggle)",
            order: 1, difficulty: .medium,
            prompt: """
            Real datasets usually live behind an API. This lesson downloads the \
            **UCI Adult Census Income** dataset straight from Kaggle, then cleans \
            its missing-value placeholders.

            First add your Kaggle token in **Settings → Learn data (Kaggle)** \
            (create one at kaggle.com → Settings → API). The lesson then downloads \
            the data to `data.csv` for you.

            Implement `prepare(path)` that loads `data.csv` and treats the dataset's \
            `?` entries (with any surrounding whitespace) as missing values (NaN). \
            Return the DataFrame.
            """,
            starter: """
            import pandas as pd
            import numpy as np

            def prepare(path):
                df = pd.read_csv(path)
                # TODO: treat "?" (any surrounding whitespace) as missing -> NaN
                return df
            """,
            test: """
            df = prepare("data.csv")
            assert len(df) > 30000, f"expected the full Adult Census dataset, got {len(df)} rows"
            assert "age" in df.columns, "expected an 'age' column"
            assert df.isna().sum().sum() > 0, "the '?' placeholders should become NaN"
            print("All tests passed")
            """,
            reference: "Kaggle · uciml/adult-census-income",
            image: dataImage,
            setup: """
            import os, sys, subprocess, glob
            if not os.environ.get("KAGGLE_KEY"):
                print("No Kaggle token found.")
                print("Add your Kaggle username + key in Settings > Learn data (Kaggle), then run again.")
                sys.exit(1)
            subprocess.run([sys.executable, "-m", "pip", "install", "-q", "kagglehub"], check=True)
            import kagglehub, pandas as pd
            path = kagglehub.dataset_download("uciml/adult-census-income")
            csv = sorted(glob.glob(os.path.join(path, "*.csv")))[0]
            pd.read_csv(csv).to_csv("data.csv", index=False)
            print("Downloaded", os.path.basename(csv))
            """,
            needsKaggle: true)
    ]

    static let dataTheory: [String: String] = [
        "data-read-csv": """
        ## Loading and inspecting data
        Real work starts by reading a file into a **DataFrame** (`pd.read_csv`).
        Before changing anything, look at it: `df.shape` gives `(rows, columns)`,
        `df.head()` previews rows, `df.dtypes` shows each column's type, and
        `df.info()` summarizes both plus non-null counts.
        """,
        "data-missing-counts": """
        ## Where are the holes?
        Missing values show up as `NaN` (or `None`). `df.isna()` returns a
        true/false mask the same shape as the data; summing it per column with
        `.sum()` tells you how many gaps each column has. Knowing the missingness
        per column is the first decision point: drop, fill, or leave.
        """,
        "data-drop-missing": """
        ## Dropping vs keeping
        `df.dropna()` removes any row with at least one missing value (use
        `axis=1` to drop columns instead). It is the simplest fix, and the right
        one when missingness is rare and random. When dropping would throw away
        too much data, impute instead.
        """,
        "data-impute": """
        ## Imputation
        Filling gaps keeps your rows. For numeric columns the **median** is a
        robust default (less sensitive to outliers than the mean). For categorical
        columns use the **mode** (most frequent value). `df[col].fillna(value)`
        does the fill; `df[col].median()` / `df[col].mode()[0]` give the values.
        """,
        "data-fix-types": """
        ## Types and bad values
        A column read as text (`object`) can't be averaged or compared
        numerically. `pd.to_numeric(s, errors="coerce")` converts what it can and
        turns the rest into `NaN`, so a stray "thirty" becomes a missing value you
        can then impute. The same idea applies to booleans and categories.
        """,
        "data-parse-dates": """
        ## Dates are not strings
        `pd.to_datetime` turns date-like text into real timestamps, unlocking the
        `.dt` accessor: `.dt.year`, `.dt.month`, `.dt.dayofweek`, and time
        arithmetic. Extracting parts of a date into their own columns is a common
        first feature-engineering step.
        """,
        "data-dedupe": """
        ## Duplicates
        Duplicate rows bias counts and leak between train/test splits.
        `df.drop_duplicates()` keeps the first occurrence of each repeated row;
        pass `subset=[...]` to dedupe on specific key columns and `keep="last"` to
        keep the most recent instead.
        """,
        "data-normalize-categories": """
        ## Consistent categories
        "USA", "U.S.", "us", and "United States" are one value written four ways,
        and models treat them as four. Normalize first (lowercase, strip
        whitespace) then **map** the known variants to one canonical label so each
        real category is a single token.
        """,
        "data-iqr-outliers": """
        ## Outliers: the IQR rule
        The interquartile range IQR = Q3 - Q1 (the middle 50% of the data). A
        common rule flags points below Q1 - 1.5·IQR or above Q3 + 1.5·IQR as
        outliers. `s.quantile(0.25)` and `s.quantile(0.75)` give the quartiles.
        It is resistant to the very extremes it is trying to find.
        """,
        "data-cap-outliers": """
        ## Capping (winsorizing)
        Rather than delete outliers you can **clip** them to the fences, pulling
        extreme values in to the boundary while keeping the row. `s.clip(lower,
        upper)` does it. Capping preserves sample size and is gentler than removal
        when extremes are real but distorting.
        """,
        "data-one-hot": """
        ## One-hot encoding
        Most models need numbers, not category strings. One-hot encoding turns a
        categorical column into one 0/1 indicator column per category.
        `pd.get_dummies(df, columns=["color"])` creates `color_red`,
        `color_green`, ... and drops the original. Use it for unordered
        categories; for ordered ones, map to ranks instead.
        """,
        "data-kaggle-adult": """
        ## Getting real data: the Kaggle API
        Most datasets live behind an API, not a download button. Kaggle gives you
        a token (kaggle.com → Settings → API → Create New Token) with a username
        and key; tools read them from `KAGGLE_USERNAME` / `KAGGLE_KEY`. This app
        injects yours from Settings into the container, and `kagglehub` fetches
        and caches the dataset. The Adult Census set marks missing values with a
        literal `?`, so a first cleaning step is turning those into real `NaN`
        (`df.replace`/mask, watching for stray whitespace). Your token stays on
        your Mac and only goes to the container for this lesson.
        """,
        "data-capstone-nyc": """
        ## A real cleaning pipeline
        Production data is rarely one fix. This NYC inspections extract has
        sentinel dates (year 1900 = never inspected), an invalid borough code
        ("0"), special grade codes mixed in with real A/B/C grades, missing
        scores, and many rows per restaurant (one per violation). A model-ready
        table needs all of these handled together and usually collapsed to one
        row per entity: chain the filters, coerce the types, then deduplicate by
        keeping the most recent record per key (`camis`).
        """,
        "data-scale": """
        ## Scaling features
        Features on different scales (age 0-100 vs income 0-1e6) distort
        distance- and gradient-based models. **Min-max** rescales to [0, 1]:
        (x - min) / (max - min). **Standardization** centers and rescales to zero
        mean and unit variance: (x - mean) / std. Fit the statistics on training
        data only, then apply the same transform to test data.
        """
    ]
}
