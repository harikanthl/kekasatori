//
//  ChallengeStore+RL.swift
//  MuseDrop
//
//  Reinforcement Learning track — a learn-by-implementing course built from the
//  RL Handbook (github.com/lubludrova/rl-handbook), Sutton & Barto, and the
//  Spinning Up references. The syllabus walks the same arc as the handbook's
//  "Map of RL": bandits → dynamic programming → model-free prediction & control
//  → deep value methods (DQN line) → policy gradients (REINFORCE→PPO) →
//  continuous control & max-entropy (DDPG/TD3/SAC).
//
//  Foundational modules (R1–R3) are pure NumPy and run in the pandas image that
//  the data track already pulls (instant, no extra download). Deep-RL modules
//  (R4–R6) implement the core update rules in PyTorch against tiny, self-
//  contained tensors — no gymnasium, no training run — so every test is fast and
//  deterministic. Each test is checked against hand-computed values.
//

import Foundation

extension ChallengeStore {

    // MARK: - Modules & images

    /// RL modules in syllabus order.
    static let rlModules: [String] = [
        "R1 · Bandits & Foundations",
        "R2 · Dynamic Programming",
        "R3 · Model-Free Control",
        "R4 · Deep Q-Networks",
        "R5 · Policy Gradients",
        "R6 · Continuous & Max-Entropy"
    ]

    /// Reuses the data track's image (ships NumPy, already cached on disk).
    private static let rlNumpyImage = "amancevice/pandas:latest"
    /// Same CPU PyTorch image the DL tracks use.
    private static let rlTorchImage = "pytorch/pytorch:2.5.1-cpu"

    /// The whole RL track, in module order. Referenced from `ChallengeStore.all`.
    static let rl: [Challenge] =
        rlBandits + rlDynamicProgramming + rlModelFree + rlDeepQ + rlPolicyGradients + rlContinuous

    // MARK: - R1 · Bandits & Foundations (NumPy)

    private static let rlBandits: [Challenge] = [
        Challenge(
            id: "rl-epsilon-greedy", title: "ε-greedy action selection",
            module: "R1 · Bandits & Foundations", order: 1, difficulty: .easy,
            prompt: """
            The exploration–exploitation dilemma in its purest form. Implement \
            **ε-greedy** selection over current action-value estimates:

            - with probability **ε**, return a uniformly random arm \
            (`rng.integers(len(q))`);
            - otherwise return the **greedy** arm `np.argmax(q)`.
            """,
            starter: """
            import numpy as np

            def select(q, epsilon, rng):
                # TODO: explore with prob epsilon, else exploit (argmax)
                pass
            """,
            test: """
            import numpy as np
            rng = np.random.default_rng(0)
            q = np.array([1.0, 5.0, 2.0, 0.0])
            # epsilon = 0 is always greedy
            assert all(select(q, 0.0, rng) == 1 for _ in range(50))
            # epsilon = 1 eventually explores every arm
            seen = {int(select(q, 1.0, rng)) for _ in range(500)}
            assert seen == {0, 1, 2, 3}, seen
            # any epsilon returns a valid index
            assert 0 <= int(select(q, 0.3, rng)) < 4
            print("✅ All tests passed")
            """,
            reference: "RL Handbook · Multi-Armed Bandits", image: rlNumpyImage),
        Challenge(
            id: "rl-incremental-mean", title: "Incremental sample average",
            module: "R1 · Bandits & Foundations", order: 2, difficulty: .easy,
            prompt: """
            Track an arm's value online without storing every reward. Implement \
            the **incremental sample-average** update

            ```
            Qₙ = Qₙ₋₁ + (Rₙ − Qₙ₋₁) / n
            ```

            where `n` is the number of times the arm has been pulled (including \
            this reward).
            """,
            starter: """
            def update(old_value, count, reward):
                # TODO: incremental mean update
                pass
            """,
            test: """
            import numpy as np
            assert abs(update(0.0, 1, 1.0) - 1.0) < 1e-9
            assert abs(update(0.5, 2, 1.5) - 1.0) < 1e-9
            # equals the batch mean after streaming the rewards in
            rewards = [1.0, 0.0, 1.0, 1.0, 0.0]
            q = 0.0
            for i, r in enumerate(rewards, start=1):
                q = update(q, i, r)
            assert abs(q - np.mean(rewards)) < 1e-9
            print("✅ All tests passed")
            """,
            reference: "RL Handbook · Multi-Armed Bandits", image: rlNumpyImage),
        Challenge(
            id: "rl-ucb", title: "UCB action selection",
            module: "R1 · Bandits & Foundations", order: 3, difficulty: .medium,
            prompt: """
            Optimism in the face of uncertainty. Implement **UCB1** selection:

            - if any arm is **untried** (`counts == 0`), return the lowest such \
            index;
            - otherwise return `argmax( q + c · sqrt( ln(step) / counts ) )`.

            The bonus shrinks as an arm is pulled more, so rarely-tried arms stay \
            attractive.
            """,
            starter: """
            import numpy as np

            def select_ucb(q, counts, step, c):
                # TODO: untried arms first, else argmax of q + exploration bonus
                pass
            """,
            test: """
            import numpy as np
            # an untried arm is taken first
            q = np.array([5.0, 5.0, 5.0])
            counts = np.array([3, 2, 0])
            assert select_ucb(q, counts, 5, 2.0) == 2
            # all tried, equal values -> the least-pulled arm wins on its bonus
            q = np.array([1.0, 1.0])
            counts = np.array([10, 1])
            assert select_ucb(q, counts, 11, 2.0) == 1
            print("✅ All tests passed")
            """,
            reference: "RL Handbook · Multi-Armed Bandits", image: rlNumpyImage),
        Challenge(
            id: "rl-thompson", title: "Thompson sampling",
            module: "R1 · Bandits & Foundations", order: 4, difficulty: .medium,
            prompt: """
            A Bayesian bandit. For Bernoulli arms, keep a **Beta(α, β)** posterior \
            per arm. To act, **sample** one draw from each arm's posterior and \
            pick the arm with the largest sample:

            ```
            samples = rng.beta(alpha, beta);  return argmax(samples)
            ```

            Posteriors with more evidence concentrate, so good arms get picked \
            more while uncertain arms still get explored.
            """,
            starter: """
            import numpy as np

            def select_thompson(alpha, beta, rng):
                # TODO: sample each Beta posterior, return the best arm
                pass
            """,
            test: """
            import numpy as np
            rng = np.random.default_rng(0)
            # arm 0 has a strong posterior toward 1, arm 1 toward 0
            alpha = np.array([100.0, 1.0])
            beta = np.array([1.0, 100.0])
            picks = [int(select_thompson(alpha, beta, rng)) for _ in range(300)]
            assert sum(p == 0 for p in picks) > 285, "should almost always pick arm 0"
            print("✅ All tests passed")
            """,
            reference: "RL Handbook · Multi-Armed Bandits", image: rlNumpyImage)
    ]

