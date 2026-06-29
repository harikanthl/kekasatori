//
//  Challenge.swift
//  MuseDrop
//
//  Learn-by-implementing challenges (deep-ml / Karpathy / Ng style): a prompt,
//  starter, and a hidden test that runs in a container (exit 0 = pass).
//  Foundations are pure-Python (no deps, instant); from attention on, PyTorch.
//  Organized into an ordered syllabus — see docs/learn-syllabus.md. Tests are
//  verified against reference implementations / standard math with known values.
//

import Foundation

struct Challenge: Identifiable, Codable, Equatable {
    enum Difficulty: String, Codable, CaseIterable {
        case easy, medium, hard
        var label: String { rawValue.capitalized }
    }

    let id: String
    let title: String
    let module: String
    /// Order within the module.
    let order: Int
    let difficulty: Difficulty
    let prompt: String
    let starter: String
    let test: String
    /// A reference (course/repo) the lesson follows.
    var reference: String? = nil
    /// Container image. Pure-Python uses slim; torch lessons use a PyTorch image.
    var image: String = "python:3.12-slim"
    /// Python by default; Terminal lessons use bash.
    var language: CodeRunSpec.Language = .python
    /// Optional setup run before the user code (e.g. create input files for a
    /// Terminal lesson). Empty for most challenges.
    var setup: String = ""
    /// Bundled data files (by name) copied into the workdir before running — for
    /// data lessons that ship a real dataset. Empty for generated-data lessons.
    var dataFiles: [String] = []
    /// When true, the user's Kaggle credentials (Keychain) are injected as
    /// KAGGLE_USERNAME / KAGGLE_KEY so the lesson can pull a real Kaggle dataset.
    var needsKaggle: Bool = false
    /// Concept/theory (markdown) shown in the Theory tab. Injected from
    /// ChallengeStore.theoryByID so the initializers above stay terse.
    var theory: String = ""

    /// setup (if any) + the user's code — what a plain "Run" executes. For
    /// Terminal lessons the setup stages input files so Run behaves like Check.
    func runScript(userCode: String) -> String {
        setup.isEmpty ? userCode : setup + "\n" + userCode
    }

    /// runScript + the hidden test, as one runnable script (exit 0 = pass).
    func checkScript(userCode: String) -> String {
        runScript(userCode: userCode) + "\n\n# ---- tests (hidden) ----\n" + test
    }
}

enum ChallengeStore {
    /// Modules in syllabus order.
    static let modules: [String] = [
        "0 · Terminal",
        "0 · Shell for ML",
        "1 · Foundations",
        "2 · Autograd & Backprop",
        "3 · Optimization & Training",
        "4 · Transformers",
        "5 · Build a GPT",
        "6 · Modern LLMs"
    ] + dataModules + rlModules

    private static let torchImage = "pytorch/pytorch:2.5.1-cpu"
    private static let shellImage = "ubuntu:24.04"

    static let all: [Challenge] = (terminal + shellML + foundations + autograd + optimization + transformers + buildGPT + modernLLMs + dataCleaning + rl).map {
        var challenge = $0
        challenge.theory = theoryByID[$0.id] ?? dataTheory[$0.id] ?? rlTheory[$0.id] ?? ""
        return challenge
    }

    // MARK: - Categories (Learn landing)

    /// A top-level track shown on the Learn landing grid. Owns an ordered list of
    /// modules; membership and progress are derived from `module`, so the whole
    /// taxonomy is this one editable table.
    struct LearnCategory: Identifiable {
        let id: String
        let name: String
        let subtitle: String
        let symbol: String
        let modules: [String]

        /// Challenges in this category, ordered by module then in-module order.
        var challenges: [Challenge] {
            ChallengeStore.all
                .filter { modules.contains($0.module) }
                .sorted { lhs, rhs in
                    let li = modules.firstIndex(of: lhs.module) ?? 0
                    let ri = modules.firstIndex(of: rhs.module) ?? 0
                    return li == ri ? lhs.order < rhs.order : li < ri
                }
        }
    }

    static let categories: [LearnCategory] = [
        LearnCategory(
            id: "terminal", name: "Terminal basics",
            subtitle: "The command line and shell scripting you actually use to drive ML work.",
            symbol: "terminal", modules: ["0 · Terminal", "0 · Shell for ML"]),
        LearnCategory(
            id: "data-cleaning", name: "Data wrangling",
            subtitle: "Clean and prep real, messy data with pandas: the unglamorous 80% of ML.",
            symbol: "tablecells", modules: dataModules),
        LearnCategory(
            id: "ml-foundations", name: "ML foundations",
            subtitle: "The math building blocks — activations, a neuron, losses — by hand.",
            symbol: "function", modules: ["1 · Foundations"]),
        LearnCategory(
            id: "dl-foundations", name: "DL foundations",
            subtitle: "Autograd, backprop, and the training loop — from scratch.",
            symbol: "point.3.connected.trianglepath.dotted",
            modules: ["2 · Autograd & Backprop", "3 · Optimization & Training"]),
        LearnCategory(
            id: "dl-advanced", name: "DL advanced",
            subtitle: "Transformers, attention, and a working GPT — in PyTorch.",
            symbol: "rectangle.3.group",
            modules: ["4 · Transformers", "5 · Build a GPT"]),
        LearnCategory(
            id: "modern-llms", name: "Modern LLMs",
            subtitle: "What today's models actually run — RoPE, RMSNorm, SwiGLU, GQA, KV cache — assembled into a Llama block.",
            symbol: "cpu", modules: ["6 · Modern LLMs"]),
        LearnCategory(
            id: "reinforcement-learning", name: "Reinforcement learning",
            subtitle: "From bandits to PPO and SAC — implement every core RL update by hand, following the RL Handbook.",
            symbol: "gamecontroller", modules: rlModules),
        LearnCategory(
            id: "papers", name: "Papers",
            subtitle: "Reproduce results from landmark papers. (Coming soon.)",
            symbol: "doc.text.magnifyingglass", modules: [])
    ]

    /// The short module name without its "N · " ordering prefix, for display
    /// inside a category (e.g. "0 · Shell for ML" → "Shell for ML").
    static func shortModuleName(_ module: String) -> String {
        module.components(separatedBy: " · ").last ?? module
    }

    // MARK: - Theory (concept for each lesson)

