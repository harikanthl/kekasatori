//
//  TaskTaxonomyStore.swift
//  MuseDrop
//
//  Loads the bundled research-task taxonomy that powers Discover's "browse by
//  area" spine. Prefers a bundled `ResearchTaxonomy.json` snapshot when present
//  (so a refreshed dump can drop in without a code change), and otherwise falls
//  back to the curated in-binary snapshot below — guaranteeing the browser
//  always has content, offline and with no network.
//
//  The default snapshot mirrors the Papers With Code "tasks" page: 6 areas,
//  74 tasks, with paper counts captured at snapshot time. Area descriptions are
//  PWC's own. Counts go stale; refresh by replacing the JSON.
//

import Foundation

struct TaskTaxonomyStore: Sendable {
    let areas: [ResearchArea]

    static let shared = TaskTaxonomyStore(areas: loadBundled())

    /// JSON snapshot if bundled & decodable; otherwise the embedded default.
    static func loadBundled() -> [ResearchArea] {
        if let url = Bundle.main.url(forResource: "ResearchTaxonomy", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([ResearchArea].self, from: data),
           !decoded.isEmpty {
            return decoded
        }
        return defaultSnapshot
    }

    // MARK: - Curated snapshot (Papers With Code tasks page)

    static let defaultSnapshot: [ResearchArea] = [
        ResearchArea(
            id: "general", name: "General", symbol: "square.grid.2x2",
            blurb: "A broad category encompassing machine learning research and tasks that don't fit specifically into vision or language domains, including general ML methods, optimization, and cross-domain approaches.",
            paperCount: 54_869,
            arxivCategories: ["cs.LG", "cs.AI", "stat.ML"], searchAnchor: "machine learning",
            tasks: [
                ResearchTask(name: "Agents", paperCount: 1_122, query: "LLM agents"),
                ResearchTask(name: "Anomaly Detection", paperCount: 394),
                ResearchTask(name: "Autonomous Driving", paperCount: 353),
                ResearchTask(name: "Coding Agents", paperCount: 311),
                ResearchTask(name: "Computer Use Agents", paperCount: 311),
                ResearchTask(name: "Deepfake And Forensics", paperCount: 217, query: "deepfake detection forensics"),
                ResearchTask(name: "Document Understanding", paperCount: 446),
                ResearchTask(name: "Embedding Models", paperCount: 957, query: "text embedding models"),
                ResearchTask(name: "Language Modeling", paperCount: 37_043),
                ResearchTask(name: "OCR", paperCount: 497, query: "optical character recognition"),
                ResearchTask(name: "Omni Models", paperCount: 166, query: "omni-modal foundation models"),
                ResearchTask(name: "Reasoning", paperCount: 3_396, query: "reasoning large language models"),
                ResearchTask(name: "Reinforcement Learning", paperCount: 7_169),
                ResearchTask(name: "Remote Sensing", paperCount: 661),
                ResearchTask(name: "Robotics", paperCount: 779),
                ResearchTask(name: "Scene Text Recognition", paperCount: 182),
                ResearchTask(name: "World Models", paperCount: 865, query: "world models reinforcement learning"),
            ]),
        ResearchArea(
            id: "vision", name: "Vision", symbol: "eye",
            blurb: "Research on enabling machines to interpret and understand still images, including image classification, generation, editing, segmentation, detection, depth, and 3D understanding.",
            paperCount: 27_506,
            arxivCategories: ["cs.CV"], searchAnchor: "computer vision",
            openAlexConcept: "C31972630",
            tasks: [
                ResearchTask(name: "3D generation", paperCount: 2_332),
                ResearchTask(name: "3D instance segmentation", paperCount: 70),
                ResearchTask(name: "3D object detection", paperCount: 325),
                ResearchTask(name: "3D semantic segmentation", paperCount: 136),
                ResearchTask(name: "3D understanding", paperCount: 1_270),
                ResearchTask(name: "Depth Estimation", paperCount: 862),
                ResearchTask(name: "Document Layout Analysis", paperCount: 150),
                ResearchTask(name: "Face Recognition", paperCount: 172),
                ResearchTask(name: "Face Verification", paperCount: 170),
                ResearchTask(name: "Image Classification", paperCount: 2_053),
                ResearchTask(name: "Image Editing", paperCount: 777),
                ResearchTask(name: "Image Generation", paperCount: 3_114),
                ResearchTask(name: "Image Inpainting", paperCount: 699),
                ResearchTask(name: "Image Matching", paperCount: 183),
                ResearchTask(name: "Image Matting", paperCount: 23),
                ResearchTask(name: "Image Restoration", paperCount: 462),
                ResearchTask(name: "Image Segmentation", paperCount: 2_137),
                ResearchTask(name: "Image Super-Resolution", paperCount: 261),
                ResearchTask(name: "Image Understanding", paperCount: 7_620),
                ResearchTask(name: "Medical Imaging", paperCount: 1_001),
                ResearchTask(name: "Motion Generation", paperCount: 366),
                ResearchTask(name: "Object Counting", paperCount: 99),
                ResearchTask(name: "Object Detection", paperCount: 1_654),
                ResearchTask(name: "Optical Flow", paperCount: 80, query: "optical flow estimation"),
                ResearchTask(name: "Pose Estimation", paperCount: 875),
                ResearchTask(name: "Semi-Supervised Image Classification", paperCount: 400),
                ResearchTask(name: "Stereo Matching", paperCount: 87),
                ResearchTask(name: "Zero-Shot Segmentation", paperCount: 128),
            ]),
        ResearchArea(
            id: "video", name: "Video", symbol: "film",
            blurb: "Research on understanding, classifying, segmenting, and generating video, including temporal modeling across frames.",
            paperCount: 3_964,
            arxivCategories: ["cs.CV"], searchAnchor: "video understanding generation",
            openAlexConcept: "C31972630",
            tasks: [
                ResearchTask(name: "Cross-View Object Correspondence", paperCount: 13),
                ResearchTask(name: "Object Tracking", paperCount: 170),
                ResearchTask(name: "Video Classification", paperCount: 1_222),
                ResearchTask(name: "Video Generation", paperCount: 1_989),
                ResearchTask(name: "Video Matting", paperCount: 17),
                ResearchTask(name: "Video Restoration", paperCount: 56),
                ResearchTask(name: "Video Segmentation", paperCount: 224),
                ResearchTask(name: "Video Super-Resolution", paperCount: 92),
                ResearchTask(name: "Video Understanding", paperCount: 181),
            ]),
        ResearchArea(
            id: "language", name: "Language", symbol: "text.bubble",
            blurb: "Research on understanding and generating human language, including machine translation, text classification, and other NLP tasks (note: language modeling lives under General).",
            paperCount: 8_266,
            arxivCategories: ["cs.CL"], searchAnchor: "natural language processing",
            openAlexConcept: "C204321447",
            tasks: [
                ResearchTask(name: "Entity Typing", paperCount: 14),
                ResearchTask(name: "Machine Translation", paperCount: 1_124),
                ResearchTask(name: "Named Entity Recognition", paperCount: 518),
                ResearchTask(name: "Part-Of-Speech Tagging", paperCount: 109),
                ResearchTask(name: "Question Answering", paperCount: 4_194),
                ResearchTask(name: "Relation Extraction", paperCount: 189),
                ResearchTask(name: "Summarization", paperCount: 1_229, query: "text summarization"),
                ResearchTask(name: "Table Question Answering", paperCount: 103),
                ResearchTask(name: "Text Classification", paperCount: 423),
                ResearchTask(name: "Text-to-SQL", paperCount: 363),
            ]),
        ResearchArea(
            id: "audio", name: "Audio", symbol: "waveform",
            blurb: "Research on processing, understanding, and generating audio signals, including speech recognition, music generation, sound classification, and audio synthesis.",
            paperCount: 3_027,
            arxivCategories: ["eess.AS", "cs.SD"], searchAnchor: "speech audio processing",
            openAlexConcept: "C28490314",
            tasks: [
                ResearchTask(name: "Audio Classification", paperCount: 60),
                ResearchTask(name: "Audio Generation", paperCount: 474),
                ResearchTask(name: "Audio Understanding", paperCount: 244),
                ResearchTask(name: "Automatic Speech Recognition", paperCount: 1_461),
                ResearchTask(name: "Text-To-Speech", paperCount: 703),
                ResearchTask(name: "Voice Cloning", paperCount: 85),
            ]),
        ResearchArea(
            id: "other", name: "Other", symbol: "atom",
            blurb: "Research that does not fit into the main modality areas (Vision, Video, Language, Audio, General), including AI for biology, time-series modeling, and other cross-domain or niche tasks.",
            paperCount: 742,
            arxivCategories: ["stat.ML", "q-bio.QM"], searchAnchor: "time series tabular learning",
            tasks: [
                ResearchTask(name: "Biology", paperCount: 11, query: "machine learning computational biology"),
                ResearchTask(name: "Tabular Learning", paperCount: 358),
                ResearchTask(name: "Time-Series Classification", paperCount: 62),
                ResearchTask(name: "Time-Series Forecasting", paperCount: 311),
            ]),
    ]

    /// Areas for the active field. AI uses the bundled PWC snapshot; Medicine
    /// uses the curated bio/medical snapshot below.
    static func areas(for field: ResearchField) -> [ResearchArea] {
        switch field {
        case .ai:        return shared.areas
        case .maths:     return mathsSnapshot
        case .physics:   return physicsSnapshot
        case .chemistry: return chemistrySnapshot
        case .medicine:  return medicineSnapshot
        }
    }

    // MARK: - Medicine snapshot (bioRxiv/medRxiv + OpenAlex concepts)

    static let medicineSnapshot: [ResearchArea] = [
        ResearchArea(
            id: "oncology", name: "Oncology", symbol: "cross.case.fill",
            blurb: "Cancer biology and treatment — tumor genomics, immunotherapy, and the tumor microenvironment.",
            searchAnchor: "cancer oncology", openAlexConcept: "C143998085",
            preprintCategories: ["cancer biology", "oncology"],
            tasks: [
                ResearchTask(name: "Cancer Immunotherapy", query: "cancer immunotherapy"),
                ResearchTask(name: "Tumor Microenvironment", query: "tumor microenvironment"),
                ResearchTask(name: "Tumor Genomics", query: "tumor genomics sequencing"),
                ResearchTask(name: "Liquid Biopsy", query: "liquid biopsy circulating tumor DNA"),
                ResearchTask(name: "Targeted Therapy", query: "targeted cancer therapy"),
            ]),
        ResearchArea(
            id: "neuroscience", name: "Neuroscience", symbol: "brain.head.profile",
            blurb: "The brain and nervous system — neurodegeneration, circuits, imaging, and interfaces.",
            searchAnchor: "neuroscience", openAlexConcept: "C169760540",
            preprintCategories: ["neuroscience", "neurology"],
            tasks: [
                ResearchTask(name: "Neurodegeneration", query: "neurodegeneration Alzheimer's disease"),
                ResearchTask(name: "Connectomics", query: "brain connectomics"),
                ResearchTask(name: "Neuroimaging", query: "neuroimaging functional MRI"),
                ResearchTask(name: "Synaptic Plasticity", query: "synaptic plasticity"),
                ResearchTask(name: "Brain-Computer Interface", query: "brain computer interface"),
            ]),
        ResearchArea(
            id: "genomics", name: "Genomics", symbol: "atom",
            blurb: "Genes and genomes — sequencing, variation, gene editing, and expression.",
            searchAnchor: "genomics", openAlexConcept: "C54355233",
            preprintCategories: ["genetics", "genomics", "genetic and genomic medicine", "bioinformatics"],
            tasks: [
                ResearchTask(name: "Single-Cell Genomics", query: "single-cell RNA sequencing"),
                ResearchTask(name: "GWAS", query: "genome-wide association study"),
                ResearchTask(name: "CRISPR Gene Editing", query: "CRISPR gene editing"),
                ResearchTask(name: "Variant Calling", query: "genomic variant calling"),
                ResearchTask(name: "Gene Expression", query: "gene expression regulation"),
            ]),
        ResearchArea(
            id: "immunology", name: "Immunology", symbol: "shield.lefthalf.filled",
            blurb: "The immune system — T-cell biology, vaccines, autoimmunity, and signaling.",
            searchAnchor: "immunology", openAlexConcept: "C203014093",
            preprintCategories: ["immunology"],
            tasks: [
                ResearchTask(name: "T-Cell Immunity", query: "T cell immunity"),
                ResearchTask(name: "Vaccine Development", query: "vaccine development"),
                ResearchTask(name: "Autoimmunity", query: "autoimmune disease"),
                ResearchTask(name: "Cytokine Signaling", query: "cytokine signaling"),
                ResearchTask(name: "mRNA Vaccines", query: "mRNA vaccine"),
            ]),
        ResearchArea(
            id: "cardiology", name: "Cardiology", symbol: "heart.fill",
            blurb: "The heart and circulation — heart failure, arrhythmia, and cardiac imaging.",
            searchAnchor: "cardiology cardiovascular", openAlexConcept: "C164705383",
            preprintCategories: ["cardiovascular medicine", "cardiology"],
            tasks: [
                ResearchTask(name: "Heart Failure", query: "heart failure treatment"),
                ResearchTask(name: "Arrhythmia", query: "cardiac arrhythmia"),
                ResearchTask(name: "Atherosclerosis", query: "atherosclerosis"),
                ResearchTask(name: "Cardiac Imaging", query: "cardiac imaging"),
                ResearchTask(name: "Hypertension", query: "hypertension"),
            ]),
        ResearchArea(
            id: "infectious-disease", name: "Infectious Disease", symbol: "syringe",
            blurb: "Pathogens and outbreaks — antimicrobial resistance, epidemiology, and the microbiome.",
            searchAnchor: "infectious disease epidemiology", openAlexConcept: "C524204448",
            preprintCategories: ["infectious diseases", "microbiology", "epidemiology"],
            tasks: [
                ResearchTask(name: "Antimicrobial Resistance", query: "antimicrobial resistance"),
                ResearchTask(name: "Viral Epidemiology", query: "viral epidemiology"),
                ResearchTask(name: "Vaccine Efficacy", query: "vaccine efficacy"),
                ResearchTask(name: "Microbiome", query: "human microbiome"),
                ResearchTask(name: "Pathogen Genomics", query: "pathogen genomic surveillance"),
            ]),
    ]

    // MARK: - Maths snapshot (arXiv math.* + OpenAlex)

    static let mathsSnapshot: [ResearchArea] = [
        ResearchArea(
            id: "algebra-number-theory", name: "Algebra & Number Theory", symbol: "function",
            blurb: "Structure and arithmetic — algebraic geometry, number theory, and representation theory.",
            arxivCategories: ["math.AG", "math.NT", "math.AC", "math.RT"], searchAnchor: "algebra number theory",
            tasks: [
                ResearchTask(name: "Algebraic Geometry", query: "algebraic geometry"),
                ResearchTask(name: "Number Theory", query: "analytic number theory"),
                ResearchTask(name: "Representation Theory", query: "representation theory"),
                ResearchTask(name: "Commutative Algebra", query: "commutative algebra"),
                ResearchTask(name: "Arithmetic Geometry", query: "arithmetic geometry"),
            ]),
        ResearchArea(
            id: "analysis", name: "Analysis", symbol: "chart.line.uptrend.xyaxis",
            blurb: "Limits, functions, and equations — PDEs, functional and harmonic analysis.",
            arxivCategories: ["math.AP", "math.CA", "math.FA", "math.CV"], searchAnchor: "mathematical analysis", openAlexConcept: "C134306372",
            tasks: [
                ResearchTask(name: "Partial Differential Equations", query: "partial differential equations"),
                ResearchTask(name: "Functional Analysis", query: "functional analysis"),
                ResearchTask(name: "Harmonic Analysis", query: "harmonic analysis"),
                ResearchTask(name: "Complex Analysis", query: "complex analysis"),
                ResearchTask(name: "Dynamical Systems", query: "dynamical systems"),
            ]),
        ResearchArea(
            id: "geometry-topology", name: "Geometry & Topology", symbol: "pyramid",
            blurb: "Shape and space — differential geometry, algebraic and geometric topology.",
            arxivCategories: ["math.DG", "math.GT", "math.AT", "math.SG"], searchAnchor: "geometry topology", openAlexConcept: "C2524010",
            tasks: [
                ResearchTask(name: "Differential Geometry", query: "differential geometry"),
                ResearchTask(name: "Algebraic Topology", query: "algebraic topology"),
                ResearchTask(name: "Geometric Topology", query: "geometric topology"),
                ResearchTask(name: "Symplectic Geometry", query: "symplectic geometry"),
                ResearchTask(name: "Riemannian Geometry", query: "Riemannian geometry"),
            ]),
        ResearchArea(
            id: "probability-statistics", name: "Probability & Statistics", symbol: "chart.bar",
            blurb: "Randomness and inference — stochastic processes, random matrices, and statistical theory.",
            arxivCategories: ["math.PR", "math.ST", "stat.TH"], searchAnchor: "probability statistics", openAlexConcept: "C105795698",
            tasks: [
                ResearchTask(name: "Stochastic Processes", query: "stochastic processes"),
                ResearchTask(name: "Random Matrix Theory", query: "random matrix theory"),
                ResearchTask(name: "Statistical Inference", query: "statistical inference"),
                ResearchTask(name: "Markov Chains", query: "Markov chains"),
            ]),
        ResearchArea(
            id: "combinatorics-logic", name: "Combinatorics & Logic", symbol: "point.3.connected.trianglepath.dotted",
            blurb: "Discrete structures and foundations — graph theory, combinatorics, and mathematical logic.",
            arxivCategories: ["math.CO", "math.LO"], searchAnchor: "combinatorics graph theory", openAlexConcept: "C114614502",
            tasks: [
                ResearchTask(name: "Graph Theory", query: "graph theory"),
                ResearchTask(name: "Combinatorics", query: "extremal combinatorics"),
                ResearchTask(name: "Mathematical Logic", query: "mathematical logic"),
                ResearchTask(name: "Set Theory", query: "set theory"),
            ]),
        ResearchArea(
            id: "applied-numerical", name: "Applied & Numerical", symbol: "function",
            blurb: "Computation and control — numerical analysis, optimization, and applied dynamics.",
            arxivCategories: ["math.NA", "math.OC", "math.DS"], searchAnchor: "numerical analysis optimization",
            tasks: [
                ResearchTask(name: "Numerical Analysis", query: "numerical analysis"),
                ResearchTask(name: "Optimization", query: "convex optimization"),
                ResearchTask(name: "Control Theory", query: "control theory"),
                ResearchTask(name: "Scientific Computing", query: "scientific computing"),
            ]),
    ]

    // MARK: - Physics snapshot (arXiv + OpenAlex)

    static let physicsSnapshot: [ResearchArea] = [
        ResearchArea(
            id: "astrophysics", name: "Astrophysics", symbol: "sparkles",
            blurb: "The cosmos — cosmology, galaxies, black holes, and stars.",
            arxivCategories: ["astro-ph.CO", "astro-ph.GA", "astro-ph.HE", "astro-ph.SR"], searchAnchor: "astrophysics", openAlexConcept: "C1276947",
            tasks: [
                ResearchTask(name: "Cosmology", query: "observational cosmology"),
                ResearchTask(name: "Galaxies", query: "galaxy formation evolution"),
                ResearchTask(name: "Black Holes", query: "black hole astrophysics"),
                ResearchTask(name: "Exoplanets", query: "exoplanet detection"),
                ResearchTask(name: "Stellar Astrophysics", query: "stellar astrophysics"),
            ]),
        ResearchArea(
            id: "condensed-matter", name: "Condensed Matter", symbol: "square.grid.3x3.fill",
            blurb: "Materials and many-body physics — superconductivity, topology, and quantum materials.",
            arxivCategories: ["cond-mat.str-el", "cond-mat.mes-hall", "cond-mat.supr-con", "cond-mat.mtrl-sci"],
            searchAnchor: "condensed matter physics", openAlexConcept: "C26873012",
            tasks: [
                ResearchTask(name: "Superconductivity", query: "superconductivity"),
                ResearchTask(name: "Topological Materials", query: "topological insulators"),
                ResearchTask(name: "Strongly Correlated Systems", query: "strongly correlated electrons"),
                ResearchTask(name: "2D Materials", query: "two-dimensional materials graphene"),
                ResearchTask(name: "Quantum Magnetism", query: "quantum magnetism"),
            ]),
        ResearchArea(
            id: "high-energy", name: "High-Energy Physics", symbol: "burst",
            blurb: "The fundamental — string theory, quantum field theory, and particle physics.",
            arxivCategories: ["hep-th", "hep-ph", "hep-ex", "hep-lat"], searchAnchor: "high energy particle physics", openAlexConcept: "C109214941",
            tasks: [
                ResearchTask(name: "String Theory", query: "string theory"),
                ResearchTask(name: "Quantum Field Theory", query: "quantum field theory"),
                ResearchTask(name: "Particle Physics", query: "particle physics phenomenology"),
                ResearchTask(name: "Lattice QCD", query: "lattice QCD"),
                ResearchTask(name: "Beyond Standard Model", query: "beyond standard model physics"),
            ]),
        ResearchArea(
            id: "quantum", name: "Quantum Physics", symbol: "atom",
            blurb: "Quantum information and matter — computing, error correction, and entanglement.",
            arxivCategories: ["quant-ph"], searchAnchor: "quantum information physics", openAlexConcept: "C62520636",
            tasks: [
                ResearchTask(name: "Quantum Computing", query: "quantum computing"),
                ResearchTask(name: "Quantum Information", query: "quantum information theory"),
                ResearchTask(name: "Quantum Error Correction", query: "quantum error correction"),
                ResearchTask(name: "Entanglement", query: "quantum entanglement"),
                ResearchTask(name: "Quantum Optics", query: "quantum optics"),
            ]),
        ResearchArea(
            id: "gravitation", name: "Gravitation & Relativity", symbol: "circle.circle",
            blurb: "Spacetime and gravity — gravitational waves, black holes, and numerical relativity.",
            arxivCategories: ["gr-qc"], searchAnchor: "general relativity gravitation", openAlexConcept: "C147452769",
            tasks: [
                ResearchTask(name: "Gravitational Waves", query: "gravitational waves"),
                ResearchTask(name: "Black Hole Physics", query: "black hole physics relativity"),
                ResearchTask(name: "Numerical Relativity", query: "numerical relativity"),
                ResearchTask(name: "Cosmological Models", query: "cosmological models gravity"),
            ]),
        ResearchArea(
            id: "optics-atomic", name: "Optics & Atomic", symbol: "rays",
            blurb: "Light and atoms — photonics, nonlinear optics, and atomic physics.",
            arxivCategories: ["physics.optics", "physics.atom-ph"], searchAnchor: "optics photonics atomic physics", openAlexConcept: "C120665830",
            tasks: [
                ResearchTask(name: "Photonics", query: "photonics"),
                ResearchTask(name: "Nonlinear Optics", query: "nonlinear optics"),
                ResearchTask(name: "Atomic Physics", query: "atomic molecular optical physics"),
                ResearchTask(name: "Metamaterials", query: "optical metamaterials"),
            ]),
    ]

    // MARK: - Chemistry snapshot (arXiv chem-adjacent + OpenAlex; ChemRxiv is bot-blocked)

    static let chemistrySnapshot: [ResearchArea] = [
        ResearchArea(
            id: "organic", name: "Organic Chemistry", symbol: "hexagon",
            blurb: "Carbon-based synthesis — catalysis, C–H activation, and asymmetric methods.",
            arxivCategories: ["physics.chem-ph"], searchAnchor: "organic chemistry synthesis", openAlexConcept: "C178790620",
            tasks: [
                ResearchTask(name: "Total Synthesis", query: "total synthesis natural products"),
                ResearchTask(name: "Catalysis", query: "homogeneous catalysis"),
                ResearchTask(name: "C–H Activation", query: "C-H activation functionalization"),
                ResearchTask(name: "Asymmetric Synthesis", query: "asymmetric catalysis"),
                ResearchTask(name: "Organometallics", query: "organometallic chemistry"),
            ]),
        ResearchArea(
            id: "physical", name: "Physical Chemistry", symbol: "waveform.path",
            blurb: "Chemistry meets physics — spectroscopy, kinetics, and quantum chemistry.",
            arxivCategories: ["physics.chem-ph"], searchAnchor: "physical chemistry", openAlexConcept: "C147789679",
            tasks: [
                ResearchTask(name: "Spectroscopy", query: "molecular spectroscopy"),
                ResearchTask(name: "Reaction Kinetics", query: "chemical reaction kinetics"),
                ResearchTask(name: "Quantum Chemistry", query: "quantum chemistry electronic structure"),
                ResearchTask(name: "Thermodynamics", query: "chemical thermodynamics"),
            ]),
        ResearchArea(
            id: "materials-chem", name: "Materials Chemistry", symbol: "square.stack.3d.up",
            blurb: "Designed matter — nanomaterials, polymers, frameworks, and energy materials.",
            arxivCategories: ["cond-mat.mtrl-sci", "cond-mat.soft"], searchAnchor: "materials chemistry", openAlexConcept: "C192562407",
            tasks: [
                ResearchTask(name: "Nanomaterials", query: "nanomaterials synthesis"),
                ResearchTask(name: "Polymers", query: "polymer chemistry"),
                ResearchTask(name: "Metal-Organic Frameworks", query: "metal-organic frameworks"),
                ResearchTask(name: "Battery Materials", query: "battery electrode materials"),
                ResearchTask(name: "Catalytic Materials", query: "heterogeneous catalysts"),
            ]),
        ResearchArea(
            id: "computational-chem", name: "Computational Chemistry", symbol: "cpu",
            blurb: "Chemistry by simulation — DFT, molecular dynamics, and ML potentials.",
            arxivCategories: ["physics.chem-ph"], searchAnchor: "computational chemistry molecular simulation", openAlexConcept: "C147597530",
            tasks: [
                ResearchTask(name: "Density Functional Theory", query: "density functional theory"),
                ResearchTask(name: "Molecular Dynamics", query: "molecular dynamics simulation"),
                ResearchTask(name: "Machine-Learning Potentials", query: "machine learning interatomic potentials"),
                ResearchTask(name: "Drug Design", query: "computational drug design"),
            ]),
        ResearchArea(
            id: "electrochem-energy", name: "Electrochemistry & Energy", symbol: "bolt",
            blurb: "Energy conversion and storage — batteries, fuel cells, and electrocatalysis.",
            arxivCategories: ["cond-mat.mtrl-sci"], searchAnchor: "electrochemistry energy storage", openAlexConcept: "C52859227",
            tasks: [
                ResearchTask(name: "Batteries", query: "lithium-ion batteries"),
                ResearchTask(name: "Fuel Cells", query: "fuel cells"),
                ResearchTask(name: "Electrocatalysis", query: "electrocatalysis"),
                ResearchTask(name: "Solar Cells", query: "perovskite solar cells"),
            ]),
        ResearchArea(
            id: "analytical-biochem", name: "Analytical & Biochemistry", symbol: "drop",
            blurb: "Measurement and life chemistry — spectrometry, chromatography, and proteins.",
            arxivCategories: ["physics.chem-ph"], searchAnchor: "analytical chemistry biochemistry", openAlexConcept: "C55493867",
            tasks: [
                ResearchTask(name: "Mass Spectrometry", query: "mass spectrometry"),
                ResearchTask(name: "Chromatography", query: "chromatography separation"),
                ResearchTask(name: "Protein Chemistry", query: "protein structure chemistry"),
                ResearchTask(name: "Metabolomics", query: "metabolomics"),
            ]),
    ]
}