    // MARK: - R2 · Dynamic Programming (NumPy)

    private static let rlDynamicProgramming: [Challenge] = [
        Challenge(
            id: "rl-bellman-backup", title: "One-step Bellman backup",
            module: "R2 · Dynamic Programming", order: 1, difficulty: .medium,
            prompt: """
            With a **known model** you can plan exactly. Given transition \
            probabilities `P[s, a, s']`, rewards `R[s, a, s']`, a value vector \
            `V`, and discount `γ`, compute the action-values of one state from a \
            single Bellman backup:

            ```
            Q(s, a) = Σ_s'  P(s'|s,a) · [ R(s,a,s') + γ · V(s') ]
            ```

            Return the length-`n_actions` vector `Q(s, ·)`.
            """,
            starter: """
            import numpy as np

            def one_step_lookahead(s, V, P, R, gamma):
                # TODO: expected reward + discounted next value, summed over s'
                pass
            """,
            test: """
            import numpy as np
            P = np.zeros((2, 2, 2)); R = np.zeros((2, 2, 2))
            # state 0: action 0 -> state 1 (reward 1); action 1 -> state 0 (reward 0)
            P[0, 0, 1] = 1.0; R[0, 0, 1] = 1.0
            P[0, 1, 0] = 1.0; R[0, 1, 0] = 0.0
            V = np.array([0.0, 10.0]); gamma = 0.9
            q = one_step_lookahead(0, V, P, R, gamma)
            assert np.allclose(q, [1.0 + 0.9 * 10.0, 0.0]), q
            print("✅ All tests passed")
            """,
            reference: "RL Handbook · Dynamic Programming", image: rlNumpyImage),
        Challenge(
            id: "rl-policy-evaluation", title: "Iterative policy evaluation",
            module: "R2 · Dynamic Programming", order: 2, difficulty: .medium,
            prompt: """
            Evaluate a fixed (possibly stochastic) policy `π[s, a]` by sweeping \
            the **Bellman expectation** update to convergence:

            ```
            V(s) ← Σ_a π(a|s) · Σ_s' P(s'|s,a) · [ R + γ V(s') ]
            ```

            Stop when the largest change over a sweep is below `theta`. Return the \
            value vector `V`.
            """,
            starter: """
            import numpy as np

            def policy_evaluation(policy, P, R, gamma, theta=1e-8):
                n_states = policy.shape[0]
                V = np.zeros(n_states)
                # TODO: sweep the Bellman expectation backup until |Δ| < theta
                return V
            """,
            test: """
            import numpy as np
            # single state, single action, self-loop with reward 1 -> V = 1/(1-γ)
            P = np.ones((1, 1, 1)); R = np.ones((1, 1, 1))
            policy = np.ones((1, 1))
            V = policy_evaluation(policy, P, R, 0.9, 1e-10)
            assert abs(V[0] - 10.0) < 1e-3, V
            print("✅ All tests passed")
            """,
            reference: "RL Handbook · Dynamic Programming", image: rlNumpyImage),
        Challenge(
            id: "rl-value-iteration", title: "Value iteration",
            module: "R2 · Dynamic Programming", order: 3, difficulty: .hard,
            prompt: """
            Collapse evaluation and improvement into one update — the **Bellman \
            optimality** backup:

            ```
            V(s) ← max_a  Σ_s' P(s'|s,a) · [ R + γ V(s') ]
            ```

            Sweep until convergence, then extract the **greedy policy** \
            `π(s) = argmax_a Q(s, a)` as an integer array. Return `(V, policy)`.
            """,
            starter: """
            import numpy as np

            def value_iteration(P, R, gamma, theta=1e-9):
                n_states, n_actions, _ = P.shape
                V = np.zeros(n_states)
                # TODO: Bellman optimality sweeps, then greedy policy extraction
                policy = np.zeros(n_states, dtype=int)
                return V, policy
            """,
            test: """
            import numpy as np
            # 3-state corridor: states 0,1,2; action 0=left, 1=right; goal=2 absorbing.
            # every step from a non-goal state costs -1.
            n_s, n_a, goal = 3, 2, 2
            P = np.zeros((n_s, n_a, n_s)); R = np.zeros((n_s, n_a, n_s))
            for s in range(n_s):
                for a in range(n_a):
                    if s == goal:
                        P[s, a, goal] = 1.0; R[s, a, goal] = 0.0
                    else:
                        ns = min(max(s + (1 if a == 1 else -1), 0), n_s - 1)
                        P[s, a, ns] = 1.0; R[s, a, ns] = -1.0
            V, policy = value_iteration(P, R, 0.9, 1e-9)
            assert abs(V[2] - 0.0) < 1e-3, V
            assert abs(V[1] - (-1.0)) < 1e-3, V
            assert abs(V[0] - (-1.9)) < 1e-3, V
            assert policy[0] == 1 and policy[1] == 1, ("should go right", policy)
            print("✅ All tests passed")
            """,
            reference: "RL Handbook · Dynamic Programming", image: rlNumpyImage)
    ]