    static let theoryByID: [String: String] = [
        "echo-redirect": """
        ## The shell, stdout, and redirection
        A command prints to **standard output** (your screen by default). `echo`
        just writes its arguments to stdout. The **`>`** operator *redirects* that
        stream into a file instead — creating it, or **truncating** it if it
        already exists.

        `echo hello > out.txt` is the most basic way to put text on disk. This
        plumbing — commands as text filters, output rerouted with `>` — is the
        whole idea the rest of the shell builds on.
        """,
        "append": """
        ## `>` truncates, `>>` appends
        Both send stdout to a file, but `>` **replaces** the file's contents while
        **`>>`** adds to the **end**, leaving what's already there untouched. Reach
        for `>>` when you're accumulating — a growing log, building a file line by
        line, collecting results from a loop.

        The trap: using `>` inside a loop overwrites every iteration, so you keep
        only the last. `>>` is what you usually want there.
        """,
        "cp-file": """
        ## Files and copies
        `cp src dst` duplicates a file. The original stays; you get an independent
        copy you can edit without touching the source. Its siblings are **`mv`**
        (rename/move — no copy left behind) and **`rm`** (delete).

        These four — `cp`, `mv`, `rm`, plus `ls` to see them — are the verbs you'll
        use constantly to wrangle datasets, checkpoints, and configs.
        """,
        "head-lines": """
        ## Peeking at big files
        Datasets and logs are often too large to open whole. **`head`** prints the
        first lines (10 by default; `head -n 3` for three), **`tail`** prints the
        last — and `tail -f` *follows* a file as it grows, which is how you watch a
        training run's log live.

        A fast habit: `head` a new data file first to see its columns and format
        before writing any code against it.
        """,
        "wc-lines": """
        ## Counting
        **`wc`** counts lines, words, and bytes; `wc -l` gives just lines — a quick
        way to ask "how many rows in this dataset?". Feeding it **from** a file with
        `wc -l < file` (rather than `wc -l file`) keeps the filename out of the
        output, so you get a bare number you can use directly.

        This is the start of treating the shell as a calculator over text.
        """,
        "grep-filter": """
        ## Searching text with grep
        **`grep PATTERN file`** prints the lines that match — the workhorse for
        finding things in logs, configs, and code. `grep ERROR log.txt` pulls every
        error line; `grep -c` counts them, `grep -v` *inverts* to show the
        non-matches, `grep -i` ignores case.

        Combined with a pipe, grep becomes a filter stage: keep only the lines that
        matter, then do something with them.
        """,
        "pipe-sort-uniq": """
        ## Pipes: composing small tools
        The **pipe** `|` wires one command's stdout into the next's stdin, so tiny
        single-purpose tools compose into pipelines. The classic
        `sort | uniq` is the idiom for "distinct values": **`uniq` only collapses
        *adjacent* duplicates**, so you must `sort` first. Add `uniq -c` and you get
        counts — an instant histogram.

        This compose-small-pieces philosophy is the heart of the Unix shell.
        """,
        "for-loop": """
        ## Variables and loops
        The shell is a real programming language. A **variable** holds a value
        (`name=value`, read back as `$name`); a **`for`** loop repeats a body over a
        list of words: `for i in 1 2 3; do ...; done`.

        Loops turn one-off commands into batch operations — process every file in a
        folder, launch a sweep of runs, rename a hundred things at once. Always
        **quote** your expansions (`"file$i.txt"`) so spaces don't split them.
        """,
        "env-vars": """
        ## Configuring runs with the environment
        **Environment variables** are key=value pairs the shell hands to every
        program it launches. `NAME=value` sets one; `$NAME` reads it; `export`
        makes it visible to child processes. ML tooling is configured this way:
        **`CUDA_VISIBLE_DEVICES=0`** picks a GPU, `HF_HOME` moves the model cache,
        `PYTORCH_CUDA_ALLOC_CONF` tunes the allocator.

        Setting a var inline — `CUDA_VISIBLE_DEVICES=0 python train.py` — scopes it
        to just that command, which is the tidy way to pin one run to one GPU.
        """,
        "cmd-subst": """
        ## Command substitution
        **`$(command)`** runs a command and substitutes its **output** right into
        the line — the glue that lets one tool feed another's value into a variable
        or a message: `N=$(wc -l < data.csv)`. Pair it with arithmetic **`$(( ))`**
        for integer math (`$(( N - 1 ))` to drop a header row).

        This is how scripts compute things on the fly — dataset sizes, timestamps
        for run names, step counts — instead of hard-coding them.
        """,
        "resume-if": """
        ## Branching on state
        Real pipelines make decisions: **`if [ -f model.pt ]; then ... else ... fi`**.
        The `[ ... ]` test checks a condition — `-f` for a file existing, `-d` for a
        directory, `-z` for an empty string — and the exit status picks the branch.

        The classic use is **resume-or-restart**: if a checkpoint is on disk, load
        it and continue; otherwise start fresh. The same pattern guards expensive
        steps ("skip download if the data's already here").
        """,
        "awk-column": """
        ## awk — columns and rows
        **awk** processes text row by row, splitting each into fields (`$1`, `$2`,
        … `$NF` = last). `-F,` sets the separator to a comma for CSVs, and a
        pattern like `NR>1` skips the header row. `awk -F, 'NR>1 {print $2}'` pulls
        one column out of a metrics file.

        It's the right tool the moment "grep a line" turns into "grab a specific
        field" — extracting the loss column, summing a row, filtering by a
        threshold.
        """,
        "parse-log": """
        ## Mining a training log
        Training spews lines like `epoch 3 loss 0.12`. To pull a number out you
        compose filters: `grep` to keep the relevant lines, **`awk '{print $NF}'`**
        to take the last field, `tail -1` for the final one or `sort -n | head -1`
        for the best.

        `$NF` (number of fields) means "the last column" regardless of how many
        there are — robust when log formats wobble. This pipeline is how you scrape
        a final/best metric without opening Python.
        """,
        "sed-config": """
        ## sed — stream editing
        **sed** edits text as it streams past. Its workhorse is substitution:
        **`s/old/new/`** replaces the first match per line (`s/old/new/g` for all).
        `sed 's/lr=0.1/lr=0.01/' config.txt` rewrites a hyperparameter;
        **`sed -i`** edits the file in place.

        It's how scripts template configs and sweep hyperparameters — programmatically
        flip a value, launch a run, repeat — no editor, no Python.
        """,
        "find-ckpt": """
        ## find — search the file tree
        **find** walks a directory tree and matches files by name, type, age, or
        size: `find runs -name '*.pt'` lists every checkpoint under `runs/`. Add
        `-newer`, `-size`, or `-type d`; pipe to `sort` for stable order or to
        `xargs` to act on each hit.

        Indispensable once runs sprawl into nested folders — locating the latest
        checkpoint, every config, or all the logs to clean up.
        """,
        "loop-shards": """
        ## Looping over files
        Datasets arrive in **shards** and runs produce many files, so you script
        the repetition: `for f in data/*.txt; do ...; done`. The glob expands in
        sorted order, and **quoting** `"$f"` keeps paths with spaces intact.

        This turns a one-file command into a batch job — count every shard,
        preprocess each, validate them all. For independent work, `xargs -P` or
        GNU `parallel` runs the iterations concurrently.
        """,
        "archive-run": """
        ## tar — bundle and compress
        **`tar -czf run.tar.gz outputs/`** packs a directory into a single
        gzipped archive: **c**reate, g**z**ip, **f**ile. `-t` lists its contents,
        `-x` extracts. One file is far easier to move than a tree of thousands.

        It's the standard way to snapshot a finished run — logs, configs, weights —
        to ship to a colleague, upload to storage, or stash before you reuse the
        scratch directory.
        """,
        "sigmoid": """
        ## Activation functions
        A neuron computes a **linear** combination of its inputs — but a stack of
        linear layers is still linear. **Activations** add the nonlinearity that
        lets networks model curves, not just lines.

        ## Sigmoid
        σ(x) = 1 / (1 + e⁻ˣ) squashes any real number into **(0, 1)**, so it reads
        as a probability. Its derivative is a tidy **σ(x)·(1 − σ(x))**.

        It **saturates**: for large |x| the slope → 0, so gradients vanish and deep
        nets train slowly. That's why hidden layers mostly use ReLU today, and
        sigmoid lives on at the output of binary classifiers and in gating units.
        """,
        "relu": """
        ## ReLU — the default hidden activation
        ReLU(x) = max(0, x). It's cheap (a threshold), and for x > 0 the gradient
        is exactly **1** — no saturation, so signals and gradients pass cleanly
        through deep stacks. That single property is most of why deep learning
        started working at scale.

        Its outputs are **sparse** (many exact zeros). The catch is the **dying
        ReLU**: a unit stuck at ≤ 0 gets zero gradient forever — which motivates
        Leaky ReLU, GELU, and friends.
        """,
        "softmax": """
        ## From scores to a distribution
        Softmax turns a vector of **logits** into a probability distribution:
        each output is `exp(xᵢ) / Σ exp(xⱼ)`, so all are positive and sum to **1**.
        Bigger logits get exponentially more mass.

        ## Numerical stability
        `exp` overflows fast, so subtract the max first:
        `softmax(x) = softmax(x − max(x))` — same result, no overflow. Softmax is
        the standard multi-class output and the heart of attention weights.
        """,
        "neuron": """
        ## The atomic unit
        A neuron is just **w·x + b** — a weighted sum of inputs plus a bias. The
        weights `w` are a direction in input space and `b` shifts the threshold;
        geometrically the neuron defines a **hyperplane**. Wrap it in an activation
        and you have the building block every layer is made of.
        """,
        "mlp-forward": """
        ## Stacking neurons into layers
        A **layer** applies many neurons at once — a matrix multiply `W·x + b`.
        Stack two layers with a nonlinearity between them and you get a
        **multi-layer perceptron**. The nonlinearity is essential: without it the
        two matrices collapse into one and you're back to a linear model.

        The **forward pass** is just: matmul → activation → matmul. With enough
        hidden units an MLP is a *universal approximator* — it can fit any
        continuous function.
        """,
        "cross-entropy": """
        ## Measuring "how wrong"
        For classification, the loss compares the predicted distribution `p` to the
        true label. **Cross-entropy** is `−log(p[correct])`: near 0 when the model
        is confident and right, and large when it's confident and wrong.

        It pairs with softmax — together their gradient simplifies to the clean
        `(p − y)`, which is why this combo is everywhere.
        """,
        "tanh": """
        ## Tanh — the zero-centered cousin of sigmoid
        tanh squashes to **(−1, 1)** instead of (0, 1), so its outputs are
        **zero-centered** — gradients flow more symmetrically than with sigmoid,
        which helped older RNNs train. Derivative is **1 − tanh²(x)**.

        It still **saturates** at the tails, so deep feed-forward nets prefer
        ReLU; but tanh remains common in gates (LSTM/GRU) and small models.
        """,
        "matmul": """
        ## The operation deep learning is built on
        A layer is a **matrix multiply**: outputs are linear combinations of
        inputs. `(AB)ᵢⱼ = Σ_k Aᵢ_k · B_kⱼ` — row of A dotted with column of B,
        which is why the inner dimensions must match.

        Almost all of a network's compute is matmuls, which is exactly why GPUs
        (and tensor cores) matter — they do these in massively parallel.
        """,
        "l2-normalize": """
        ## Putting vectors on the unit sphere
        Dividing by the L2 norm `‖v‖₂ = √Σvᵢ²` gives a **unit vector** — same
        direction, length 1. It makes magnitudes comparable, so dot products
        become **cosine similarity**. Used in embeddings, retrieval, and
        normalization layers everywhere.
        """,
        "one-hot": """
        ## Categories as vectors
        Models work on numbers, not labels. **One-hot** encodes class *k* as a
        vector that is 1 at position *k* and 0 elsewhere — no false ordering
        between categories. It's the target format for softmax + cross-entropy,
        and the conceptual input to an embedding lookup.
        """,
        "accuracy": """
        ## The simplest metric
        Accuracy is the fraction of predictions that match the labels. It's
        intuitive but **misleading on imbalanced data** (99% "no" → 99% accuracy
        by always guessing no), which is why precision/recall/F1 and AUC exist.
        Still the first number you check.
        """,
        "bce": """
        ## Loss for yes/no
        **Binary cross-entropy** is cross-entropy for two classes:
        `−[y·log(p) + (1−y)·log(1−p)]`. When y=1 it rewards a high p; when y=0 it
        rewards a low p; being confidently wrong is punished hard (the log blows
        up). It's the natural partner of a sigmoid output.
        """,
        "numerical-grad": """
        ## Gradients without calculus
        The derivative is a limit of a slope. A **finite difference** approximates
        it numerically: the **central difference** `(f(x+h) − f(x−h)) / 2h` is
        accurate to O(h²).

        You won't train with this (it's slow — one function eval per parameter per
        side), but it's the gold-standard **grad check**: compare it to your
        analytic backprop to catch bugs.
        """,
        "neuron-grad": """
        ## Backprop = the chain rule
        Training needs **∂loss/∂weight**. With loss = (pred − y)² and pred = w·x + b,
        the chain rule gives `∂L/∂wᵢ = 2(pred − y)·xᵢ` and `∂L/∂b = 2(pred − y)`.

        The gradient points **uphill**, so we step the *opposite* way to reduce the
        loss. Doing this composition automatically, layer by layer, is
        backpropagation.
        """,
        "micrograd": """
        ## Reverse-mode autodiff
        Every computation is a **graph** of tiny ops. Each op knows its **local
        derivative** (∂out/∂in). To get gradients for *all* parameters in one pass,
        do a **reverse** (topological) walk from the loss, multiplying local
        derivatives along the way — the chain rule, accumulated.

        This is exactly how PyTorch's `autograd` works. micrograd is the whole idea
        in ~150 lines: a `Value` that records its parents and a `_backward` closure.
        """,
        "gd-step": """
        ## Gradient descent
        To minimize a loss, repeatedly step **against** the gradient:
        `w ← w − lr · ∇L`. The **learning rate** `lr` is the step size — too small
        and it crawls, too large and it overshoots or diverges. This single update
        is the engine under every optimizer.
        """,
        "adam": """
        ## Adam — the default optimizer
        Plain SGD struggles with noisy or badly-scaled gradients. **Adam** keeps two
        running averages per parameter: **m** (momentum — the mean gradient) and
        **v** (the mean squared gradient). It steps with `m̂ / (√v̂ + ε)`, so each
        parameter gets its own adaptive learning rate.

        Early on m and v are biased toward zero, so Adam **bias-corrects** by
        dividing by `1 − βᵗ`. Defaults β₁=0.9, β₂=0.999 just work.
        """,
        "train-linear": """
        ## The training loop
        Learning is a loop: **forward** (predict) → **loss** → **backward**
        (gradients) → **update** (gradient descent), repeated for many steps. Plot
        the loss and it should fall and flatten — that curve is your single best
        diagnostic.

        Too-high `lr` → the curve spikes or oscillates; too-low → it barely moves.
        Watch the visualiser below as it trains.
        """,
        "torch-linear": """
        ## The workhorse layer
        `nn.Linear` computes **y = x·Wᵀ + b** over a whole batch at once. In PyTorch
        this is one batched matmul — no Python loops. Master tensor shapes and
        broadcasting here; every architecture is mostly linear layers glued
        together with nonlinearities and norms.
        """,
        "layernorm": """
        ## Keeping activations well-behaved
        Deep nets train better when activations stay at a stable scale.
        **LayerNorm** normalizes each example **across its features** to zero mean,
        unit variance, then rescales with learned `γ`, `β`.

        Unlike BatchNorm it doesn't depend on the batch, so it works for sequences
        and tiny batches — which is why **transformers use it everywhere**.
        """,
        "attention": """
        ## The transformer's core
        Attention lets every token look at every other token. Each token emits a
        **query**, and every token a **key** and **value**. Similarity is the
        dot product **q·k**, scaled by **√d_k** (so large dimensions don't saturate
        the softmax), turned into weights by softmax, and used to take a **weighted
        sum of values**.

        It's permutation-aware only via added position info, and it models
        **long-range** dependencies in one step — the idea behind *Attention Is All
        You Need*. Multi-head attention just runs several of these in parallel.
        """,
        "causal-attention": """
        ## Why a decoder can't peek ahead
        A language model predicts the **next** token, so position *i* must only
        attend to positions **≤ i** — never the future. The fix is a **causal
        mask**: before softmax, set every score where *j > i* to **−∞**, so those
        weights become exactly zero.

        This single masked attention is what makes GPT a *decoder* rather than an
        *encoder*. Build it once and a whole autoregressive model follows.
        """,
        "multihead-attention": """
        ## Many views of the sequence at once
        One attention head learns one notion of "relevance". **Multi-head**
        attention splits the model dimension into `h` independent heads, runs
        attention in each `d_k = D/h` subspace **in parallel**, then concatenates
        the results back to width `D`.

        Different heads specialize — syntax, coreference, position — and the model
        gets several relationship types for the price of one matmul. The only new
        skill is **reshaping**: `(B,T,D) → (B,h,T,d_k)` and back.
        """,
        "feed-forward": """
        ## The per-token compute block
        Attention *mixes* information across tokens; the **feed-forward network**
        then *processes* each token on its own. It's two linear layers with a
        nonlinearity between — `Linear(D→4D) · GELU · Linear(4D→D)` — applied
        identically at every position.

        It's where most of a transformer's parameters live, and the widening to
        `4D` gives the block room to compute before projecting back.
        """,
        "positional-encoding": """
        ## Giving order to a permutation-blind layer
        Attention sees a **set**, not a sequence — shuffle the tokens and the
        output just shuffles with them. To inject order, we **add** a positional
        signal to the embeddings.

        The original transformer uses fixed **sinusoids**: each dimension is a sine
        or cosine whose wavelength grows geometrically. Nearby positions get
        similar vectors, distant ones differ, and the pattern extends to lengths
        never seen in training.
        """,
        "bpe-train": """
        ## How text becomes tokens
        Models read integers, not characters. **Byte-Pair Encoding** starts from
        raw bytes (0–255) and repeatedly finds the **most frequent adjacent pair**,
        minting a new id for it. Run it `k` times and common chunks — `" the"`,
        `"ing"` — collapse into single tokens.

        The whole algorithm is two helpers: count pairs, and replace a chosen pair
        everywhere. It's exactly what GPT-2's tokenizer does, and where every
        prompt's token count comes from.
        """,
        "gpt-block": """
        ## The repeating unit of a GPT
        A decoder is the **same block stacked N times**. Each block is two
        residual sub-layers: **causal multi-head attention**, then a
        **feed-forward** network — every sub-layer wrapped as `x = x + sublayer(
        LayerNorm(x))` (the **pre-norm** arrangement modern GPTs use).

        Residuals give gradients a clean highway through depth; the causal mask
        keeps it autoregressive. Get this one block right and the full model is
        just embeddings around a stack of it.
        """,
        "tiny-gpt": """
        ## Assembling the whole model
        A GPT is **token embeddings + position embeddings → a stack of blocks →
        final LayerNorm → a linear head** to vocabulary logits. That's it — no
        magic beyond what you've already built.

        Here you wire those pieces and let it **overfit a tiny batch**: if the loss
        falls toward zero, the embeddings, residual stream, and head are all
        connected correctly. Same code as nanoGPT, just smaller.
        """,
        "gpt-generate": """
        ## Talking to the model
        Generation is a loop: feed the current tokens, take the logits at the
        **last** position, pick the next id, append, repeat. **Greedy** decoding
        takes the `argmax`; sampling with **temperature** and **top-k** trades
        determinism for diversity.

        One detail makes it real: **crop the context** to the model's block size
        each step, so a fixed-size model can generate sequences longer than it was
        trained on.
        """,
        "rmsnorm": """
        ## RMSNorm — normalization without the mean
        LayerNorm does two things: it **re-centers** (subtract the mean) and
        **re-scales** (divide by the standard deviation) each token's feature
        vector. RMSNorm keeps only the rescaling. The claim — from Zhang & Sennrich
        (2019) — is that the *scale invariance* is what stabilizes training, and
        the centering buys little.

        For a feature vector `x = (x₁, …, x_n)` it computes:

        ```
        RMS(x) = sqrt( (1/n) · Σ xᵢ²  +  ε )

                      xᵢ
        yᵢ  =  ───────────  · γᵢ
                  RMS(x)
        ```

        The **root mean square** in the denominator is just the L2 norm rescaled by
        √n. So RMSNorm projects `x` onto a sphere of fixed radius √n, then a learned
        per-feature gain `γ` (initialized to 1) lets the model stretch each
        dimension back. There is **no β bias** and **no mean subtraction**.

        ### Why it's preferred in modern LLMs
        - **Cheaper**: one pass for `Σxᵢ²` instead of a mean *and* a variance; no
          subtraction across the feature dim. At LLM scale every norm counts.
        - **Fewer parameters**: `γ` only, no `β`.
        - **Numerically clean** in low precision: the `+ ε` lives *inside* the
          square root, and the reference normalizes in **float32** (`x.float()`)
          even when the model runs in bf16, then casts back — small magnitudes
          don't underflow.

        ### The gradient intuition
        Dividing by `RMS(x)` makes the output invariant to the overall scale of
        `x`: multiply `x` by 10 and `y` is unchanged. That decouples "how big are
        my activations" from "what direction do they point", which is exactly the
        instability deep residual stacks suffer from. LayerNorm everywhere in the
        original transformer becomes **RMSNorm everywhere** in Llama, GPT-NeoX,
        and friends.
        """,
        "rope": """
        ## RoPE — rotary position embeddings
        Attention is permutation-blind, so position must be injected somehow. The
        original transformer **adds** a positional vector to the token embedding.
        RoPE (Su et al., 2021) instead **rotates** the query and key vectors by an
        angle proportional to their position — and that single trick makes
        attention scores depend only on **relative** position.

        ### Rotating pairs of dimensions
        Split the head dimension `d` into `d/2` consecutive pairs
        `(x₀,x₁), (x₂,x₃), …`. Treat each pair as a point in a 2-D plane and rotate
        it. For a token at position `m`, pair `i` is rotated by angle `m·θᵢ`:

        ```
        ⎡ x'₂ᵢ   ⎤   ⎡ cos(mθᵢ)   −sin(mθᵢ) ⎤ ⎡ x₂ᵢ   ⎤
        ⎢        ⎥ = ⎢                       ⎥ ⎢       ⎥
        ⎣ x'₂ᵢ₊₁ ⎦   ⎣ sin(mθᵢ)    cos(mθᵢ) ⎦ ⎣ x₂ᵢ₊₁ ⎦
        ```

        The per-pair frequencies are a **geometric series**, identical to the
        sinusoidal-encoding wavelengths:

        ```
        θᵢ = base^(−2i/d) ,   base = 10000 ,   i = 0 … d/2−1
        ```

        Low `i` rotates slowly (long wavelength → coarse, long-range position);
        high `i` rotates fast (short wavelength → fine, local position).

        ### Why the dot product becomes relative
        Write a rotation by angle `mθ` as the complex multiply `e^{imθ}`. Pair `i`
        of the query at position `m` becomes `qᵢ·e^{imθᵢ}`, and of the key at
        position `n`, `kᵢ·e^{inθᵢ}`. Their contribution to the attention score is
        the real part of:

        ```
        (qᵢ e^{imθᵢ}) · conj(kᵢ e^{inθᵢ})
            =  qᵢ kᵢ* · e^{i(m−n)θᵢ}
        ```

        The absolute positions `m` and `n` survive **only through their difference
        `m − n`**. So a query and key that are 5 tokens apart produce the same
        score no matter *where* in the sequence they sit. Relative position falls
        out of the algebra for free — no learned relative-position table.

        ### Two properties worth testing
        - **Norm-preserving**: rotation is orthogonal, so `‖RoPE(x)‖ = ‖x‖`. RoPE
          never changes a vector's length, only its angle — it can't blow up
          activations.
        - **Relative invariance**: shifting *both* the query and key positions by
          the same amount leaves every score unchanged (`score[m,n] = score[m+s,
          n+s]`). That's the defining property and a perfect unit test.

        ### Why modern models use it
        It needs no extra parameters, applies the *same* rule at every layer, and
        **extrapolates** — because position enters as an angle, a model trained on
        2 K tokens still produces sensible (if degrading) scores past that length,
        which is the basis for long-context tricks like NTK / position
        interpolation.
        """,
        "swiglu": """
        ## SwiGLU — a gated feed-forward block
        The classic transformer FFN is `W₂ · GELU(W₁x)` — widen, nonlinearity,
        project back. SwiGLU (Shazeer, 2020) replaces the single nonlinearity with
        a **gate**: one linear branch decides *how much* of another linear branch
        to let through.

        ```
        SwiGLU(x) = W₂ · ( SiLU(W₁x) ⊙ W₃x )
        ```

        Three weight matrices now: `W₁` (the **gate**), `W₃` (the **value/up**
        projection), and `W₂` (the **down** projection). `⊙` is elementwise
        multiply. The gate `SiLU(W₁x)` modulates the value `W₃x` channel by
        channel before the result is projected back to model width.

        ### SiLU / Swish
        The activation is **SiLU** (a.k.a. Swish):

        ```
        SiLU(z) = z · σ(z) = z / (1 + e^(−z))
        ```

        Unlike ReLU it is **smooth** and **non-monotonic** — it dips slightly
        negative for small negative `z` before returning to 0, which empirically
        trains better. Its derivative is `σ(z) · (1 + z·(1 − σ(z)))`, well-defined
        everywhere (ReLU's kink at 0 is gone).

        ### Why gating helps
        A plain MLP applies the *same* nonlinearity to every feature. A gated unit
        lets the network learn a **multiplicative, input-dependent mask** — it can
        suppress or amplify each hidden channel based on the input, a strictly
        richer function class. The GLU family (ReGLU, GEGLU, SwiGLU) consistently
        beats the ungated FFN at equal compute.

        ### The 2/3 detail
        Gating adds a third matrix, so to keep the parameter count of the block
        roughly equal to a standard FFN of hidden size `4d`, Llama shrinks the
        hidden dimension to about **⅔ · 4d** (then rounds to a hardware-friendly
        multiple). Same budget, better block.
        """,
        "gqa": """
        ## Grouped-Query Attention — sharing the K/V heads
        Standard multi-head attention gives every head its **own** query, key, and
        value projections. At inference the keys and values of every past token are
        cached, so the **KV cache** holds `n_heads` worth of K and V for the whole
        sequence — and reading it back from memory each step is the bottleneck of
        autoregressive decoding.

        GQA (Ainslie et al., 2023) sits on a spectrum:

        ```
        MHA   : n_kv_heads = n_heads     (one K/V per query head — most memory)
        GQA   : 1 < n_kv_heads < n_heads (query heads share K/V in groups)
        MQA   : n_kv_heads = 1           (all query heads share one K/V — least)
        ```

        With `n_kv_heads` key/value heads and `n_heads` query heads, each K/V head
        is shared by a **group** of `n_rep = n_heads / n_kv_heads` query heads.

        ### The mechanics — repeat_kv
        Before attention, each K/V head is duplicated `n_rep` times so the head
        counts line up, which is exactly `torch.repeat_interleave(x, n_rep,
        dim=head)`:

        ```
        kv heads:   [ A  B ]                       (n_kv_heads = 2)
        repeated:   [ A  A  A  A  B  B  B  B ]     (n_rep = 4 → 8 query heads)
        query head:   0  1  2  3  4  5  6  7
        ```

        Note it's **interleave**, not tile: query heads 0–3 all attend through K/V
        head A, heads 4–7 through B. The compute is identical to MHA after the
        repeat — the win is purely that the **cache** stores only `n_kv_heads`
        heads.

        ### Why it matters
        - **KV-cache size** (and the memory traffic to read it) drops by
          `n_heads / n_kv_heads`. Llama-2 70B uses 8 KV heads for 64 query heads —
          an 8× smaller cache.
        - Quality sits **between** MQA and MHA: MQA's single shared head can hurt,
          GQA recovers almost all of MHA's quality at a fraction of the bandwidth.
        It's the default in Llama-2/3, Mistral, and most current open models.
        """,
        "kv-cache": """
        ## The KV cache — don't recompute the past
        Generation is autoregressive: to produce token `t+1` you run attention
        over tokens `0…t`. The naive loop re-encodes the **entire** prefix every
        step, so generating `T` tokens costs `O(T²)` attention work — and most of
        it is recomputing keys and values that never change.

        The fix is a **cache**. A token's key and value depend only on that token
        (and earlier ones, via the causal mask) — never on the future. So once
        computed they are **final**. Keep them:

        ```
        prefill (one big forward over the prompt):
            K_cache, V_cache  ←  K, V  for every prompt token

        decode (per new token):
            k_t, v_t  ←  project just the new token
            K_cache   ←  concat(K_cache, k_t)     # append
            V_cache   ←  concat(V_cache, v_t)
            out_t     ←  attention( q_t , K_cache , V_cache )
        ```

        Each decode step now does **one** query against all cached keys — `O(T)`
        per step, `O(T²)` total but with a tiny constant and, crucially, **no
        recomputation**. The query for the new token is the only thing projected
        fresh.

        ### Why no causal mask is needed during decode
        At step `t` the cache holds exactly tokens `0…t` and the lone query is
        token `t`. It is *supposed* to attend to all of them, so plain (non-causal)
        attention over the cache is already correct. The defining test: feeding
        tokens one at a time through the cache must produce the **same** output as
        one full causal forward over the whole sequence.

        ### The cost it trades into
        Memory. The cache holds `2 · n_layers · n_kv_heads · head_dim` floats **per
        token** — which is precisely why [[gqa]] (fewer KV heads) and quantized
        caches matter: at long context the KV cache, not the weights, dominates
        memory.
        """,
        "llama-block": """
        ## Assembling a Llama block
        Everything in this module snaps together into the unit a modern decoder
        stacks N times. Like the [[gpt-block]] it is two **pre-norm residual**
        sub-layers, but each piece is the modern variant:

        ```
        h = x + Attention( RMSNorm(x) )          # RoPE on Q,K · GQA · causal
        y = h + SwiGLU(  RMSNorm(h) )             # gated feed-forward
        ```

        Walking the attention sub-layer:

        ```
        1. a   = RMSNorm(x)                       # [[rmsnorm]], not LayerNorm
        2. q,k,v = a·Wq , a·Wk , a·Wv             # Wk,Wv are smaller (GQA)
        3. q,k = RoPE(q), RoPE(k)                 # [[rope]] — rotate, don't add
        4. k,v = repeat_kv(k,v)                   # [[gqa]] — share K/V heads
        5. o   = causal_attention(q,k,v)          # scaled dot-product, masked
        6. h   = x + o·Wo                          # residual back into the stream
        ```

        ### What changed from a GPT-2 block
        - **RMSNorm** replaces LayerNorm (no mean, no bias).
        - **RoPE** replaces learned/sinusoidal *additive* position — and it's
          applied to Q and K **inside** attention, every layer, not once at the
          input.
        - **SwiGLU** replaces the GELU MLP (gated, three matrices, ⅔·4d hidden).
        - **GQA** replaces full multi-head attention (fewer K/V heads → smaller
          [[kv-cache]]).
        - **No biases** on the linear layers, and norms are **pre**-norm
          (`x + sublayer(norm(x))`), which is what lets very deep stacks train
          stably.

        The behavioral signature is the same as any decoder block: it must be
        **causal** — perturbing a later token can't change the output at earlier
        positions. Get that invariant right and you've built the core of Llama.
        """
    ]

