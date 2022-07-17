#include<stdio.h>
#include"error_check.h"
#include"time_helper.h"
#define DTYPE double
#define DTYPE_OUTPUT_FORMAT "%.3lf"

#define BLOCK_SIZE 256
#define PRINT_SIZE 8

double adj_diff_cpu(DTYPE *data_input, DTYPE *data_output, int n)
{
	double begin, time_cost;
	begin = cpuSecond();
	for(int i=1; i<n; i++)
	{
		DTYPE x_i = data_input[i];
		DTYPE x_i_minus_one = data_input[i-1];
		data_output[i] = x_i - x_i_minus_one;
	}
	time_cost = cpuSecond()-begin;
	return time_cost;
}

__global__ void kernel_adj_diff_naive(DTYPE *input, DTYPE *output, DTYPE n)
{
    int i = threadIdx.x + blockDim.x*blockIdx.x;
    if(i>0 && i<n)
    {
    	DTYPE x_i = input[i];
		DTYPE x_i_minus_one = input[i-1];
	    output[i] = x_i - x_i_minus_one;
    }
}

double adj_diff_naive(DTYPE *data_input, DTYPE *data_output, int n)
{
	double begin, time_cost;
	DTYPE *d_data_input = NULL;
	DTYPE *d_data_output = NULL;
	CHECK(cudaMalloc((void **)&d_data_input, n*sizeof(DTYPE)));
	CHECK(cudaMalloc((void **)&d_data_output, n*sizeof(DTYPE)));
	CHECK(cudaMemcpy(d_data_input, data_input, n*sizeof(DTYPE), cudaMemcpyHostToDevice));
	CHECK(cudaMemset(d_data_output, 0, n*sizeof(DTYPE)));

	int blockDim = BLOCK_SIZE;
	int gridDim = (n-1)/blockDim + 1;
	begin = cpuSecond();
	kernel_adj_diff_naive<<<gridDim, blockDim>>>(d_data_input, d_data_output, n);
    CHECK(cudaDeviceSynchronize());
	time_cost = cpuSecond()-begin;
	CHECK(cudaGetLastError());
	CHECK(cudaMemcpy(data_output, d_data_output, n*sizeof(DTYPE), cudaMemcpyDeviceToHost));
	CHECK(cudaFree(d_data_input));
	CHECK(cudaFree(d_data_output));
	return time_cost;
}

// Todo
//     use shared memory, but do not use __syncthreads()
__global__ void kernel_adj_diff_static_shmem(DTYPE *input, DTYPE *output, int n)
{
    unsigned int i = threadIdx.x + blockDim.x*blockIdx.x;
	__shared__ DTYPE s_data[BLOCK_SIZE];
	__shared__ char count[BLOCK_SIZE];
	s_data[threadIdx.x] = input[i];

	count[threadIdx.x] = 'y';
	for(int co=0;co!=BLOCK_SIZE;)
	{
		co=0;
		for(int k=0;k<BLOCK_SIZE;k++)
		{
			if(count[k]=='y') co++;
		}
	}

    if(threadIdx.x>0)
    {
		output[i] = s_data[threadIdx.x] - s_data[threadIdx.x - 1];
    }else if(i>0){
		output[i] = s_data[threadIdx.x] - input[i-1];
	}
}

double adj_diff_static_shmem(DTYPE *data_input, DTYPE *data_output, DTYPE n)
{
	double begin, time_cost;
	DTYPE *d_data_input = NULL;
	DTYPE *d_data_output = NULL;
	CHECK(cudaMalloc((void **)&d_data_input, n*sizeof(DTYPE)));
	CHECK(cudaMalloc((void **)&d_data_output, n*sizeof(DTYPE)));
	CHECK(cudaMemcpy(d_data_input, data_input, n*sizeof(DTYPE), cudaMemcpyHostToDevice));
	CHECK(cudaMemset(d_data_output, 0, n*sizeof(DTYPE)));

	int blockDim = BLOCK_SIZE;
	int gridDim = (n-1)/blockDim + 1;
	begin = cpuSecond();
	kernel_adj_diff_static_shmem<<<gridDim, blockDim>>>(d_data_input, d_data_output, n);
    CHECK(cudaDeviceSynchronize());
	time_cost = cpuSecond()-begin;
	CHECK(cudaGetLastError());
	CHECK(cudaMemcpy(data_output, d_data_output, n*sizeof(DTYPE), cudaMemcpyDeviceToHost));
	CHECK(cudaFree(d_data_input));
	CHECK(cudaFree(d_data_output));
	return time_cost;
}


void init_data(DTYPE *arr, int n)
{
	for(int i=1; i<n; i++){
		arr[i] = arr[i-1]+i;
	}
}

void print_arr(DTYPE *arr, int n){
	for(int i=0; i<n; i++){
		printf(DTYPE_OUTPUT_FORMAT, arr[i]);
	}
}

int compare(DTYPE *arr, DTYPE *ref, int n){
	for(int i=0; i<n; i++){
		if(abs(arr[i]-ref[i])>1e-3){
			return -1;
		}
	}
	return 1;
}
 
int main() 
{
	int n = 1<<25;
	DTYPE *data_input = (DTYPE *)malloc(n*sizeof(DTYPE));
	DTYPE *data_output_cpu = (DTYPE *)malloc(n*sizeof(DTYPE));
	DTYPE *data_output_from_gpu = (DTYPE *)malloc(n*sizeof(DTYPE));
    
	init_data(data_input, n);
	printf("Input:\n");
	print_arr(data_input, PRINT_SIZE);
	printf("\nTime cost (CPU):%.9lf s\n", adj_diff_cpu(data_input, data_output_cpu, n));
	printf("Output:\n");
	print_arr(data_output_cpu, PRINT_SIZE);
    

	/*
	*  adj_diff_naive  *
	*/
    printf("\n\n\nGPU versions:\n");
	
    printf("\n1.adj_diff_naive:\n");
	printf("Time cost (GPU):%.9lf s\n", adj_diff_naive(data_input, data_output_from_gpu, n));
	if(compare(data_output_from_gpu, data_output_cpu, n)==1){ printf("Passed!\n");	}
	else{ printf("Failed!\n");	} 
	memset(data_output_from_gpu, 0, n*sizeof(DTYPE));

	/*
	*  adj_diff_static_shmem  *
	*/
	init_data(data_input, n);
	printf("\n\n2.adj_difference with statically allocated shared memory:\n");
	printf("Time cost (GPU):%.9lf s\n", adj_diff_static_shmem(data_input, data_output_from_gpu, n));
	if(compare(data_output_from_gpu, data_output_cpu, n)==1){ printf("Passed!\n");	}
	else{ printf("Failed!\n");	} 
	memset(data_output_from_gpu, 0, n*sizeof(DTYPE));

    return 0;
}