    // MARK: - R3 · Model-Free Prediction & Control (NumPy)

    private static let rlModelFree: [Challenge] = [
        Challenge(
            id: "rl-td-update", title: "TD(0) value update",
            module: "R3 · Model-Free Control", order: 1, difficulty: .easy,
            prompt: """
            Drop the model: learn values from sampled transitions. The **TD(0)** \
            update bootstraps off the next state's current estimate:

            ```
            V(s) ← V(s) + α · [ r + γ V(s') − V(s) ]
            ```

            The bracket is the **TD error**. Return the new value for `s`.
            """,
            starter: """
            def td_update(v_s, reward, gamma, v_next, alpha):
                # TODO: one TD(0) step; return the updated V(s)
                pass
            """,
            test: """
            assert abs(td_update(0.0, 1.0, 0.9, 2.0, 0.5) - 1.4) < 1e-9
            # zero TD error leaves the value unchanged
            assert abs(td_update(5.0, 0.0, 1.0, 5.0, 0.3) - 5.0) < 1e-9
            print("✅ All tests passed")
            """,
            reference: "RL Handbook · Monte Carlo & TD", image: rlNumpyImage),
        Challenge(
            id: "rl-mc-returns", title: "Discounted returns",
            module: "R3 · Model-Free Control", order: 2, difficulty: .medium,
            prompt: """
            Monte Carlo learns from **complete returns**. Given an episode's \
            reward sequence, compute the discounted return-to-go at every step:

            ```
            G_t = r_t + γ r_{t+1} + γ² r_{t+2} + …
            ```

            Compute it in one **reverse** pass (`G_t = r_t + γ G_{t+1}`). Return an \
            array the same length as `rewards`.
            """,
            starter: """
            import numpy as np

            def returns(rewards, gamma):
                # TODO: reverse cumulative discounted return-to-go
                pass
            """,
            test: """
            import numpy as np
            assert np.allclose(returns([1.0, 1.0, 1.0], 0.5), [1.75, 1.5, 1.0])
            assert np.allclose(returns([0.0, 0.0, 5.0], 1.0), [5.0, 5.0, 5.0])
            print("✅ All tests passed")
            """,
            reference: "RL Handbook · Monte Carlo & TD", image: rlNumpyImage),
        Challenge(
            id: "rl-qlearning-update", title: "Q-learning update (off-policy)",
            module: "R3 · Model-Free Control", order: 3, difficulty: .medium,
            prompt: """
            **Q-learning** is off-policy TD control: it bootstraps off the \
            **greedy** next action regardless of what the behavior policy did.

            ```
            Q(s,a) ← Q(s,a) + α · [ r + γ · max_a' Q(s',a') − Q(s,a) ]
            ```

            Mutate and return the `Q` table.
            """,
            starter: """
            import numpy as np

            def q_learning_update(Q, s, a, reward, s_next, gamma, alpha):
                # TODO: TD update using the MAX over next actions
                return Q
            """,
            test: """
            import numpy as np
            Q = np.zeros((2, 2)); Q[1] = [1.0, 3.0]
            Q = q_learning_update(Q, 0, 0, 1.0, 1, 0.9, 0.5)
            # target = 1 + 0.9 * max(1, 3) = 3.7 ; 0 + 0.5 * 3.7 = 1.85
            assert abs(Q[0, 0] - 1.85) < 1e-9, Q[0, 0]
            print("✅ All tests passed")
            """,
            reference: "RL Handbook · Sarsa & Q-Learning", image: rlNumpyImage),
        Challenge(
            id: "rl-sarsa-update", title: "Sarsa update (on-policy)",
            module: "R3 · Model-Free Control", order: 4, difficulty: .medium,
            prompt: """
            **Sarsa** is on-policy: it bootstraps off the next action the agent \
            **actually took** — so the values include the cost of exploration.

            ```
            Q(s,a) ← Q(s,a) + α · [ r + γ · Q(s',a') − Q(s,a) ]
            ```

            Note `a'` is passed in, not maximized. Compare this to your \
            Q-learning update — same data, different target. Mutate and return `Q`.
            """,
            starter: """
            import numpy as np

            def sarsa_update(Q, s, a, reward, s_next, a_next, gamma, alpha):
                # TODO: TD update using the value of the NEXT action a_next
                return Q
            """,
            test: """
            import numpy as np
            Q = np.zeros((2, 2)); Q[1] = [1.0, 3.0]
            # next action is 0 (a non-greedy, exploratory choice)
            Q = sarsa_update(Q, 0, 0, 1.0, 1, 0, 0.9, 0.5)
            # target = 1 + 0.9 * Q[1,0]=1.0 -> 1.9 ; 0 + 0.5 * 1.9 = 0.95
            assert abs(Q[0, 0] - 0.95) < 1e-9, Q[0, 0]
            print("✅ All tests passed")
            """,
            reference: "RL Handbook · Sarsa & Q-Learning", image: rlNumpyImage),
        Challenge(
            id: "rl-qlearning-loop", title: "Capstone: tabular Q-learning",
            module: "R3 · Model-Free Control", order: 5, difficulty: .hard,
            prompt: """
            Put it together. A 5-state corridor is provided via `reset()` and \
            `step(s, a)` (action 0 = left, 1 = right; goal is state 4; every \
            non-goal step costs −1).

            Implement `train(episodes, alpha, gamma, epsilon)` running **ε-greedy \
            Q-learning**: from `reset()`, repeatedly pick an action, `step`, apply \
            the Q-learning update, until the episode is `done`. Return the learned \
            `Q` table (shape `(5, 2)`). After enough episodes the greedy action \
            from every non-goal state should be **right**.
            """,
            starter: """
            import numpy as np

            def train(episodes=2000, alpha=0.5, gamma=0.95, epsilon=0.1):
                Q = np.zeros((N_STATES, N_ACTIONS))
                rng = np.random.default_rng(0)
                # TODO: for each episode, run ε-greedy Q-learning to termination
                return Q
            """,
            test: """
            import numpy as np
            Q = train(2000, 0.5, 0.95, 0.1)
            assert Q.shape == (N_STATES, N_ACTIONS), Q.shape
            greedy = Q.argmax(axis=1)
            assert all(greedy[s] == 1 for s in range(N_STATES - 1)), ("expected right", greedy)
            print("✅ All tests passed")
            """,
            reference: "RL Handbook · Sarsa & Q-Learning", image: rlNumpyImage,
            setup: """
            import numpy as np
            N_STATES = 5
            N_ACTIONS = 2  # 0 = left, 1 = right
            GOAL = N_STATES - 1

            def reset():
                return 0

            def step(s, a):
                ns = min(max(s + (1 if a == 1 else -1), 0), N_STATES - 1)
                done = (ns == GOAL)
                reward = 0.0 if done else -1.0
                return ns, reward, done
            """)
    ]