    // MARK: Module 0 — Terminal (POSIX shell)
    //
    // Verified by filesystem state: `setup` stages input files, the user's
    // command transforms them, the hidden test diffs the result. Pure sh — no
    // bashisms — so it runs under dash in the slim Ubuntu image.

    private static let terminal: [Challenge] = [
        Challenge(
            id: "echo-redirect", title: "echo & redirect", module: "0 · Terminal", order: 1, difficulty: .easy,
            prompt: "Use `echo` and the **`>`** redirect to write the single line `hello world` into a file named `out.txt`.",
            starter: "# Write \"hello world\" into out.txt\n",
            test: """
            [ "$(cat out.txt)" = "hello world" ] || { echo "❌ out.txt should contain exactly: hello world"; exit 1; }
            echo "✅ All tests passed"
            """,
            image: shellImage, language: .bash),
        Challenge(
            id: "append", title: "Append with >>", module: "0 · Terminal", order: 2, difficulty: .easy,
            prompt: "`notes.txt` already holds `line one`. Use **`>>`** to *append* a second line, `line two`, without overwriting the first.",
            starter: "# Append \"line two\" to notes.txt\n",
            test: """
            printf 'line one\\nline two\\n' > expected.txt
            diff expected.txt notes.txt >/dev/null 2>&1 || { echo "❌ notes.txt should hold both lines, in order"; exit 1; }
            echo "✅ All tests passed"
            """,
            image: shellImage, language: .bash, setup: "printf 'line one\\n' > notes.txt"),
        Challenge(
            id: "cp-file", title: "Copy a file", module: "0 · Terminal", order: 3, difficulty: .easy,
            prompt: "Copy `data.txt` to a new file `copy.txt` with **`cp`**.",
            starter: "# Copy data.txt to copy.txt\n",
            test: """
            diff data.txt copy.txt >/dev/null 2>&1 || { echo "❌ copy.txt should be identical to data.txt"; exit 1; }
            echo "✅ All tests passed"
            """,
            image: shellImage, language: .bash, setup: "printf 'the quick brown fox\\n' > data.txt"),
        Challenge(
            id: "head-lines", title: "head: first N lines", module: "0 · Terminal", order: 4, difficulty: .easy,
            prompt: "`nums.txt` has the numbers 1–10, one per line. Write its **first 3 lines** to `top.txt` using **`head`**.",
            starter: "# First 3 lines of nums.txt -> top.txt\n",
            test: """
            printf '1\\n2\\n3\\n' > expected.txt
            diff expected.txt top.txt >/dev/null 2>&1 || { echo "❌ top.txt should be the first 3 lines"; exit 1; }
            echo "✅ All tests passed"
            """,
            image: shellImage, language: .bash, setup: "printf '1\\n2\\n3\\n4\\n5\\n6\\n7\\n8\\n9\\n10\\n' > nums.txt"),
        Challenge(
            id: "wc-lines", title: "Count lines", module: "0 · Terminal", order: 5, difficulty: .easy,
            prompt: "Count the lines in `log.txt` and write **just the number** to `count.txt`. (Hint: `wc -l < log.txt` keeps the filename out of the output.)",
            starter: "# Write the line count of log.txt into count.txt\n",
            test: """
            n="$(tr -d ' \\n' < count.txt)"
            [ "$n" = "5" ] || { echo "❌ count.txt should contain 5, got: $n"; exit 1; }
            echo "✅ All tests passed"
            """,
            image: shellImage, language: .bash, setup: "printf 'a\\nb\\nc\\nd\\ne\\n' > log.txt"),
        Challenge(
            id: "grep-filter", title: "Filter with grep", module: "0 · Terminal", order: 6, difficulty: .medium,
            prompt: "Write every line of `log.txt` that contains **`ERROR`** into `errors.txt`, keeping their order. Use **`grep`**.",
            starter: "# grep the ERROR lines from log.txt into errors.txt\n",
            test: """
            printf 'ERROR disk full\\nERROR oom\\n' > expected.txt
            diff expected.txt errors.txt >/dev/null 2>&1 || { echo "❌ errors.txt should hold only the ERROR lines"; exit 1; }
            echo "✅ All tests passed"
            """,
            image: shellImage, language: .bash,
            setup: "printf 'INFO ok\\nERROR disk full\\nINFO done\\nERROR oom\\n' > log.txt"),
        Challenge(
            id: "pipe-sort-uniq", title: "Pipes: sort | uniq", module: "0 · Terminal", order: 7, difficulty: .medium,
            prompt: "Using a **pipe** (`|`), write the **unique** words from `words.txt` in **sorted** order to `unique.txt`. (Hint: `uniq` only collapses *adjacent* duplicates, so `sort` first.)",
            starter: "# sort words.txt, drop duplicates, write to unique.txt\n",
            test: """
            printf 'apple\\nbanana\\ncherry\\n' > expected.txt
            diff expected.txt unique.txt >/dev/null 2>&1 || { echo "❌ unique.txt should be the sorted, de-duplicated words"; exit 1; }
            echo "✅ All tests passed"
            """,
            image: shellImage, language: .bash,
            setup: "printf 'banana\\napple\\napple\\ncherry\\nbanana\\n' > words.txt"),
        Challenge(
            id: "for-loop", title: "Variables & a for loop", module: "0 · Terminal", order: 8, difficulty: .medium,
            prompt: "Use a shell **`for` loop** to create three empty files: `file1.txt`, `file2.txt`, `file3.txt`. (Hint: `for i in 1 2 3; do touch \"file$i.txt\"; done`.)",
            starter: "# Create file1.txt, file2.txt, file3.txt with a for loop\n",
            test: """
            for i in 1 2 3; do [ -f "file$i.txt" ] || { echo "❌ missing file$i.txt"; exit 1; }; done
            echo "✅ All tests passed"
            """,
            image: shellImage, language: .bash)
    ]

