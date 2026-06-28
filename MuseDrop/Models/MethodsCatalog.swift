//
//  MethodsCatalog.swift
//  MuseDrop
//
//  A controlled vocabulary of research methods — the same idea as Papers with
//  Code's "Methods" taxonomy: canonical techniques (Transformer, RoPE, GRPO,
//  Flash Attention, …) grouped by area, each with the year it was introduced.
//
//  The paper detail page tags a paper by *detecting* these methods in its title
//  and abstract (deterministic, offline — no LLM), so Methods are always real,
//  recognized techniques rather than free-form text. Many of these map directly
//  to the Learn modules (RoPE, GQA, RMSNorm, KV cache, Multi-head attention).
//

import Foundation

enum MethodArea: String, Sendable, CaseIterable {
    case general = "General"
    case language = "Language"
    case vision = "Vision"
    case audio = "Audio"

    /// Display order, most general first.
    var order: Int {
        switch self {
        case .general: return 0
        case .language: return 1
        case .vision: return 2
        case .audio: return 3
        }
    }
}

struct ResearchMethod: Identifiable, Hashable, Sendable {
    let name: String
    let area: MethodArea
    let year: Int?
    /// Acronyms / spellings used to detect the method in free text.
    var aliases: [String] = []

    var id: String { name }

    /// "Transformer · 2017" — the chip label.
    var label: String { year.map { "\(name) · \($0)" } ?? name }
}

enum MethodsCatalog {