    // MARK: - R4 · Deep Q-Networks (PyTorch)

    private static let rlDeepQ: [Challenge] = [
        Challenge(
            id: "rl-replay-buffer", title: "Experience replay buffer",
            module: "R4 · Deep Q-Networks", order: 1, difficulty: .medium,
            prompt: """
            DQN breaks correlations by training on a **replay buffer**. Implement \
            a fixed-capacity FIFO store:

            - `add(item)` appends; once full it **evicts the oldest**;
            - `__len__` returns the current count (capped at capacity);
            - `sample(n, rng)` returns `n` items drawn uniformly at random \
            (`rng.choice`).
            """,
            starter: """
            import numpy as np

            class ReplayBuffer:
                def __init__(self, capacity):
                    self.capacity = capacity
                    # TODO: storage + position bookkeeping

                def add(self, item):
                    # TODO: append, overwriting the oldest when full
                    pass

                def __len__(self):
                    # TODO
                    pass

                def sample(self, n, rng):
                    # TODO: n uniformly random stored items
                    pass
            """,
            test: """
            import numpy as np
            buf = ReplayBuffer(3)
            for i in range(5):
                buf.add(i)
            assert len(buf) == 3, len(buf)
            rng = np.random.default_rng(0)
            batch = buf.sample(2, rng)
            assert len(batch) == 2
            assert all(int(x) in {2, 3, 4} for x in batch), batch  # only the last 3 survive
            print("✅ All tests passed")
            """,
            reference: "RL Handbook · DQN", image: rlTorchImage),
        Challenge(
            id: "rl-dqn-gather", title: "Gather Q(s,a) for taken actions",
            module: "R4 · Deep Q-Networks", order: 2, difficulty: .medium,
            prompt: """
            A Q-network outputs a value for **every** action; the loss needs only \
            the value of the action that was **taken**. Given `q` of shape \
            `(batch, n_actions)` and a long tensor `actions` of shape `(batch,)`, \
            return the chosen Q-values of shape `(batch,)`.

            This is the `gather` idiom: `q.gather(1, actions.unsqueeze(1)).squeeze(1)`.
            """,
            starter: """
            import torch

            def gather_q(q, actions):
                # TODO: pick q[i, actions[i]] for each row i
                pass
            """,
            test: """
            import torch
            q = torch.tensor([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])
            actions = torch.tensor([2, 0])
            out = gather_q(q, actions)
            assert out.shape == (2,), out.shape
            assert torch.allclose(out, torch.tensor([3.0, 4.0])), out
            print("✅ All tests passed")
            """,
            reference: "RL Handbook · DQN", image: rlTorchImage),
        Challenge(
            id: "rl-dqn-target", title: "DQN TD target",
            module: "R4 · Deep Q-Networks", order: 3, difficulty: .medium,
            prompt: """
            The DQN regression target uses the **target network** and bootstraps \
            off the greedy next action, zeroing the bootstrap at terminal steps:

            ```
            y = r + γ · (1 − done) · max_a' Q_target(s', a')
            ```

            Given `rewards`, `dones` (1.0 at terminal), the target net's next-state \
            outputs `q_next` of shape `(batch, n_actions)`, and `gamma`, return `y` \
            of shape `(batch,)`.
            """,
            starter: """
            import torch

            def dqn_target(rewards, dones, q_next, gamma):
                # TODO: r + γ (1 - done) max_a' q_next
                pass
            """,
            test: """
            import torch
            q_next = torch.tensor([[1.0, 3.0], [5.0, 2.0]])
            rewards = torch.tensor([1.0, 0.0])
            dones = torch.tensor([0.0, 1.0])
            y = dqn_target(rewards, dones, q_next, 0.9)
            # row0: 1 + 0.9*3 = 3.7 ; row1: terminal -> 0
            assert torch.allclose(y, torch.tensor([3.7, 0.0]), atol=1e-5), y
            print("✅ All tests passed")
            """,
            reference: "RL Handbook · DQN", image: rlTorchImage),
        Challenge(
            id: "rl-double-dqn", title: "Double DQN target",
            module: "R4 · Deep Q-Networks", order: 4, difficulty: .hard,
            prompt: """
            The `max` in vanilla DQN **overestimates** because the same network \
            both selects and evaluates the next action. **Double DQN** decouples \
            them: the **online** net picks the action, the **target** net scores it.

            ```
            a* = argmax_a' Q_online(s', a')
            y  = r + γ · (1 − done) · Q_target(s', a*)
            ```

            Given the online and target next-state outputs, return `y` of shape \
            `(batch,)`.
            """,
            starter: """
            import torch

            def double_dqn_target(rewards, dones, q_online_next, q_target_next, gamma):
                # TODO: select with online (argmax), evaluate with target (gather)
                pass
            """,
            test: """
            import torch
            q_online_next = torch.tensor([[1.0, 5.0]])   # argmax -> action 1
            q_target_next = torch.tensor([[10.0, 2.0]])  # evaluates action 1 -> 2.0
            r = torch.tensor([0.0]); d = torch.tensor([0.0])
            y = double_dqn_target(r, d, q_online_next, q_target_next, 0.9)
            # 0 + 0.9 * 2.0 = 1.8  (vanilla DQN would wrongly use 10.0)
            assert torch.allclose(y, torch.tensor([1.8]), atol=1e-5), y
            print("✅ All tests passed")
            """,
            reference: "RL Handbook · DQN Improvements", image: rlTorchImage)
    ]

