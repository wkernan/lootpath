// Small dense linear algebra for the fit: least squares through the
// eigen-decomposition of the normal matrix (cyclic Jacobi), so a rank-deficient
// design - four secondaries that budget rows cannot tell apart - gets the
// minimum-norm solution and says its rank, instead of dividing by zero.
'use strict';

function jacobiEigen(A) {
    const n = A.length;
    const a = A.map((r) => r.slice());
    const v = a.map((_, i) => a.map((__, j) => (i === j ? 1 : 0)));
    for (let sweep = 0; sweep < 100; sweep++) {
        let off = 0;
        for (let p = 0; p < n; p++) for (let q = p + 1; q < n; q++) off += a[p][q] * a[p][q];
        if (off < 1e-30) break;
        for (let p = 0; p < n; p++) {
            for (let q = p + 1; q < n; q++) {
                if (Math.abs(a[p][q]) < 1e-300) continue;
                const theta = (a[q][q] - a[p][p]) / (2 * a[p][q]);
                const t = Math.sign(theta || 1) / (Math.abs(theta) + Math.sqrt(theta * theta + 1));
                const c = 1 / Math.sqrt(t * t + 1);
                const s = t * c;
                for (let k = 0; k < n; k++) {
                    const akp = a[k][p];
                    const akq = a[k][q];
                    a[k][p] = c * akp - s * akq;
                    a[k][q] = s * akp + c * akq;
                }
                for (let k = 0; k < n; k++) {
                    const apk = a[p][k];
                    const aqk = a[q][k];
                    a[p][k] = c * apk - s * aqk;
                    a[q][k] = s * apk + c * aqk;
                }
                for (let k = 0; k < n; k++) {
                    const vkp = v[k][p];
                    const vkq = v[k][q];
                    v[k][p] = c * vkp - s * vkq;
                    v[k][q] = s * vkp + c * vkq;
                }
            }
        }
    }
    return { values: a.map((r, i) => r[i]), vectors: v };
}

// Solve min ||X b - y|| for b. Columns are scaled to unit norm first so the
// tolerance means the same thing for Intellect (hundreds) and percents.
function leastSquares(X, y, relTol) {
    const tol = relTol === undefined ? 1e-9 : relTol;
    const n = X.length;
    const p = n ? X[0].length : 0;
    const scale = new Array(p).fill(0);
    for (const row of X) for (let j = 0; j < p; j++) scale[j] += row[j] * row[j];
    for (let j = 0; j < p; j++) scale[j] = scale[j] > 0 ? Math.sqrt(scale[j]) : 1;
    const XtX = Array.from({ length: p }, () => new Array(p).fill(0));
    const Xty = new Array(p).fill(0);
    for (let i = 0; i < n; i++) {
        const r = X[i].map((x, j) => x / scale[j]);
        for (let j = 0; j < p; j++) {
            Xty[j] += r[j] * y[i];
            for (let k = 0; k < p; k++) XtX[j][k] += r[j] * r[k];
        }
    }
    const { values, vectors } = jacobiEigen(XtX);
    const maxEig = Math.max(...values.map(Math.abs), 0);
    const b = new Array(p).fill(0);
    let rank = 0;
    let minKept = Infinity;
    for (let e = 0; e < p; e++) {
        if (!(values[e] > tol * maxEig)) continue;
        rank += 1;
        minKept = Math.min(minKept, values[e]);
        let proj = 0;
        for (let j = 0; j < p; j++) proj += vectors[j][e] * Xty[j];
        for (let j = 0; j < p; j++) b[j] += (vectors[j][e] * proj) / values[e];
    }
    return {
        beta: b.map((x, j) => x / scale[j]),
        rank,
        condition: rank ? Math.sqrt(maxEig / minKept) : Infinity,
    };
}

module.exports = { jacobiEigen, leastSquares };