    /// The canonical method list (a curated subset of the Papers-with-Code
    /// Methods taxonomy, biased toward techniques that recur in AI papers).
    static let all: [ResearchMethod] = [
        // MARK: General
        ResearchMethod(name: "Large Language Model", area: .general, year: nil, aliases: ["LLM", "LLMs"]),
        ResearchMethod(name: "Transformer", area: .general, year: 2017),
        ResearchMethod(name: "Fine-tuning", area: .general, year: nil, aliases: ["finetuning", "fine tuning"]),
        ResearchMethod(name: "Multi-Head Attention", area: .general, year: 2017, aliases: ["MHA", "multi head attention"]),
        ResearchMethod(name: "Softmax", area: .general, year: nil),
        ResearchMethod(name: "Layer Normalization", area: .general, year: 2016, aliases: ["LayerNorm", "layer norm"]),
        ResearchMethod(name: "Adam", area: .general, year: 2014),
        ResearchMethod(name: "AdamW", area: .general, year: 2017),
        ResearchMethod(name: "Dropout", area: .general, year: 2014),
        ResearchMethod(name: "Embedding", area: .general, year: nil, aliases: ["embeddings"]),
        ResearchMethod(name: "Pre-training", area: .general, year: nil, aliases: ["pretraining", "pre training"]),
        ResearchMethod(name: "Chain-of-Thought", area: .general, year: 2022, aliases: ["CoT", "chain of thought"]),
        ResearchMethod(name: "Stable Diffusion", area: .general, year: 2023),
        ResearchMethod(name: "Direct Preference Optimization", area: .general, year: 2023, aliases: ["DPO"]),
        ResearchMethod(name: "Label Smoothing", area: .general, year: 2015),
        ResearchMethod(name: "RLHF", area: .general, year: 2022),
        ResearchMethod(name: "GRPO", area: .general, year: nil),
        ResearchMethod(name: "Convolution", area: .general, year: nil, aliases: ["convolutional"]),
        ResearchMethod(name: "Diffusion Transformer", area: .general, year: 2022, aliases: ["DiT"]),
        ResearchMethod(name: "LoRA", area: .general, year: 2021),
        ResearchMethod(name: "QLoRA", area: .general, year: 2023),
        ResearchMethod(name: "PPO", area: .general, year: nil),
        ResearchMethod(name: "PEFT", area: .general, year: 2021),
        ResearchMethod(name: "Classifier-free Guidance", area: .general, year: 2022, aliases: ["classifier free guidance"]),
        ResearchMethod(name: "Key-Value Cache", area: .general, year: 2017, aliases: ["KV cache", "kv-cache", "key value cache"]),
        ResearchMethod(name: "Scaling Laws", area: .general, year: 2020, aliases: ["scaling law"]),
        ResearchMethod(name: "ReAct", area: .general, year: 2022),
        ResearchMethod(name: "Few-shot Prompting", area: .general, year: 2020, aliases: ["few-shot", "few shot"]),
        ResearchMethod(name: "Flow Matching", area: .general, year: 2022),
        ResearchMethod(name: "Knowledge Distillation", area: .general, year: 2015, aliases: ["distillation"]),
        ResearchMethod(name: "Skip Connection", area: .general, year: 2015, aliases: ["residual connection"]),
        ResearchMethod(name: "Flash Attention", area: .general, year: 2022, aliases: ["FlashAttention"]),
        ResearchMethod(name: "Mixture-of-Experts", area: .general, year: 1991, aliases: ["MoE", "mixture of experts"]),
        ResearchMethod(name: "Mamba", area: .general, year: 2023),
        ResearchMethod(name: "GAN", area: .general, year: 2016, aliases: ["generative adversarial network"]),
        ResearchMethod(name: "Quantization", area: .general, year: nil, aliases: ["quantized", "quantize"]),
        ResearchMethod(name: "DETR", area: .general, year: 2020),
        ResearchMethod(name: "Batch Normalization", area: .general, year: 2015, aliases: ["BatchNorm", "batch norm"]),
        ResearchMethod(name: "Contrastive Learning", area: .general, year: nil),
        ResearchMethod(name: "VAE", area: .general, year: 2013, aliases: ["variational autoencoder"]),
        ResearchMethod(name: "Self-supervised Learning", area: .general, year: nil, aliases: ["self supervised", "SSL"]),
        ResearchMethod(name: "Reward Model", area: .general, year: nil, aliases: ["reward modeling", "reward modelling"]),
        ResearchMethod(name: "State Space Model", area: .general, year: 2021, aliases: ["state space models", "SSM"]),
        ResearchMethod(name: "Graph Neural Network", area: .general, year: nil, aliases: ["GNN"]),
        ResearchMethod(name: "RMSNorm", area: .general, year: 2019, aliases: ["RMS normalization", "root mean square"]),
        ResearchMethod(name: "LSTM", area: .general, year: 1997),
        ResearchMethod(name: "Function Calling", area: .general, year: 2023, aliases: ["tool calling"]),
        ResearchMethod(name: "Multi-Latent Attention", area: .general, year: 2024, aliases: ["MLA", "multi-head latent attention"]),
        ResearchMethod(name: "RoPE", area: .general, year: 2021, aliases: ["rotary position", "rotary embedding", "rotary positional"]),
        ResearchMethod(name: "LLM-as-a-judge", area: .general, year: nil, aliases: ["llm as a judge"]),
        ResearchMethod(name: "Multi-Query Attention", area: .general, year: 2019, aliases: ["MQA"]),
        ResearchMethod(name: "Sparse Attention", area: .general, year: 2019),
        ResearchMethod(name: "Linear Attention", area: .general, year: nil),
        ResearchMethod(name: "Gradient Clipping", area: .general, year: 2012),
        ResearchMethod(name: "word2vec", area: .general, year: 2013),
        ResearchMethod(name: "MCP", area: .general, year: 2024, aliases: ["model context protocol"]),

        // MARK: Language
        ResearchMethod(name: "Diffusion", area: .language, year: 2015, aliases: ["diffusion model"]),
        ResearchMethod(name: "BPE", area: .language, year: 2015, aliases: ["byte-pair encoding", "byte pair encoding"]),
        ResearchMethod(name: "LLaMA", area: .language, year: 2023, aliases: ["llama"]),
        ResearchMethod(name: "BERT", area: .language, year: 2018),
        ResearchMethod(name: "RAG", area: .language, year: 2020, aliases: ["retrieval-augmented generation", "retrieval augmented"]),
        ResearchMethod(name: "T5", area: .language, year: 2019),
        ResearchMethod(name: "GPT-4", area: .language, year: 2023, aliases: ["GPT-4o", "GPT4"]),
        ResearchMethod(name: "GPT-3", area: .language, year: 2020, aliases: ["GPT3"]),
        ResearchMethod(name: "GPT-2", area: .language, year: 2019, aliases: ["GPT2"]),
        ResearchMethod(name: "Seq2Seq", area: .language, year: 2014, aliases: ["sequence to sequence"]),
        ResearchMethod(name: "Grouped-Query Attention", area: .language, year: 2023, aliases: ["GQA", "grouped query attention"]),
        ResearchMethod(name: "Speculative Decoding", area: .language, year: 2022),
        ResearchMethod(name: "Attention", area: .language, year: 2014, aliases: ["attention mechanism"]),
        ResearchMethod(name: "BLEU", area: .language, year: 2002),
        ResearchMethod(name: "ROUGE", area: .language, year: 2004),
        ResearchMethod(name: "Sliding Window Attention", area: .language, year: 2020),
        ResearchMethod(name: "GloVe", area: .language, year: 2014),
        ResearchMethod(name: "ELMo", area: .language, year: 2018),

        // MARK: Vision
        ResearchMethod(name: "CLIP", area: .vision, year: 2021),
        ResearchMethod(name: "LLaVA", area: .vision, year: 2023, aliases: ["llava"]),
        ResearchMethod(name: "Vision Transformer", area: .vision, year: 2020, aliases: ["ViT"]),
        ResearchMethod(name: "Segment Anything", area: .vision, year: 2023, aliases: ["SAM"]),
        ResearchMethod(name: "DINO", area: .vision, year: 2021),
        ResearchMethod(name: "ResNet", area: .vision, year: 2015, aliases: ["residual network"]),
        ResearchMethod(name: "VQ-VAE", area: .vision, year: 2017),
        ResearchMethod(name: "U-Net", area: .vision, year: 2015, aliases: ["UNet"]),
        ResearchMethod(name: "ConvNeXt", area: .vision, year: 2022),
        ResearchMethod(name: "Mask R-CNN", area: .vision, year: 2017),
        ResearchMethod(name: "Faster R-CNN", area: .vision, year: 2015),
        ResearchMethod(name: "NeRF", area: .vision, year: 2020, aliases: ["neural radiance field"]),
        ResearchMethod(name: "Gaussian Splatting", area: .vision, year: 2023, aliases: ["3D Gaussian Splatting", "3DGS"]),
        ResearchMethod(name: "YOLO", area: .vision, year: 2015),
        ResearchMethod(name: "Max Pooling", area: .vision, year: nil),

        // MARK: Audio
        ResearchMethod(name: "Whisper", area: .audio, year: 2022),
        ResearchMethod(name: "WaveNet", area: .audio, year: 2016),
        ResearchMethod(name: "Conformer", area: .audio, year: 2020),
        ResearchMethod(name: "SoundStream", area: .audio, year: 2021),
        ResearchMethod(name: "Spectrogram", area: .audio, year: nil, aliases: ["mel-spectrogram", "mel spectrogram"]),
        ResearchMethod(name: "RNN-Transducer", area: .audio, year: 2012, aliases: ["RNN-T"]),
        ResearchMethod(name: "Wav2Vec", area: .audio, year: 2019, aliases: ["wav2vec"]),
        ResearchMethod(name: "Neural Audio Codec", area: .audio, year: nil),
    ]

    /// Detect catalog methods mentioned in `text` (a paper's title + abstract).
    /// Word-boundary matched; short/mixed-case acronyms (LLM, GQA, RoPE) are
    /// matched case-sensitively to avoid false hits on common words. Returns the
    /// most specific matches first, capped, then grouped by area for display.
    static func detect(in text: String, limit: Int = 8) -> [ResearchMethod] {
        let matched = all.filter { method in
            ([method.name] + method.aliases).contains { CatalogText.mentions(text, $0) }
        }
        // Keep the most specific (longest-named) when over the cap…
        let top = matched.sorted { $0.name.count > $1.name.count }.prefix(limit)
        // …then present grouped by area, alphabetical within area.
        return top.sorted {
            $0.area.order != $1.area.order ? $0.area.order < $1.area.order : $0.name < $1.name
        }
    }
}