    // MARK: - R5 · Policy Gradients (PyTorch)

    private static let rlPolicyGradients: [Challenge] = [
        Challenge(
            id: "rl-reinforce-loss", title: "REINFORCE loss",
            module: "R5 · Policy Gradients", order: 1, difficulty: .medium,
            prompt: """
            Optimize the policy directly. **REINFORCE** increases the \
            log-probability of sampled actions in proportion to their return. \
            Gradient ascent on `E[log π · G]` is gradient **descent** on its \
            negative:

            ```
            loss = − mean( log π(a|s) · G )
            ```

            Given `log_probs` and `returns` (both shape `(T,)`), return the scalar \
            loss.
            """,
            starter: """
            import torch

            def reinforce_loss(log_probs, returns):
                # TODO: negative mean of log_prob * return
                pass
            """,
            test: """
            import torch
            log_probs = torch.tensor([-0.5, -1.0])
            returns = torch.tensor([2.0, 1.0])
            loss = reinforce_loss(log_probs, returns)
            # -mean(-0.5*2, -1.0*1) = -mean(-1, -1) = 1.0
            assert torch.allclose(loss, torch.tensor(1.0), atol=1e-6), loss
            print("✅ All tests passed")
            """,
            reference: "RL Handbook · Policy Gradient & REINFORCE", image: rlTorchImage),
        Challenge(
            id: "rl-advantage", title: "Advantage baseline",
            module: "R5 · Policy Gradients", order: 2, difficulty: .medium,
            prompt: """
            REINFORCE has high variance. Subtracting a state-value **baseline** \
            leaves the gradient unbiased but far less noisy:

            ```
            A_t = G_t − V(s_t)
            ```

            Given returns `G` and value estimates `V` (same shape), return the \
            advantages. Positive ⇒ the action did better than expected.
            """,
            starter: """
            import torch

            def advantage(returns, values):
                # TODO: returns minus the value baseline
                pass
            """,
            test: """
            import torch
            G = torch.tensor([3.0, 1.0, 2.0])
            V = torch.tensor([1.0, 1.0, 1.0])
            A = advantage(G, V)
            assert torch.allclose(A, torch.tensor([2.0, 0.0, 1.0])), A
            print("✅ All tests passed")
            """,
            reference: "RL Handbook · Actor-Critic", image: rlTorchImage),
        Challenge(
            id: "rl-gae", title: "Generalized Advantage Estimation",
            module: "R5 · Policy Gradients", order: 3, difficulty: .hard,
            prompt: """
            **GAE** interpolates between low-variance one-step TD and \
            high-variance Monte Carlo with a single knob `λ`. With \
            `δ_t = r_t + γ V(s_{t+1}) − V(s_t)`:

            ```
            A_t = δ_t + (γλ) δ_{t+1} + (γλ)² δ_{t+2} + …
                = δ_t + (γλ) · A_{t+1}
            ```

            `values` has length `T+1` (the last entry bootstraps the final next \
            state). Compute it in one reverse pass; return advantages of length \
            `T`.
            """,
            starter: """
            import numpy as np

            def gae(rewards, values, gamma, lam):
                # rewards: length T ; values: length T+1 (last = bootstrap V(s_T))
                # TODO: reverse accumulation of discounted TD errors
                pass
            """,
            test: """
            import numpy as np
            rewards = [1.0, 1.0]
            values = [0.5, 0.5, 0.0]
            A = gae(rewards, values, gamma=0.9, lam=0.8)
            # delta0 = 1 + 0.9*0.5 - 0.5 = 0.95 ; delta1 = 1 + 0 - 0.5 = 0.5
            # A1 = 0.5 ; A0 = 0.95 + (0.9*0.8)*0.5 = 1.31
            assert np.allclose(A, [1.31, 0.5], atol=1e-6), A
            print("✅ All tests passed")
            """,
            reference: "RL Handbook · TRPO / PPO", image: rlTorchImage),
        Challenge(
            id: "rl-ppo-clip", title: "PPO clipped surrogate",
            module: "R5 · Policy Gradients", order: 4, difficulty: .hard,
            prompt: """
            **PPO** keeps updates from moving the policy too far by clipping the \
            probability ratio. With `r = exp(logπ_new − logπ_old)`:

            ```
            loss = − mean( min( r · A ,  clip(r, 1−ε, 1+ε) · A ) )
            ```

            Given `old_log_probs`, `new_log_probs`, advantages `A`, and `clip`, \
            return the scalar loss. (Advantages are positive here.)
            """,
            starter: """
            import torch

            def ppo_clip_loss(old_log_probs, new_log_probs, advantages, clip):
                # TODO: ratio, clipped surrogate, negative mean
                pass
            """,
            test: """
            import torch
            old = torch.tensor([0.0, 0.0])
            new = torch.tensor([0.2, -0.2])  # ratios ~1.2214 and ~0.8187
            A = torch.tensor([1.0, 1.0])
            loss = ppo_clip_loss(old, new, A, clip=0.2)
            # r0=1.2214 clipped to 1.2 -> 1.2 ; r1=0.8187 within band -> 0.8187
            # -mean(1.2, 0.8187) = -1.009366
            assert torch.allclose(loss, torch.tensor(-1.009366), atol=1e-4), loss
            print("✅ All tests passed")
            """,
            reference: "RL Handbook · PPO", image: rlTorchImage)
    ]