    // MARK: Module 0b — Shell for ML (POSIX shell, ML workflows)
    //
    // Scripting you actually use to drive training: env vars, parsing logs,
    // editing configs, finding checkpoints, batching shards, archiving runs.
    // Still pure sh, verified by filesystem/stdout state in the Ubuntu image.

    private static let shellML: [Challenge] = [
        Challenge(
            id: "env-vars", title: "Environment variables", module: "0 · Shell for ML", order: 1, difficulty: .easy,
            prompt: "Set a variable `EPOCHS` to `10`, then write `training for $EPOCHS epochs` to `cmd.txt`. This is exactly how you pass config to a run — e.g. `CUDA_VISIBLE_DEVICES=0` to pick a GPU.",
            starter: "# Set EPOCHS=10, then write \"training for $EPOCHS epochs\" to cmd.txt\n",
            test: """
            [ "$(cat cmd.txt)" = "training for 10 epochs" ] || { echo "❌ cmd.txt should read: training for 10 epochs"; exit 1; }
            echo "✅ All tests passed"
            """,
            image: shellImage, language: .bash),
        Challenge(
            id: "cmd-subst", title: "Command substitution", module: "0 · Shell for ML", order: 2, difficulty: .medium,
            prompt: "`train.csv` has a header row plus the data. Using **`$(...)`** and arithmetic **`$(( ))`**, write `dataset: <N> rows` to `summary.txt`, where N is the row count *excluding* the header.",
            starter: "# Count data rows (lines minus the header) and write \"dataset: N rows\" to summary.txt\n",
            test: """
            [ "$(cat summary.txt)" = "dataset: 3 rows" ] || { echo "❌ summary.txt should read: dataset: 3 rows"; exit 1; }
            echo "✅ All tests passed"
            """,
            image: shellImage, language: .bash, setup: "printf 'x,y\\n1,2\\n3,4\\n5,6\\n' > train.csv"),
        Challenge(
            id: "resume-if", title: "Resume or train (if)", module: "0 · Shell for ML", order: 3, difficulty: .medium,
            prompt: "Check for a checkpoint with **`if [ -f model.pt ]`**: if it exists write `resuming` to `status.txt`, otherwise write `training fresh`. (A checkpoint is present here.)",
            starter: "# if model.pt exists -> \"resuming\", else -> \"training fresh\", into status.txt\n",
            test: """
            [ "$(cat status.txt)" = "resuming" ] || { echo "❌ a checkpoint exists, so status.txt should read: resuming"; exit 1; }
            echo "✅ All tests passed"
            """,
            image: shellImage, language: .bash, setup: ": > model.pt"),
        Challenge(
            id: "awk-column", title: "awk: extract a column", module: "0 · Shell for ML", order: 4, difficulty: .medium,
            prompt: "`metrics.csv` is `epoch,loss,acc`. Use **awk** (`-F,` field separator) to write just the **loss** column of the data rows to `loss.txt`, skipping the header (`NR>1`).",
            starter: "# awk: print the 2nd field of every data row of metrics.csv -> loss.txt\n",
            test: """
            printf '0.90\\n0.50\\n0.20\\n' > expected.txt
            diff expected.txt loss.txt >/dev/null 2>&1 || { echo "❌ loss.txt should be just the loss column (no header)"; exit 1; }
            echo "✅ All tests passed"
            """,
            image: shellImage, language: .bash,
            setup: "printf 'epoch,loss,acc\\n1,0.90,0.40\\n2,0.50,0.70\\n3,0.20,0.92\\n' > metrics.csv"),
        Challenge(
            id: "parse-log", title: "Parse a training log", module: "0 · Shell for ML", order: 5, difficulty: .medium,
            prompt: "`train.log` has lines like `epoch 3 loss 0.12`. Write the **final** loss value to `final.txt`. (Hint: `tail -1 ... | awk '{print $NF}'` — `$NF` is the last field.)",
            starter: "# write the last line's loss value of train.log -> final.txt\n",
            test: """
            [ "$(cat final.txt)" = "0.12" ] || { echo "❌ final.txt should be the last loss: 0.12"; exit 1; }
            echo "✅ All tests passed"
            """,
            image: shellImage, language: .bash,
            setup: "printf 'epoch 1 loss 0.90\\nepoch 2 loss 0.45\\nepoch 3 loss 0.12\\n' > train.log"),
        Challenge(
            id: "sed-config", title: "sed: tweak a hyperparameter", module: "0 · Shell for ML", order: 6, difficulty: .medium,
            prompt: "`config.txt` sets `lr=0.1`. Use **sed** to change it to `lr=0.01`, writing the result back to `config.txt` and leaving the other lines untouched. (GNU `sed -i 's/old/new/' config.txt` edits in place.)",
            starter: "# sed: replace lr=0.1 with lr=0.01 in config.txt\n",
            test: """
            printf 'lr=0.01\\nbatch_size=32\\nepochs=10\\n' > expected.txt
            diff expected.txt config.txt >/dev/null 2>&1 || { echo "❌ only the lr line should change, to lr=0.01"; exit 1; }
            echo "✅ All tests passed"
            """,
            image: shellImage, language: .bash, setup: "printf 'lr=0.1\\nbatch_size=32\\nepochs=10\\n' > config.txt"),
        Challenge(
            id: "find-ckpt", title: "find: locate checkpoints", module: "0 · Shell for ML", order: 7, difficulty: .medium,
            prompt: "Use **find** to list every `*.pt` file under `runs/`, **sort** the paths, and write them to `checkpoints.txt`.",
            starter: "# find all .pt files under runs/, sorted -> checkpoints.txt\n",
            test: """
            printf 'runs/exp1/model.pt\\nruns/exp2/model.pt\\n' > expected.txt
            diff expected.txt checkpoints.txt >/dev/null 2>&1 || { echo "❌ checkpoints.txt should be the sorted .pt paths"; exit 1; }
            echo "✅ All tests passed"
            """,
            image: shellImage, language: .bash,
            setup: "mkdir -p runs/exp1 runs/exp2; : > runs/exp1/model.pt; : > runs/exp2/model.pt; : > runs/exp1/notes.txt"),
        Challenge(
            id: "loop-shards", title: "Batch over dataset shards", module: "0 · Shell for ML", order: 8, difficulty: .medium,
            prompt: "For every `.txt` file under `data/` (in sorted glob order), append a line `<file>: <line count>` to `counts.txt`. Use a **for loop** over `data/*.txt` with `wc -l`.",
            starter: "# for each data/*.txt, write \"<file>: <lines>\" to counts.txt\n",
            test: """
            printf 'data/s1.txt: 2\\ndata/s2.txt: 3\\n' > expected.txt
            sed 's/:[[:space:]]*/: /' counts.txt > got.txt
            diff expected.txt got.txt >/dev/null 2>&1 || { echo "❌ counts.txt should list each shard and its line count"; exit 1; }
            echo "✅ All tests passed"
            """,
            image: shellImage, language: .bash,
            setup: "mkdir -p data; printf 'a\\nb\\n' > data/s1.txt; printf 'a\\nb\\nc\\n' > data/s2.txt"),
        Challenge(
            id: "archive-run", title: "Archive a run (tar)", module: "0 · Shell for ML", order: 9, difficulty: .easy,
            prompt: "Bundle the `outputs/` directory into a **gzipped tar** archive `run.tar.gz` (`tar -czf`) — how you'd snapshot a finished run's logs and weights.",
            starter: "# tar + gzip the outputs/ directory into run.tar.gz\n",
            test: """
            tar -tzf run.tar.gz | grep -q 'outputs/model.pt' || { echo "❌ run.tar.gz should contain the outputs/ files"; exit 1; }
            echo "✅ All tests passed"
            """,
            image: shellImage, language: .bash,
            setup: "mkdir -p outputs; printf 'done\\n' > outputs/log.txt; : > outputs/model.pt")
    ]

