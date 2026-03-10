/**
 * Adaptive minimisation for selecting vignette indices.
 * @param {string} globalData - JSON dataset with overall_counts & position_counts
 * @param {number} numVignettes - Number of vignette IDs to select
 * @returns {string[]} Array of selected 6-bit vignette ID strings
 */
export default async function trialMinimisation(globalData, numVignettes) {
  const LAMBDA = 0.075;
  const GAMMA = 0.2;

  // Load global counts
  const overallCounts = globalData.overall_counts;
  const positionCounts = globalData.position_counts;

  const vignetteIds = Object.keys(overallCounts);
  const nV = vignetteIds.length;

  // Total assignments so far
  const totalAssigned = Object.values(overallCounts).reduce((sum, count) => sum + count, 0);
  const targetOverall = (totalAssigned + numVignettes) / nV;
  const targetPosition = targetOverall / numVignettes;

  // initialize marginal cost lookup tables
  const deltaOverall  = {};
  const deltaPosition = {};
  function computeDeltaOverall(i) {
    const C = overallCounts[i];
    const oldO = (C - targetOverall) ** 2;
    const newO = (C + 1 - targetOverall) ** 2;
    deltaOverall[i] = oldO - newO;
  }
  function computeDeltaPosition(i) {
    deltaPosition[i] = [];
    for (let p = 0; p < numVignettes; p++) {
      const P    = positionCounts[i][p];
      const oldP = (P - targetPosition) ** 2;
      const newP = (P + 1 - targetPosition) ** 2;
      deltaPosition[i][p] = oldP - newP;
    }
  }
  // build both tables
  for (const i of vignetteIds) {
    computeDeltaOverall(i);
    computeDeltaPosition(i);
  }

  // Hamming distance between two 6-bit strings
  function hammingDistance(a, b) {
    let dist = 0;
    for (let i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) dist++;
    }
    return dist;
  }
  // Ensure each pair in the sequence differs by >= 2 bits
  function isValidCandidate(order) {
    for (let i = 0; i < order.length; i++) {
      for (let j = i + 1; j < order.length; j++) {
        if (hammingDistance(order[i], order[j]) < 2) return false;
      }
    }
    return true;
  }
  // Generate one valid candidate sequence
  function generateCandidate() {
    let seq;
    do {
      const pool = [...vignetteIds];
      seq = [];
      for (let i = 0; i < numVignettes; i++) {
        const idx = Math.floor(Math.random() * pool.length);
        seq.push(pool.splice(idx, 1)[0]);
      }
    } while (!isValidCandidate(seq));
    return seq;
  }

  // Compute the cost of a candidate sequence
  function computeMarginalCost(seq) {
    let sum = 0;
      for (let p = 0; p < numVignettes; p++) {
        const i = seq[p];
        sum += deltaOverall[i] + LAMBDA * deltaPosition[i][p];
      }
    return sum;
  }

  function stableSoftmax(deltas) {
    const exps = deltas.map(d => Math.exp(GAMMA * d));
    const sum_exps = exps.reduce((a, b) => a + b, 0) || 1;
    const probs = exps.map(e => e / sum_exps);
    return probs;
  }

  // Build candidate pool, compute costs, and sample via a computationally safe version of softmax
  const POOL_SIZE = 100;
  const candidates = Array.from({ length: POOL_SIZE }, () => generateCandidate());
  const deltas = candidates.map(computeMarginalCost);
  const probabilities = stableSoftmax(deltas);

  const pick = Math.random();

  let cumulative = 0;
  let chosenIndex = probabilities.length - 1;
  for (let i = 0; i < probabilities.length; i++) {
    cumulative += probabilities[i];
    if (pick < cumulative) {
      chosenIndex = i;
      break;
    }
  }

  return candidates[chosenIndex];
}