    // MARK: - R6 · Continuous Control & Max-Entropy (PyTorch)

    private static let rlContinuous: [Challenge] = [
        Challenge(
            id: "rl-soft-update", title: "Polyak (soft) target update",
            module: "R6 · Continuous & Max-Entropy", order: 1, difficulty: .easy,
            prompt: """
            Off-policy actor-critics keep slow-moving **target networks** updated \
            by Polyak averaging:

            ```
            θ_target ← τ · θ_online + (1 − τ) · θ_target
            ```

            Small `τ` (e.g. 0.005) means the target trails the online net, which \
            stabilizes bootstrapped TD targets. Return the new target tensor.
            """,
            starter: """
            import torch

            def soft_update(target, online, tau):
                # TODO: τ * online + (1 - τ) * target
                pass
            """,
            test: """
            import torch
            target = torch.tensor([0.0, 10.0])
            online = torch.tensor([1.0, 0.0])
            out = soft_update(target, online, tau=0.1)
            assert torch.allclose(out, torch.tensor([0.1, 9.0]), atol=1e-6), out
            print("✅ All tests passed")
            """,
            reference: "RL Handbook · DDPG", image: rlTorchImage),
        Challenge(
            id: "rl-target-smoothing", title: "TD3 target policy smoothing",
            module: "R6 · Continuous & Max-Entropy", order: 2, difficulty: .medium,
            prompt: """
            TD3 regularizes the critic target by adding **clipped noise** to the \
            target action, then clamping to the valid action range:

            ```
            a' = clamp( μ(s') + clamp(noise, −c, c),  low,  high )
            ```

            Given the target-actor output `mu`, a `noise` tensor, the noise clip \
            `c`, and action bounds `low`/`high`, return the smoothed action.
            """,
            starter: """
            import torch

            def smooth_action(mu, noise, c, low, high):
                # TODO: clip the noise to [-c, c], add, then clamp to [low, high]
                pass
            """,
            test: """
            import torch
            mu = torch.tensor([0.9, -0.9, 0.0])
            noise = torch.tensor([0.5, -0.5, 0.05])
            out = smooth_action(mu, noise, c=0.2, low=-1.0, high=1.0)
            # noise clipped -> [0.2, -0.2, 0.05]; +mu -> [1.1, -1.1, 0.05]; clamp -> [1, -1, 0.05]
            assert torch.allclose(out, torch.tensor([1.0, -1.0, 0.05]), atol=1e-6), out
            print("✅ All tests passed")
            """,
            reference: "RL Handbook · TD3 & SAC", image: rlTorchImage),
        Challenge(
            id: "rl-td3-target", title: "TD3 twin-critic target",
            module: "R6 · Continuous & Max-Entropy", order: 3, difficulty: .hard,
            prompt: """
            TD3 fights Q-overestimation with **twin critics** and takes the \
            **minimum** of the two target critics:

            ```
            y = r + γ · (1 − done) · min( Q₁_target(s',a') , Q₂_target(s',a') )
            ```

            Given `rewards`, `dones`, the two target-critic tensors `q1`/`q2` \
            (shape `(batch,)`), and `gamma`, return `y`.
            """,
            starter: """
            import torch

            def td3_target(rewards, dones, q1, q2, gamma):
                # TODO: bootstrap off the elementwise min of the twin critics
                pass
            """,
            test: """
            import torch
            q1 = torch.tensor([5.0, 1.0]); q2 = torch.tensor([3.0, 2.0])
            r = torch.tensor([0.0, 0.0]); d = torch.tensor([0.0, 1.0])
            y = td3_target(r, d, q1, q2, gamma=0.9)
            # min -> [3, 1]; row0: 0+0.9*3=2.7 ; row1: terminal -> 0
            assert torch.allclose(y, torch.tensor([2.7, 0.0]), atol=1e-5), y
            print("✅ All tests passed")
            """,
            reference: "RL Handbook · TD3 & SAC", image: rlTorchImage),
        Challenge(
            id: "rl-sac-target", title: "SAC max-entropy target",
            module: "R6 · Continuous & Max-Entropy", order: 4, difficulty: .hard,
            prompt: """
            **SAC** maximizes reward *plus* policy entropy, so the critic target \
            subtracts the action's log-probability (scaled by temperature `α`) \
            from the twin-critic minimum:

            ```
            y = r + γ · (1 − done) · [ min(Q₁,Q₂) − α · log π(a'|s') ]
            ```

            Higher entropy (more negative `log π`) raises the target, rewarding \
            the policy for staying stochastic. Return `y`.
            """,
            starter: """
            import torch

            def sac_target(rewards, dones, q1, q2, log_pi, alpha, gamma):
                # TODO: min twin critics, subtract α·log_pi, then bootstrap
                pass
            """,
            test: """
            import torch
            q1 = torch.tensor([2.0]); q2 = torch.tensor([3.0])
            log_pi = torch.tensor([-1.0])
            r = torch.tensor([0.0]); d = torch.tensor([0.0])
            y = sac_target(r, d, q1, q2, log_pi, alpha=0.2, gamma=0.9)
            # min=2 ; 2 - 0.2*(-1) = 2.2 ; 0 + 0.9*2.2 = 1.98
            assert torch.allclose(y, torch.tensor([1.98]), atol=1e-5), y
            print("✅ All tests passed")
            """,
            reference: "RL Handbook · TD3 & SAC", image: rlTorchImage)
    ]

    // MARK: - Theory (concept for each RL lesson)