    // MARK: Module 1 — Foundations (pure Python)

    private static let foundations: [Challenge] = [
        Challenge(
            id: "sigmoid", title: "Sigmoid", module: "1 · Foundations", order: 1, difficulty: .easy,
            prompt: "Implement the **sigmoid** activation σ(x) = 1 / (1 + e⁻ˣ). Return a float.",
            starter: "import math\n\ndef sigmoid(x: float) -> float:\n    # TODO\n    pass\n",
            test: """
            assert abs(sigmoid(0) - 0.5) < 1e-9
            assert abs(sigmoid(1) - 0.7310585786) < 1e-6
            assert sigmoid(-100) < 1e-6 and sigmoid(100) > 1 - 1e-6
            print("✅ All tests passed")
            """,
            reference: "byhand.ai · Ng C1"),
        Challenge(
            id: "relu", title: "ReLU", module: "1 · Foundations", order: 2, difficulty: .easy,
            prompt: "Implement **ReLU** elementwise over a list: `relu(xs)` returns `max(0, x)` for each x.",
            starter: "def relu(xs):\n    # TODO\n    pass\n",
            test: """
            assert relu([-1.0, 0.0, 2.0, -3.5]) == [0.0, 0.0, 2.0, 0.0]
            assert relu([]) == []
            print("✅ All tests passed")
            """),
        Challenge(
            id: "softmax", title: "Softmax", module: "1 · Foundations", order: 3, difficulty: .easy,
            prompt: "Implement **softmax** over logits. Output sums to 1; subtract the max first for stability.",
            starter: "import math\n\ndef softmax(xs):\n    # TODO\n    pass\n",
            test: """
            out = softmax([1.0, 2.0, 3.0])
            assert abs(sum(out) - 1.0) < 1e-9
            assert out[2] > out[1] > out[0]
            assert abs(out[0] - 0.0900305732) < 1e-6
            print("✅ All tests passed")
            """),
        Challenge(
            id: "neuron", title: "A Single Neuron", module: "1 · Foundations", order: 4, difficulty: .easy,
            prompt: "Implement `neuron(w, x, b)` = the dot product **w·x + b** (a single linear unit).",
            starter: "def neuron(w, x, b):\n    # TODO\n    pass\n",
            test: """
            assert abs(neuron([1.0, -2.0, 0.5], [2.0, 1.0, 4.0], 1.0) - 3.0) < 1e-9
            assert abs(neuron([], [], 0.5) - 0.5) < 1e-9
            print("✅ All tests passed")
            """,
            reference: "byhand.ai"),
        Challenge(
            id: "mlp-forward", title: "MLP Forward Pass", module: "1 · Foundations", order: 5, difficulty: .medium,
            prompt: """
            Implement a 2-layer MLP forward pass: `mlp(x, W1, b1, W2, b2)`.
            Hidden = **ReLU(W1·x + b1)**, output = **W2·hidden + b2**. Each W is a
            list of rows. Return the output list.
            """,
            starter: "def mlp(x, W1, b1, W2, b2):\n    # TODO: matvec + relu + matvec\n    pass\n",
            test: """
            out = mlp([2.0, -3.0], [[1.0, 0.0], [0.0, 1.0]], [0.0, 0.0], [[1.0, 1.0]], [0.0])
            assert len(out) == 1 and abs(out[0] - 2.0) < 1e-9
            print("✅ All tests passed")
            """,
            reference: "Ng C1"),
        Challenge(
            id: "cross-entropy", title: "Cross-Entropy Loss", module: "1 · Foundations", order: 6, difficulty: .easy,
            prompt: "Implement `cross_entropy(probs, target)` = **−log(probs[target])** for a class index.",
            starter: "import math\n\ndef cross_entropy(probs, target):\n    # TODO\n    pass\n",
            test: """
            import math
            assert abs(cross_entropy([0.7, 0.2, 0.1], 0) - 0.3566749439) < 1e-6
            assert cross_entropy([0.0, 1.0], 1) < 1e-9
            print("✅ All tests passed")
            """),
        Challenge(
            id: "tanh", title: "Tanh", module: "1 · Foundations", order: 7, difficulty: .easy,
            prompt: "Implement **tanh(x)** = (eˣ − e⁻ˣ)/(eˣ + e⁻ˣ). Range (−1, 1), zero-centered.",
            starter: "import math\n\ndef tanh(x):\n    # TODO\n    pass\n",
            test: """
            assert abs(tanh(0) - 0.0) < 1e-9
            assert abs(tanh(1) - 0.7615941559) < 1e-6
            assert tanh(-50) < -0.999 and tanh(50) > 0.999
            print("✅ All tests passed")
            """),
        Challenge(
            id: "matmul", title: "Matrix Multiply", module: "1 · Foundations", order: 8, difficulty: .medium,
            prompt: "Implement `matmul(A, B)` — A is m×k, B is k×n; return the m×n product. Each is a list of rows.",
            starter: "def matmul(A, B):\n    # TODO\n    pass\n",
            test: """
            assert matmul([[1, 2], [3, 4]], [[5, 6], [7, 8]]) == [[19, 22], [43, 50]]
            assert matmul([[1, 0, 2]], [[3], [4], [5]]) == [[13]]
            print("✅ All tests passed")
            """),
        Challenge(
            id: "l2-normalize", title: "L2 Normalize", module: "1 · Foundations", order: 9, difficulty: .easy,
            prompt: "Implement `l2_normalize(v)` = v / ‖v‖₂ (the unit vector). Assume v is non-zero.",
            starter: "import math\n\ndef l2_normalize(v):\n    # TODO\n    pass\n",
            test: """
            out = l2_normalize([3.0, 4.0])
            assert abs(out[0] - 0.6) < 1e-9 and abs(out[1] - 0.8) < 1e-9
            print("✅ All tests passed")
            """),
        Challenge(
            id: "one-hot", title: "One-Hot Encoding", module: "1 · Foundations", order: 10, difficulty: .easy,
            prompt: "Implement `one_hot(index, n)` → a length-n list that is 1 at `index` and 0 elsewhere.",
            starter: "def one_hot(index, n):\n    # TODO\n    pass\n",
            test: """
            assert one_hot(2, 4) == [0, 0, 1, 0]
            assert one_hot(0, 1) == [1]
            print("✅ All tests passed")
            """),
        Challenge(
            id: "accuracy", title: "Accuracy", module: "1 · Foundations", order: 11, difficulty: .easy,
            prompt: "Implement `accuracy(preds, labels)` — the fraction of positions where they match.",
            starter: "def accuracy(preds, labels):\n    # TODO\n    pass\n",
            test: """
            assert abs(accuracy([1, 0, 1, 1], [1, 1, 1, 0]) - 0.5) < 1e-9
            assert abs(accuracy([2, 2], [2, 2]) - 1.0) < 1e-9
            print("✅ All tests passed")
            """),
        Challenge(
            id: "bce", title: "Binary Cross-Entropy", module: "1 · Foundations", order: 12, difficulty: .medium,
            prompt: "Implement `bce(p, y)` for one example: **−[y·log(p) + (1−y)·log(1−p)]**, where y ∈ {0, 1}.",
            starter: "import math\n\ndef bce(p, y):\n    # TODO\n    pass\n",
            test: """
            import math
            assert abs(bce(0.9, 1) - 0.1053605157) < 1e-6
            assert abs(bce(0.1, 0) - 0.1053605157) < 1e-6
            print("✅ All tests passed")
            """)
    ]

    // MARK: Module 2 — Autograd & Backprop (pure Python)

    private static let autograd: [Challenge] = [
        Challenge(
            id: "numerical-grad", title: "Numerical Gradient", module: "2 · Autograd & Backprop", order: 1, difficulty: .easy,
            prompt: "Implement the **central-difference** derivative: `numgrad(f, x, h=1e-5)` ≈ (f(x+h) − f(x−h)) / 2h.",
            starter: "def numgrad(f, x, h=1e-5):\n    # TODO\n    pass\n",
            test: """
            assert abs(numgrad(lambda t: t * t, 3.0) - 6.0) < 1e-4
            assert abs(numgrad(lambda t: t ** 3, 2.0) - 12.0) < 1e-3
            print("✅ All tests passed")
            """),
        Challenge(
            id: "neuron-grad", title: "Backprop a Neuron", module: "2 · Autograd & Backprop", order: 2, difficulty: .medium,
            prompt: """
            For a linear neuron pred = w·x + b and loss = (pred − y)², return the
            gradients **(dL/dw as a list, dL/db as a float)**.
            (dL/dw_i = 2·(pred − y)·x_i, dL/db = 2·(pred − y).)
            """,
            starter: "def neuron_grad(w, x, b, y):\n    # TODO: return (grad_w, grad_b)\n    pass\n",
            test: """
            gw, gb = neuron_grad([1.0, 1.0], [1.0, 2.0], 0.0, 0.0)
            assert abs(gw[0] - 6.0) < 1e-9 and abs(gw[1] - 12.0) < 1e-9
            assert abs(gb - 6.0) < 1e-9
            print("✅ All tests passed")
            """,
            reference: "Karpathy micrograd"),
        Challenge(
            id: "micrograd", title: "micrograd: Value + backward", module: "2 · Autograd & Backprop", order: 3, difficulty: .hard,
            prompt: """
            Implement reverse-mode autodiff. Complete `__add__`, `__mul__`, and
            `tanh` on `Value` so each builds the output node **and** sets its
            `_backward` to push gradients to its inputs. `backward()` is given.
            Follows Karpathy's **micrograd**.
            """,
            starter: """
            import math

            class Value:
                def __init__(self, data, _children=()):
                    self.data = data
                    self.grad = 0.0
                    self._backward = lambda: None
                    self._prev = set(_children)

                def __add__(self, other):
                    # TODO: out = Value(self.data + other.data, (self, other))
                    # out._backward adds out.grad to self.grad and other.grad
                    pass

                def __mul__(self, other):
                    # TODO: chain rule: d/dself = other.data, d/dother = self.data
                    pass

                def tanh(self):
                    # TODO: t = tanh(x); local grad = (1 - t**2)
                    pass

                def backward(self):
                    topo, seen = [], set()
                    def build(v):
                        if v not in seen:
                            seen.add(v)
                            for c in v._prev:
                                build(c)
                            topo.append(v)
                    build(self)
                    self.grad = 1.0
                    for v in reversed(topo):
                        v._backward()
            """,
            test: """
            a = Value(2.0)
            b = Value(-3.0)
            e = a * b + a          # = a*b + a
            e.backward()
            assert abs(a.grad - (-2.0)) < 1e-9   # de/da = b + 1
            assert abs(b.grad - 2.0) < 1e-9      # de/db = a
            print("✅ All tests passed")
            """,
            reference: "github.com/karpathy/micrograd")
    ]

