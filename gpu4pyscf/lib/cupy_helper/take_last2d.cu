/* Copyright 2023 The GPU4PySCF Authors. All Rights Reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <cuda_runtime.h>
#include <stdio.h>
#define THREADS        32
#define COUNT_BLOCK     80

__global__
static void _take_last2d(double *a, const double *b, int *indices, int n)
{
    size_t i = blockIdx.z;
    int j = blockIdx.x * blockDim.x + threadIdx.x;
    int k = blockIdx.y * blockDim.y + threadIdx.y;
    if (j >= n || k >= n) {
        return;
    }

    int j_b = indices[j];
    int k_b = indices[k];
    int off = i * n * n;

    a[off + j * n + k] = b[off + j_b * n + k_b];
}

__global__
static void _takebak(double *out, double *a, int *indices,
                     int count, int n_o, int n_a)
{
    int i0 = blockIdx.y * COUNT_BLOCK;
    int j = blockIdx.x * blockDim.x + threadIdx.x;
    if (j > n_a) {
        return;
    }

    // a is on host with zero-copy memory. We need enough iterations for
    // data prefetch to hide latency
    int i1 = i0 + COUNT_BLOCK;
    if (i1 > count) i1 = count;
    int jp = indices[j];
#pragma unroll
    for (size_t i = i0; i < i1; ++i) {
        out[i * n_o + jp] = a[i * n_a + j];
    }
}

extern "C" {
int take_last2d(cudaStream_t stream, double *a, const double *b, int *indices, int blk_size, int n)
{
    // reorder j and k in a[i,j,k] with indicies
    int ntile = (n + THREADS - 1) / THREADS;
    dim3 threads(THREADS, THREADS);
    dim3 blocks(ntile, ntile, blk_size);
    _take_last2d<<<blocks, threads, 0, stream>>>(a, b, indices, n);
    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess) {
        return 1;
    }
    return 0;
}

int takebak(cudaStream_t stream, double *out, double *a_h, int *indices,
            int count, int n_o, int n_a)
{
    double *a_d;
    cudaError_t err;
    err = cudaHostGetDevicePointer(&a_d, a_h, 0); // zero-copy check
    if (err != cudaSuccess) {
        return 1;
    }

    int ntile = (n_a + THREADS*THREADS - 1) / (THREADS*THREADS);
    int ncount = (count + COUNT_BLOCK - 1) / COUNT_BLOCK;
    dim3 threads(THREADS*THREADS);
    dim3 blocks(ntile, ncount);
    _takebak<<<blocks, threads, 0, stream>>>(out, a_d, indices, count, n_o, n_a);
    err = cudaGetLastError();
    if (err != cudaSuccess) {
        return 1;
    }
    return 0;
}
}