    static let rlTheory: [String: String] = [
        "rl-epsilon-greedy": """
        ## Exploration vs. exploitation
        A bandit has one state and `k` arms with unknown payoffs. **Exploit** and
        you keep pulling the arm that looks best so far; **explore** and you risk a
        worse arm to learn its true value. ε-greedy is the simplest balance: act
        greedily, but with probability **ε** pick at random.

        A fixed ε keeps exploring forever (good for non-stationary problems); a
        **decaying** ε (e.g. `ε_t = c/(t+1)`) explores early then commits. This same
        rule is the behavior policy inside Sarsa and Q-learning.
        """,
        "rl-incremental-mean": """
        ## Learning a mean online
        You don't need to store every reward to track an arm's average. The
        incremental rule `Qₙ = Qₙ₋₁ + (Rₙ − Qₙ₋₁)/n` updates in O(1) memory and is
        mathematically identical to the batch mean.

        Replace the `1/n` step size with a **constant α** and you get an
        *exponential* moving average that forgets old rewards — exactly what you
        want when the environment drifts. That `value ← value + α·(target − value)`
        shape is the skeleton of every TD update that follows.
        """,
        "rl-ucb": """
        ## Optimism in the face of uncertainty
        Instead of exploring blindly, **UCB** explores *deliberately*: it adds a
        confidence bonus `c·sqrt(ln t / Nₐ)` to each arm's estimate. Arms pulled
        rarely have a large bonus, so they get tried; as `Nₐ` grows the bonus
        shrinks and the estimate dominates.

        This directs exploration toward genuinely uncertain arms rather than
        wasting random pulls, and gives UCB its logarithmic-regret guarantee on
        stationary bandits.
        """,
        "rl-thompson": """
        ## Bayesian bandits
        Thompson sampling keeps a **posterior** over each arm's payoff and acts by
        *sampling* from it — pick the arm whose sampled value is highest. For
        Bernoulli rewards the conjugate posterior is **Beta(α, β)**: start at
        Beta(1,1) (uniform), add 1 to α on a success and to β on a failure.

        Uncertain arms have wide posteriors, so their samples sometimes come out on
        top — that *is* the exploration, with no ε to tune. It's simple, and often
        the strongest baseline in practice.
        """,
        "rl-bellman-backup": """
        ## The Bellman backup
        Every value method is built on one identity: the value of a state is the
        expected immediate reward plus the discounted value of where you land.
        `Q(s,a) = Σ_s' P(s'|s,a)·[R + γV(s')]` is a single **backup** — it pushes
        information one step back through the model.

        With a known `P` and `R` this is exact planning. Without a model, the same
        target is *sampled* instead of summed — and that's the only difference
        between dynamic programming and TD learning.
        """,
        "rl-policy-evaluation": """
        ## Evaluating a fixed policy
        Policy evaluation answers "if the agent keeps following π, what is each
        state worth?" Sweep the Bellman *expectation* backup
        `V(s) ← Σ_a π(a|s) Σ_s' P[R + γV(s')]` repeatedly and `V` converges to the
        true `V_π` (the backup is a γ-contraction, so a unique fixed point exists).

        This is the "evaluation" half of generalized policy iteration; pairing it
        with greedy improvement gives an algorithm that provably reaches the
        optimal policy.
        """,
        "rl-value-iteration": """
        ## Value iteration
        Why fully evaluate a policy before improving it? Value iteration folds both
        steps into one **Bellman optimality** backup `V(s) ← max_a Σ_s' P[R + γV(s')]`,
        sweeping until `V` stops changing. The greedy policy w.r.t. the converged
        `V*` is optimal.

        It's the model-based ideal the rest of the course approximates: Q-learning
        is value iteration with sampled, one-state-at-a-time backups and a function
        approximator instead of a table.
        """,
        "rl-td-update": """
        ## Bootstrapping from one step
        Monte Carlo waits for the full episode return; **TD(0)** updates after a
        single step using its own estimate of the next state:
        `V(s) ← V(s) + α·[r + γV(s') − V(s)]`. The bracket is the **TD error** — the
        surprise between what you expected and what one step revealed.

        Bootstrapping lets TD learn online, from incomplete episodes, with lower
        variance than MC (at the price of some bias). It is the workhorse update of
        model-free RL.
        """,
        "rl-mc-returns": """
        ## Returns-to-go
        The **return** `G_t = Σ γ^k r_{t+k}` is what every value function predicts.
        Computing it for a whole episode is cheapest **backwards**:
        `G_t = r_t + γ·G_{t+1}`, one pass from the last step to the first.

        Discounting (γ < 1) makes the sum finite and expresses a preference for
        sooner rewards. These returns are the regression targets for Monte Carlo
        value learning and the weights in the REINFORCE gradient.
        """,
        "rl-qlearning-update": """
        ## Off-policy TD control
        Q-learning learns the **optimal** action-values while behaving however it
        likes (e.g. ε-greedy). Its target bootstraps off the *greedy* next action:
        `r + γ·max_a' Q(s',a')`. Because the target ignores the behavior policy,
        Q-learning is **off-policy** — it can learn the best policy from exploratory
        or even logged data.

        That `max` is also the source of overestimation bias, which Double DQN
        later fixes.
        """,
        "rl-sarsa-update": """
        ## On-policy TD control
        Sarsa uses the quintuple `(S, A, R, S', A')`: its target is `r + γ·Q(s',a')`
        for the action **actually taken** next, so it evaluates and improves the
        *same* ε-greedy policy. That makes it **on-policy**.

        The practical difference shows up near danger: on the cliff-walking task,
        Q-learning learns the optimal path right along the edge, while Sarsa — which
        feels the cost of its own exploratory steps — learns a safer route.
        """,
        "rl-qlearning-loop": """
        ## Putting control together
        Tabular Q-learning is the full GPI loop from samples: act ε-greedily, take a
        step, apply the off-policy TD update, repeat. With enough exploration and a
        decaying-or-small α, `Q` converges to `Q*` and the greedy policy solves the
        task.

        On a tiny corridor it learns "always go right" in a few hundred episodes.
        The exact same loop, with a neural net replacing the table and a replay
        buffer feeding it, becomes DQN.
        """,
        "rl-replay-buffer": """
        ## Experience replay
        Consecutive transitions are highly correlated, and online updates throw each
        sample away after one use — both poison neural-net training. A **replay
        buffer** stores recent transitions and trains on *random minibatches* drawn
        from it, which decorrelates the data and reuses each transition many times.

        It's a fixed-capacity ring: new transitions overwrite the oldest. Together
        with a target network, it's what made off-policy bootstrapping stable enough
        to crack Atari.
        """,
        "rl-dqn-gather": """
        ## Selecting the taken action's value
        A Q-network emits one value per action, but the Bellman loss compares only
        the value of the action that was actually played. `gather` indexes each row
        of the `(batch, n_actions)` output by that row's action:
        `q.gather(1, a.unsqueeze(1)).squeeze(1)`.

        Getting this indexing right — and keeping gradients flowing only through the
        chosen action — is the small but essential plumbing of a DQN update.
        """,
        "rl-dqn-target": """
        ## The DQN regression target
        DQN turns control into supervised regression: fit `Q(s,a)` to the target
        `y = r + γ·(1−done)·max_a' Q_target(s',a')`. Two tricks make it stable — a
        **target network** (a slowly-updated copy that supplies `Q_target`, so the
        target doesn't chase the prediction) and the `(1−done)` factor that zeros
        the bootstrap at episode end.

        Minimize `(Q(s,a) − y)²` (or Huber) over replay minibatches and you have the
        algorithm that learned Atari from pixels.
        """,
        "rl-double-dqn": """
        ## Taming overestimation
        The `max` in the DQN target both **selects** and **evaluates** the next
        action with the same noisy network, which systematically *overestimates*
        Q-values. **Double DQN** splits the two: the **online** net picks
        `a* = argmax Q_online(s',·)`, the **target** net scores it,
        `y = r + γ·Q_target(s', a*)`.

        It's a one-line change that removes most of the bias and reliably improves
        scores — one of the headline ingredients folded into Rainbow.
        """,
        "rl-reinforce-loss": """
        ## The policy gradient
        Instead of learning values and acting greedily, policy-gradient methods
        optimize a parameterized policy `π_θ` directly. The REINFORCE estimator
        nudges up the log-probability of each sampled action in proportion to its
        return: `∇J = E[∇log π(a|s)·G]`. As a loss to *minimize* that's
        `−mean(log π · G)`.

        It works for stochastic and continuous-action policies out of the box, but
        the raw return makes it high-variance — which is what baselines and critics
        are for.
        """,
        "rl-advantage": """
        ## Baselines cut the variance
        Subtracting any state-dependent baseline `b(s)` from the return leaves the
        policy gradient **unbiased** but can slash its variance. The best practical
        choice is the value function, giving the **advantage** `A_t = G_t − V(s_t)`:
        how much better the action did than the state's average.

        Now the gradient pushes up actions with positive advantage and down those
        with negative — a much cleaner signal than the absolute return. This is the
        actor-critic idea in one line.
        """,
        "rl-gae": """
        ## Trading bias for variance
        One-step advantages (`δ_t`) are low-variance but biased; full Monte Carlo
        advantages are unbiased but noisy. **GAE** blends the whole spectrum with a
        single `λ`: an exponentially-weighted sum of TD errors,
        `A_t = Σ (γλ)^l δ_{t+l}`, computed in one backward pass.

        `λ=0` recovers the one-step advantage, `λ=1` the Monte Carlo one;
        `λ≈0.95` is the standard sweet spot that makes PPO and TRPO train smoothly.
        """,
        "rl-ppo-clip": """
        ## Trust regions, cheaply
        Reusing on-policy data for several gradient steps can blow the policy too
        far from the one that collected it. TRPO enforces a hard KL trust region;
        **PPO** approximates it with a clipped objective. With ratio
        `r = π_new/π_old`, it optimizes `min(r·A, clip(r, 1−ε, 1+ε)·A)`.

        Once `r` leaves `[1−ε, 1+ε]` in the improving direction, clipping flattens
        the objective, so there's no incentive to push further. Simple, first-order,
        and the default on-policy algorithm today.
        """,
        "rl-soft-update": """
        ## Slow-moving targets
        Bootstrapped TD targets are unstable when the target is the network itself.
        Continuous-control actor-critics keep a separate **target network** updated
        by Polyak averaging: `θ⁻ ← τθ + (1−τ)θ⁻` after every step, with a tiny
        `τ≈0.005`.

        The target therefore drifts slowly behind the online net, giving the critic
        a near-stationary objective to regress toward. DDPG, TD3, and SAC all rely
        on it.
        """,
        "rl-target-smoothing": """
        ## Regularizing the critic target
        A deterministic actor can exploit sharp, spurious peaks in the critic.
        **Target policy smoothing** (TD3) blurs them: add clipped noise to the
        target action, `a' = clip(μ(s') + clip(ε, −c, c), low, high)`, so the critic
        target is averaged over a small neighborhood of actions.

        It's a cheap, effective regularizer that stops the policy from overfitting
        to critic errors — one of TD3's three fixes over DDPG.
        """,
        "rl-td3-target": """
        ## Twin critics
        DDPG inherits DQN's overestimation: the actor learns to exploit wherever the
        single critic is too optimistic. **TD3** trains *two* critics and forms the
        target from their **minimum**, `min(Q₁,Q₂)`, which biases the estimate
        downward and cancels most of the inflation.

        Combined with delayed actor updates and target smoothing, this makes
        deterministic continuous control reliable where plain DDPG was brittle.
        """,
        "rl-sac-target": """
        ## Maximum-entropy RL
        SAC optimizes reward **plus** policy entropy, so the agent succeeds *while
        staying as random as it can*. That changes the critic target to
        `min(Q₁,Q₂) − α·log π(a'|s')`: a high-entropy (more negative log-prob) action
        gets a bonus.

        The temperature `α` trades off return against exploration (and is usually
        auto-tuned to a target entropy). The result is a stochastic off-policy actor
        that's sample-efficient and robust — a default for continuous control.
        """
    ]
}