    // MARK: Module 3 — Optimization & Training (pure Python)

    private static let optimization: [Challenge] = [
        Challenge(
            id: "gd-step", title: "Gradient Descent Step", module: "3 · Optimization & Training", order: 1, difficulty: .easy,
            prompt: "Implement one GD step: `gd_step(w, grad, lr)` returns w_i − lr·grad_i for each i.",
            starter: "def gd_step(w, grad, lr):\n    # TODO\n    pass\n",
            test: """
            out = gd_step([1.0, 2.0], [0.5, 1.0], 0.1)
            assert abs(out[0] - 0.95) < 1e-9 and abs(out[1] - 1.9) < 1e-9
            print("✅ All tests passed")
            """),
        Challenge(
            id: "adam", title: "Adam Update", module: "3 · Optimization & Training", order: 2, difficulty: .hard,
            prompt: """
            Implement one **Adam** step. Update biased moments m, v; bias-correct
            with step t; return **(w_new, m_new, v_new)**.
            m = β₁m + (1−β₁)g, v = β₂v + (1−β₂)g², m̂ = m/(1−β₁ᵗ), v̂ = v/(1−β₂ᵗ),
            w −= lr·m̂/(√v̂ + ε).
            """,
            starter: """
            import math

            def adam_step(w, g, m, v, t, lr=0.01, b1=0.9, b2=0.999, eps=1e-8):
                # TODO: return (w_new, m_new, v_new) as lists
                pass
            """,
            test: """
            w2, m2, v2 = adam_step([0.0], [1.0], [0.0], [0.0], 1)
            assert abs(m2[0] - 0.1) < 1e-9 and abs(v2[0] - 0.001) < 1e-9
            assert abs(w2[0] - (-0.01)) < 1e-4
            print("✅ All tests passed")
            """,
            reference: "Ng C2 · Kingma & Ba 2014"),
        Challenge(
            id: "train-linear", title: "Train a Line (with loss curve)", module: "3 · Optimization & Training", order: 3, difficulty: .medium,
            prompt: """
            Fit **y = 2x + 1** by gradient descent. Implement
            `train(xs, ys, steps, lr)` returning `(w, b)`. **Print `loss <i> <value>`
            each step** — the visualiser plots it. Loss is mean squared error.
            """,
            starter: """
            def train(xs, ys, steps, lr):
                w, b = 0.0, 0.0
                n = len(xs)
                for i in range(steps):
                    # TODO: predictions, MSE loss, gradients, update w and b
                    # print(f"loss {i} {loss}")
                    pass
                return w, b
            """,
            test: """
            xs = [0.0, 1.0, 2.0, 3.0]
            ys = [1.0, 3.0, 5.0, 7.0]
            w, b = train(xs, ys, steps=2000, lr=0.05)
            assert abs(w - 2.0) < 0.05 and abs(b - 1.0) < 0.05
            print("✅ All tests passed")
            """,
            reference: "Ng C1")
    ]

    // MARK: Module 4 — Transformers (PyTorch)

    private static let transformers: [Challenge] = [
        Challenge(
            id: "torch-linear", title: "Linear Layer", module: "4 · Transformers", order: 1, difficulty: .easy,
            prompt: """
            Implement a linear layer in **PyTorch**: `linear(W, b, x)` = **x·Wᵀ + b**
            with tensor ops (no Python loops). *First run pulls the PyTorch image once.*
            """,
            starter: "import torch\n\ndef linear(W, b, x):\n    # TODO: x @ W.T + b\n    pass\n",
            test: """
            import torch
            W = torch.tensor([[1., 2.], [0., 1.], [1., 1.]])
            b = torch.tensor([1., 0., -1.])
            x = torch.tensor([[1., 1.], [2., 0.]])
            out = linear(W, b, x)
            assert out.shape == (2, 3)
            assert torch.allclose(out, x @ W.T + b)
            print("✅ All tests passed")
            """,
            reference: "Karpathy makemore", image: torchImage),
        Challenge(
            id: "layernorm", title: "LayerNorm", module: "4 · Transformers", order: 2, difficulty: .medium,
            prompt: """
            Implement **LayerNorm** over the last dim in PyTorch:
            `(x − mean) / sqrt(var + eps) · gamma + beta`. Use **biased** variance.
            """,
            starter: "import torch\n\ndef layer_norm(x, gamma, beta, eps=1e-5):\n    # TODO: normalize over the last dimension\n    pass\n",
            test: """
            import torch
            import torch.nn.functional as F
            torch.manual_seed(0)
            x = torch.randn(4, 8)
            g = torch.ones(8); b = torch.zeros(8)
            out = layer_norm(x, g, b)
            expected = F.layer_norm(x, (8,), g, b)
            assert torch.allclose(out, expected, atol=1e-5)
            print("✅ All tests passed")
            """,
            reference: "Ba et al. 2016", image: torchImage),
        Challenge(
            id: "attention", title: "Scaled Dot-Product Attention", module: "4 · Transformers", order: 3, difficulty: .hard,
            prompt: """
            Implement **scaled dot-product attention** in PyTorch:
            **softmax(Q·Kᵀ / √d_k)·V**, where the last dim is d_k. From
            *Attention Is All You Need*.
            """,
            starter: "import torch\nimport torch.nn.functional as F\n\ndef attention(Q, K, V):\n    # TODO: softmax(Q @ K.transpose(-2,-1) / sqrt(d_k)) @ V\n    pass\n",
            test: """
            import torch
            import torch.nn.functional as F
            torch.manual_seed(0)
            Q = torch.randn(2, 3, 4); K = torch.randn(2, 3, 4); V = torch.randn(2, 3, 4)
            out = attention(Q, K, V)
            expected = F.scaled_dot_product_attention(Q, K, V)
            assert out.shape == (2, 3, 4)
            assert torch.allclose(out, expected, atol=1e-5)
            print("✅ All tests passed")
            """,
            reference: "arxiv 1706.03762", image: torchImage),
        Challenge(
            id: "causal-attention", title: "Causal (Masked) Attention", module: "4 · Transformers", order: 4, difficulty: .medium,
            prompt: """
            Make attention **autoregressive**: position *i* may only attend to
            positions **≤ i**. Mask the future with **−∞** before softmax, then
            `softmax(scores)·V`. This is the core of a GPT decoder.
            """,
            starter: "import torch\nimport torch.nn.functional as F\n\ndef causal_attention(Q, K, V):\n    # TODO: mask scores where j > i with -inf, then softmax @ V\n    pass\n",
            test: """
            import torch
            import torch.nn.functional as F
            torch.manual_seed(0)
            Q = torch.randn(2, 4, 8); K = torch.randn(2, 4, 8); V = torch.randn(2, 4, 8)
            out = causal_attention(Q, K, V)
            expected = F.scaled_dot_product_attention(Q, K, V, is_causal=True)
            assert out.shape == (2, 4, 8)
            assert torch.allclose(out, expected, atol=1e-5)
            print("✅ All tests passed")
            """,
            reference: "Karpathy nanoGPT", image: torchImage),
        Challenge(
            id: "multihead-attention", title: "Multi-Head Attention", module: "4 · Transformers", order: 5, difficulty: .hard,
            prompt: """
            Run **`num_heads`** attention heads in parallel. Split the last dim
            `D` into `h` heads of size `d_k = D/h` → shape `(B, h, T, d_k)`, attend
            **per head**, then concatenate back to `(B, T, D)`. No learned
            projections here — just the head split, attention, and merge.
            """,
            starter: "import torch\nimport torch.nn.functional as F\n\ndef multi_head_attention(Q, K, V, num_heads):\n    # TODO: reshape into heads, attend per head, merge back\n    pass\n",
            test: """
            import torch
            import torch.nn.functional as F
            torch.manual_seed(0)
            B, T, D, h = 2, 5, 8, 2
            Q = torch.randn(B, T, D); K = torch.randn(B, T, D); V = torch.randn(B, T, D)
            out = multi_head_attention(Q, K, V, h)
            dk = D // h
            def split(x): return x.view(B, T, h, dk).transpose(1, 2)
            exp = F.scaled_dot_product_attention(split(Q), split(K), split(V))
            exp = exp.transpose(1, 2).contiguous().view(B, T, D)
            assert out.shape == (B, T, D)
            assert torch.allclose(out, exp, atol=1e-5)
            print("✅ All tests passed")
            """,
            reference: "arxiv 1706.03762", image: torchImage),
        Challenge(
            id: "feed-forward", title: "Feed-Forward Network", module: "4 · Transformers", order: 6, difficulty: .medium,
            prompt: """
            Implement a transformer **feed-forward block**: `Linear → GELU →
            Linear`, applied per position. Given weights `W1,b1,W2,b2`, compute
            `gelu(x·W1ᵀ + b1)·W2ᵀ + b2` (PyTorch `nn.Linear` convention).
            """,
            starter: "import torch\nimport torch.nn.functional as F\n\ndef ffn(x, W1, b1, W2, b2):\n    # TODO: gelu(x @ W1.T + b1) @ W2.T + b2\n    pass\n",
            test: """
            import torch
            import torch.nn as nn
            import torch.nn.functional as F
            torch.manual_seed(0)
            d, hidden = 8, 32
            x = torch.randn(2, 5, d)
            lin1 = nn.Linear(d, hidden); lin2 = nn.Linear(hidden, d)
            W1, b1 = lin1.weight.data, lin1.bias.data
            W2, b2 = lin2.weight.data, lin2.bias.data
            out = ffn(x, W1, b1, W2, b2)
            expected = lin2(F.gelu(lin1(x)))
            assert out.shape == (2, 5, d)
            assert torch.allclose(out, expected, atol=1e-5)
            print("✅ All tests passed")
            """,
            reference: "arxiv 1706.03762", image: torchImage),
        Challenge(
            id: "positional-encoding", title: "Sinusoidal Positional Encoding", module: "4 · Transformers", order: 7, difficulty: .medium,
            prompt: """
            Build the original **sinusoidal positional encoding**: a `(T, D)`
            matrix where even dims hold `sin(pos / 10000^(2i/D))` and odd dims hold
            the matching `cos`. Added to embeddings, it tells attention *where*
            each token sits.
            """,
            starter: "import torch\nimport math\n\ndef positional_encoding(T, D):\n    # TODO: even dims = sin, odd dims = cos, geometric wavelengths\n    pass\n",
            test: """
            import torch
            import math
            T, D = 10, 16
            pe = positional_encoding(T, D)
            assert pe.shape == (T, D)
            # position 0: sin(0)=0 on even dims, cos(0)=1 on odd dims
            assert torch.allclose(pe[0, 0::2], torch.zeros(D // 2), atol=1e-6)
            assert torch.allclose(pe[0, 1::2], torch.ones(D // 2), atol=1e-6)
            pos = torch.arange(T).unsqueeze(1).float()
            div = torch.exp(torch.arange(0, D, 2).float() * (-math.log(10000.0) / D))
            ref = torch.zeros(T, D)
            ref[:, 0::2] = torch.sin(pos * div)
            ref[:, 1::2] = torch.cos(pos * div)
            assert torch.allclose(pe, ref, atol=1e-5)
            print("✅ All tests passed")
            """,
            reference: "arxiv 1706.03762", image: torchImage)
    ]

    // MARK: Module 5 — Build a GPT (PyTorch)

    private static let buildGPT: [Challenge] = [
        Challenge(
            id: "bpe-train", title: "BPE Tokenizer", module: "5 · Build a GPT", order: 1, difficulty: .medium,
            prompt: """
            Train a **byte-pair encoding** tokenizer. Implement three functions:
            `get_stats(ids)` → counts of adjacent pairs; `merge(ids, pair, idx)` →
            the list with every consecutive `pair` replaced by `idx`; and
            `train_bpe(ids, num_merges)` → runs `num_merges` rounds, each time
            merging the **most frequent pair** (`max(stats, key=stats.get)`) into a
            new id starting at **256**. Return `(ids_after, merges)` where `merges`
            is a list of `((a, b), idx)` in order. *(Pure Python — no torch.)*
            """,
            starter: """
            def get_stats(ids):
                # TODO: return dict {(a, b): count} over adjacent pairs
                pass

            def merge(ids, pair, idx):
                # TODO: replace each consecutive `pair` with `idx`; return new list
                pass

            def train_bpe(ids, num_merges):
                # TODO: run num_merges rounds; new ids start at 256
                #       return (ids_after, merges) with merges = [((a, b), idx), ...]
                pass
            """,
            test: """
            text = "the cat sat on the mat the cat ran the cat sat"
            ids = list(text.encode("utf-8"))
            out, merges = train_bpe(list(ids), 6)

            def _stats(x):
                d = {}
                for a, b in zip(x, x[1:]):
                    d[(a, b)] = d.get((a, b), 0) + 1
                return d
            def _merge(x, pair, idx):
                r, i = [], 0
                while i < len(x):
                    if i < len(x) - 1 and x[i] == pair[0] and x[i + 1] == pair[1]:
                        r.append(idx); i += 2
                    else:
                        r.append(x[i]); i += 1
                return r
            ref, ref_merges, nid = list(ids), [], 256
            for _ in range(6):
                s = _stats(ref)
                if not s:
                    break
                pair = max(s, key=s.get)
                ref = _merge(ref, pair, nid)
                ref_merges.append((pair, nid)); nid += 1

            assert get_stats(list(ids))[(ids[0], ids[1])] >= 1
            assert merges == ref_merges, "merge list mismatch"
            assert out == ref, "encoded ids mismatch"
            assert merges[0][1] == 256
            print("✅ All tests passed")
            """,
            reference: "Karpathy minBPE"),
        Challenge(
            id: "gpt-block", title: "GPT Block", module: "5 · Build a GPT", order: 2, difficulty: .hard,
            prompt: """
            Implement one **pre-norm decoder block**. In `forward`, do
            `x = x + attn(ln1(x))` using **causal** multi-head self-attention, then
            `x = x + mlp(ln2(x))`. The submodules are wired for you — split `qkv`
            into heads, attend causally, merge, project. Causality is the test:
            changing a later token must **not** affect earlier outputs.
            """,
            starter: """
            import torch
            import torch.nn as nn
            import torch.nn.functional as F

            class GPTBlock(nn.Module):
                def __init__(self, n_embd, n_head):
                    super().__init__()
                    self.n_head = n_head
                    self.ln1 = nn.LayerNorm(n_embd)
                    self.ln2 = nn.LayerNorm(n_embd)
                    self.qkv = nn.Linear(n_embd, 3 * n_embd)
                    self.proj = nn.Linear(n_embd, n_embd)
                    self.mlp = nn.Sequential(
                        nn.Linear(n_embd, 4 * n_embd), nn.GELU(),
                        nn.Linear(4 * n_embd, n_embd),
                    )

                def forward(self, x):
                    B, T, C = x.shape
                    # TODO:
                    #  1. a = ln1(x); q, k, v = self.qkv(a).split(C, dim=2)
                    #  2. reshape each to (B, n_head, T, C // n_head)
                    #  3. causal attention (F.scaled_dot_product_attention is_causal=True)
                    #  4. merge heads -> (B, T, C); x = x + self.proj(att)
                    #  5. x = x + self.mlp(self.ln2(x)); return x
                    pass
            """,
            test: """
            import torch
            torch.manual_seed(0)
            block = GPTBlock(n_embd=16, n_head=4)
            x = torch.randn(1, 6, 16)
            y1 = block(x)
            assert y1.shape == (1, 6, 16)
            # causality: changing the LAST token must not affect earlier outputs
            x2 = x.clone()
            x2[:, 5, :] = torch.randn(16)
            y2 = block(x2)
            assert torch.allclose(y1[:, :5], y2[:, :5], atol=1e-5), "block is not causal"
            # ...but it must still attend (the last position should change)
            assert not torch.allclose(y1[:, 5], y2[:, 5], atol=1e-5)
            print("✅ All tests passed")
            """,
            reference: "Karpathy nanoGPT", image: torchImage),
        Challenge(
            id: "tiny-gpt", title: "Tiny GPT (train it)", module: "5 · Build a GPT", order: 3, difficulty: .hard,
            prompt: """
            Assemble a working GPT. Build `TinyGPT` from **token embedding +
            position embedding → the block stack → final LayerNorm → an lm_head**
            returning logits of shape `(B, T, vocab_size)`. The block is provided.
            If it's wired correctly it will **overfit a tiny batch** — the test
            trains it and checks the loss collapses.
            """,
            starter: """
            import torch
            import torch.nn as nn
            import torch.nn.functional as F

            class GPTBlock(nn.Module):
                def __init__(self, n_embd, n_head):
                    super().__init__()
                    self.n_head = n_head
                    self.ln1 = nn.LayerNorm(n_embd)
                    self.ln2 = nn.LayerNorm(n_embd)
                    self.qkv = nn.Linear(n_embd, 3 * n_embd)
                    self.proj = nn.Linear(n_embd, n_embd)
                    self.mlp = nn.Sequential(
                        nn.Linear(n_embd, 4 * n_embd), nn.GELU(),
                        nn.Linear(4 * n_embd, n_embd),
                    )

                def forward(self, x):
                    B, T, C = x.shape
                    a = self.ln1(x)
                    q, k, v = self.qkv(a).split(C, dim=2)
                    h = self.n_head
                    q = q.view(B, T, h, C // h).transpose(1, 2)
                    k = k.view(B, T, h, C // h).transpose(1, 2)
                    v = v.view(B, T, h, C // h).transpose(1, 2)
                    att = F.scaled_dot_product_attention(q, k, v, is_causal=True)
                    att = att.transpose(1, 2).contiguous().view(B, T, C)
                    x = x + self.proj(att)
                    x = x + self.mlp(self.ln2(x))
                    return x

            class TinyGPT(nn.Module):
                def __init__(self, vocab_size, block_size, n_embd, n_head, n_layer):
                    super().__init__()
                    # TODO: self.tok_emb = nn.Embedding(vocab_size, n_embd)
                    #       self.pos_emb = nn.Embedding(block_size, n_embd)
                    #       self.blocks  = nn.ModuleList(GPTBlock(...) x n_layer)
                    #       self.ln_f    = nn.LayerNorm(n_embd)
                    #       self.head    = nn.Linear(n_embd, vocab_size)
                    pass

                def forward(self, idx):
                    # TODO: x = tok_emb(idx) + pos_emb(arange(T)); run blocks;
                    #       return head(ln_f(x))  -> (B, T, vocab_size)
                    pass
            """,
            test: """
            import torch
            import torch.nn.functional as F
            torch.manual_seed(0)
            vocab, T = 16, 8
            model = TinyGPT(vocab_size=vocab, block_size=T, n_embd=32, n_head=4, n_layer=2)
            x = torch.randint(0, vocab, (4, T))
            logits = model(x)
            assert logits.shape == (4, T, vocab)
            y = torch.randint(0, vocab, (4, T))
            opt = torch.optim.Adam(model.parameters(), lr=1e-2)
            first = last = None
            for step in range(60):
                logits = model(x)
                loss = F.cross_entropy(logits.view(-1, vocab), y.view(-1))
                opt.zero_grad(); loss.backward(); opt.step()
                if step == 0:
                    first = loss.item()
                last = loss.item()
            assert last < first * 0.4, f"loss did not drop enough: {first:.3f} -> {last:.3f}"
            print("✅ All tests passed")
            """,
            reference: "Karpathy nanoGPT", image: torchImage),
        Challenge(
            id: "gpt-generate", title: "Generation", module: "5 · Build a GPT", order: 4, difficulty: .medium,
            prompt: """
            Implement greedy **autoregressive generation**. Loop `max_new_tokens`
            times: crop `idx` to the last `block_size` tokens, run the model, take
            the **last** step's logits, append `argmax`. Return the extended `idx`.
            (Temperature and top-k are the same loop with a sample instead of an
            argmax.)
            """,
            starter: """
            import torch

            def generate(model, idx, max_new_tokens, block_size):
                # idx: (B, T) tensor of token ids. Append max_new_tokens greedily.
                # Each step: crop to last block_size, take last-step logits, argmax.
                # TODO
                pass
            """,
            test: """
            import torch
            import torch.nn as nn

            class FixedModel(nn.Module):
                def __init__(self, vocab):
                    super().__init__(); self.vocab = vocab
                def forward(self, idx):
                    B, T = idx.shape
                    logits = torch.zeros(B, T, self.vocab)
                    logits[:, :, 3] = 10.0   # always favors token 3
                    return logits

            m = FixedModel(8)
            out = generate(m, torch.tensor([[0]]), max_new_tokens=5, block_size=4)
            assert out.shape == (1, 6)
            assert out[0, 0].item() == 0
            assert out[0, 1:].tolist() == [3, 3, 3, 3, 3]
            # context cropping must not crash when the sequence exceeds block_size
            out2 = generate(m, torch.tensor([[1, 2, 3]]), max_new_tokens=4, block_size=2)
            assert out2.shape == (1, 7)
            print("✅ All tests passed")
            """,
            reference: "Karpathy nanoGPT", image: torchImage)
    ]

    // MARK: Module 6 — Modern LLMs (PyTorch · llama2.c reference)

    private static let modernLLMs: [Challenge] = [
        Challenge(
            id: "rmsnorm", title: "RMSNorm", module: "6 · Modern LLMs", order: 1, difficulty: .medium,
            prompt: """
            Implement **RMSNorm** — LayerNorm without the mean. Normalize each token
            by its root-mean-square, then scale by a learned `weight`:
            `x · rsqrt(mean(x²) + eps) · weight`, reducing over the **last** dim.
            No centering, no bias. Verified against `F.rms_norm`.
            """,
            starter: """
            import torch

            def rms_norm(x, weight, eps=1e-5):
                # TODO: x * rsqrt(mean(x**2, last dim, keepdim) + eps) * weight
                pass
            """,
            test: """
            import torch
            import torch.nn.functional as F
            torch.manual_seed(0)
            D = 8
            x = torch.randn(4, 3, D)
            w = torch.randn(D)
            out = rms_norm(x, w, eps=1e-5)
            expected = F.rms_norm(x, (D,), w, eps=1e-5)
            assert out.shape == (4, 3, D)
            assert torch.allclose(out, expected, atol=1e-5)
            # RMSNorm does NOT subtract the mean — adding a constant must change the output
            assert not torch.allclose(rms_norm(x + 5.0, w), out, atol=1e-3)
            print("✅ All tests passed")
            """,
            reference: "Zhang & Sennrich 2019", image: torchImage),
        Challenge(
            id: "rope", title: "Rotary Position Embeddings (RoPE)", module: "6 · Modern LLMs", order: 2, difficulty: .hard,
            prompt: """
            Implement **RoPE**. Treat the head dim as `d/2` consecutive pairs and
            **rotate** pair `i` of the token at position `m` by angle `m·θᵢ` (the
            `cos`/`sin` tables are precomputed for you). Input `x` is
            `(B, T, H, d)`; rotate each `(x₂ᵢ, x₂ᵢ₊₁)` pair. The rotation is
            orthogonal (norm-preserving) and makes attention scores depend only on
            **relative** position — both are tested.
            """,
            starter: """
            import torch

            def precompute_freqs_cis(dim, end, theta=10000.0):
                freqs = 1.0 / (theta ** (torch.arange(0, dim, 2)[: dim // 2].float() / dim))
                t = torch.arange(end)
                freqs = torch.outer(t, freqs).float()
                return torch.cos(freqs), torch.sin(freqs)   # each (end, dim/2)

            def apply_rope(x, freqs_cos, freqs_sin):
                # x: (B, T, H, d). Split the last dim into pairs (xr, xi):
                #   xr, xi = x.reshape(*x.shape[:-1], -1, 2).unbind(-1)   # (B,T,H,d/2)
                # Rotate each pair by the per-position angle:
                #   out_r = xr*cos - xi*sin ;  out_i = xr*sin + xi*cos
                # Re-interleave: stack([out_r, out_i], -1).flatten(3). Broadcast the
                # (T, d/2) tables as (1, T, 1, d/2).
                # TODO
                pass
            """,
            test: """
            import torch
            torch.manual_seed(0)
            T, H, D = 6, 2, 8
            fc, fs = precompute_freqs_cis(D, T)
            qvec = torch.randn(1, 1, H, D); kvec = torch.randn(1, 1, H, D)
            q = qvec.expand(1, T, H, D).contiguous()
            k = kvec.expand(1, T, H, D).contiguous()
            qr = apply_rope(q, fc, fs); kr = apply_rope(k, fc, fs)
            assert qr.shape == (1, T, H, D)
            # 1) rotation preserves the per-vector norm
            assert torch.allclose(qr.norm(dim=-1), q.norm(dim=-1), atol=1e-4), "norm not preserved"
            # 2) scores depend only on relative position (shift both -> unchanged)
            score = torch.einsum('mhd,nhd->hmn', qr[0], kr[0])
            assert torch.allclose(score[:, 1:, 1:], score[:, :-1, :-1], atol=1e-4), "not relative"
            # 3) matches the reference rotation
            xr, xi = q.float().reshape(1, T, H, -1, 2).unbind(-1)
            cb = fc.view(1, T, 1, -1); sb = fs.view(1, T, 1, -1)
            ref = torch.stack([xr * cb - xi * sb, xr * sb + xi * cb], dim=-1).flatten(3)
            assert torch.allclose(qr, ref, atol=1e-5)
            print("✅ All tests passed")
            """,
            reference: "Su et al. 2021 (RoFormer)", image: torchImage),
        Challenge(
            id: "swiglu", title: "SwiGLU Feed-Forward", module: "6 · Modern LLMs", order: 3, difficulty: .medium,
            prompt: """
            Implement the **SwiGLU** feed-forward block used in Llama:
            `w2( SiLU(w1·x) ⊙ w3·x )`, where `⊙` is elementwise multiply and
            `SiLU(z) = z·σ(z)`. `w1` is the gate, `w3` the up-projection, `w2` the
            down-projection (all passed as `nn.Linear`).
            """,
            starter: """
            import torch
            import torch.nn.functional as F

            def swiglu_ffn(x, w1, w3, w2):
                # gate = SiLU(w1(x)) ; value = w3(x) ; return w2(gate * value)
                # TODO
                pass
            """,
            test: """
            import torch
            import torch.nn as nn
            import torch.nn.functional as F
            torch.manual_seed(0)
            d, hidden = 8, 16
            x = torch.randn(2, 5, d)
            w1 = nn.Linear(d, hidden, bias=False)
            w3 = nn.Linear(d, hidden, bias=False)
            w2 = nn.Linear(hidden, d, bias=False)
            out = swiglu_ffn(x, w1, w3, w2)
            expected = w2(F.silu(w1(x)) * w3(x))
            assert out.shape == (2, 5, d)
            assert torch.allclose(out, expected, atol=1e-5)
            # must be SiLU-gated, not a plain ReLU MLP
            assert not torch.allclose(out, w2(F.relu(w1(x)) * w3(x)), atol=1e-3)
            print("✅ All tests passed")
            """,
            reference: "Shazeer 2020 (GLU Variants)", image: torchImage),
        Challenge(
            id: "gqa", title: "Grouped-Query Attention", module: "6 · Modern LLMs", order: 4, difficulty: .hard,
            prompt: """
            Implement **GQA**, where query heads share K/V heads in groups. Write
            `repeat_kv(x, n_rep)` — duplicate each of the `n_kv_heads` heads
            `n_rep` times by **interleaving** (`torch.repeat_interleave` on the head
            dim) — then `gqa(q, k, v, n_rep)`: repeat K/V up to the query-head
            count and run causal attention. Shapes are `(B, T, heads, head_dim)`.
            """,
            starter: """
            import torch
            import torch.nn.functional as F

            def repeat_kv(x, n_rep):
                # x: (B, T, n_kv_heads, head_dim) -> (B, T, n_kv_heads*n_rep, head_dim)
                # interleave each head n_rep times (use expand+reshape or repeat_interleave)
                # TODO
                pass

            def gqa(q, k, v, n_rep):
                # repeat_kv on k and v, then causal scaled-dot-product attention.
                # q: (B,T,nh,hd)  k,v: (B,T,nkv,hd) -> out (B,T,nh,hd)
                # (transpose to (B, heads, T, hd) for F.scaled_dot_product_attention)
                # TODO
                pass
            """,
            test: """
            import torch
            import torch.nn.functional as F
            torch.manual_seed(0)
            B, T, nh, nkv, hd = 1, 5, 4, 2, 8
            n_rep = nh // nkv
            q = torch.randn(B, T, nh, hd)
            k = torch.randn(B, T, nkv, hd)
            v = torch.randn(B, T, nkv, hd)
            rk = repeat_kv(k, n_rep)
            assert rk.shape == (B, T, nh, hd)
            assert torch.allclose(rk, torch.repeat_interleave(k, n_rep, dim=2)), "must interleave"
            out = gqa(q, k, v, n_rep)
            assert out.shape == (B, T, nh, hd)
            kk = torch.repeat_interleave(k, n_rep, dim=2).transpose(1, 2)
            vv = torch.repeat_interleave(v, n_rep, dim=2).transpose(1, 2)
            ref = F.scaled_dot_product_attention(q.transpose(1, 2), kk, vv, is_causal=True).transpose(1, 2)
            assert torch.allclose(out, ref, atol=1e-5)
            print("✅ All tests passed")
            """,
            reference: "Ainslie et al. 2023 (GQA)", image: torchImage),
        Challenge(
            id: "kv-cache", title: "KV Cache", module: "6 · Modern LLMs", order: 5, difficulty: .medium,
            prompt: """
            Implement a **KV cache** for autoregressive decoding. `update(k, v)`
            appends the new token's key/value (`(B, 1, H, hd)`) to the running cache
            along the time dim and returns the full cached `(K, V)`. Decoding one
            token at a time through the cache must equal one full causal forward —
            that's the test.
            """,
            starter: """
            import torch

            class KVCache:
                def __init__(self):
                    self.k = None
                    self.v = None

                def update(self, k, v):
                    # Append k, v (each (B, 1, H, hd)) along dim=1; return (self.k, self.v).
                    # First call: the cache simply becomes k, v.
                    # TODO
                    pass
            """,
            test: """
            import torch
            import torch.nn.functional as F
            torch.manual_seed(0)
            B, H, hd, T = 1, 2, 8, 5
            K = torch.randn(B, T, H, hd); V = torch.randn(B, T, H, hd); Q = torch.randn(B, T, H, hd)

            def attn(q, k, v, causal):
                q = q.transpose(1, 2); k = k.transpose(1, 2); v = v.transpose(1, 2)
                return F.scaled_dot_product_attention(q, k, v, is_causal=causal).transpose(1, 2)

            full = attn(Q, K, V, True)          # reference: one causal forward
            cache = KVCache(); outs = []
            for t in range(T):                  # decode one token at a time
                k_all, v_all = cache.update(K[:, t:t+1], V[:, t:t+1])
                outs.append(attn(Q[:, t:t+1], k_all, v_all, False))
            step = torch.cat(outs, dim=1)
            assert step.shape == (B, T, H, hd)
            assert torch.allclose(step, full, atol=1e-5), "cached decode != full causal attention"
            assert cache.k.shape == (B, T, H, hd)
            print("✅ All tests passed")
            """,
            reference: "Karpathy nanoGPT", image: torchImage),
        Challenge(
            id: "llama-block", title: "Llama Block (capstone)", module: "6 · Modern LLMs", order: 6, difficulty: .hard,
            prompt: """
            Assemble a **Llama decoder block** from everything in this module:
            pre-norm residuals with **RMSNorm**, attention with **RoPE** on Q/K and
            **GQA**, then a **SwiGLU** feed-forward. The helpers are provided — wire
            the `forward`: `h = x + attn(rmsnorm(x))`, `out = h + swiglu(rmsnorm(h))`.
            The test checks it's **causal** (a later token can't change earlier
            outputs).
            """,
            starter: """
            import torch
            import torch.nn as nn
            import torch.nn.functional as F

            def precompute_freqs_cis(dim, end, theta=10000.0):
                freqs = 1.0 / (theta ** (torch.arange(0, dim, 2)[: dim // 2].float() / dim))
                freqs = torch.outer(torch.arange(end), freqs).float()
                return torch.cos(freqs), torch.sin(freqs)

            def apply_rope(x, fc, fs):
                xr, xi = x.float().reshape(*x.shape[:-1], -1, 2).unbind(-1)
                T = x.shape[1]
                fc = fc.view(1, T, 1, -1); fs = fs.view(1, T, 1, -1)
                return torch.stack([xr*fc - xi*fs, xr*fs + xi*fc], dim=-1).flatten(3).type_as(x)

            def repeat_kv(x, n_rep):
                b, t, nkv, hd = x.shape
                if n_rep == 1: return x
                return x[:, :, :, None, :].expand(b, t, nkv, n_rep, hd).reshape(b, t, nkv*n_rep, hd)

            class LlamaBlock(nn.Module):
                def __init__(self, dim, n_heads, n_kv_heads):
                    super().__init__()
                    self.nh, self.nkv = n_heads, n_kv_heads
                    self.hd = dim // n_heads
                    self.n_rep = n_heads // n_kv_heads
                    self.attn_norm = nn.RMSNorm(dim)
                    self.ffn_norm = nn.RMSNorm(dim)
                    self.wq = nn.Linear(dim, n_heads * self.hd, bias=False)
                    self.wk = nn.Linear(dim, n_kv_heads * self.hd, bias=False)
                    self.wv = nn.Linear(dim, n_kv_heads * self.hd, bias=False)
                    self.wo = nn.Linear(n_heads * self.hd, dim, bias=False)
                    hidden = 4 * dim
                    self.w1 = nn.Linear(dim, hidden, bias=False)
                    self.w3 = nn.Linear(dim, hidden, bias=False)
                    self.w2 = nn.Linear(hidden, dim, bias=False)

                def forward(self, x, fc, fs):
                    B, T, C = x.shape
                    # TODO — attention sub-layer:
                    #   a = self.attn_norm(x)
                    #   q = self.wq(a).view(B, T, self.nh,  self.hd)
                    #   k = self.wk(a).view(B, T, self.nkv, self.hd)
                    #   v = self.wv(a).view(B, T, self.nkv, self.hd)
                    #   q, k = apply_rope(q, fc, fs), apply_rope(k, fc, fs)
                    #   k, v = repeat_kv(k, self.n_rep), repeat_kv(v, self.n_rep)
                    #   o = causal scaled_dot_product_attention over (B, heads, T, hd)
                    #   h = x + self.wo(o.reshape(B, T, -1))
                    # TODO — SwiGLU sub-layer:
                    #   n = self.ffn_norm(h)
                    #   return h + self.w2(F.silu(self.w1(n)) * self.w3(n))
                    pass
            """,
            test: """
            import torch
            torch.manual_seed(0)
            dim, nh, nkv, T = 16, 4, 2, 6
            block = LlamaBlock(dim, nh, nkv)
            fc, fs = precompute_freqs_cis(dim // nh, T)
            x = torch.randn(1, T, dim)
            y1 = block(x, fc, fs)
            assert y1.shape == (1, T, dim)
            # causality: changing the last token must not affect earlier outputs
            x2 = x.clone(); x2[:, 5, :] = torch.randn(dim)
            y2 = block(x2, fc, fs)
            assert torch.allclose(y1[:, :5], y2[:, :5], atol=1e-5), "Llama block is not causal"
            assert not torch.allclose(y1[:, 5], y2[:, 5], atol=1e-5)
            print("✅ All tests passed")
            """,
            reference: "Karpathy llama2.c", image: torchImage)
    ]
}
