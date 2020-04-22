/**************************************************************************
* This file contains implementation of pqp (parallel quadratic programming)
* GPU version unoptimised (Basic) for MPC Term Project of HP3 Course.
* Group 7 CSE Dept. IIT KGP
*	Objective function: 1/2 U'QpU + Fp'U + 1/2 Mp
*	Constraints: GpU <= Kp
**************************************************************************/
#include<stdio.h>
#include<stdlib.h>
#include<math.h>
#include<cuda.h>
#include<cuda_runtime.h>

#define NUM_ITER 100

#define pHorizon 1
#define nState 29
#define nInput 7
#define nOutput 7
#define nDis 1

#define erc 7
#define eac 100000
#define eaj 100000
#define erj 7

__global__ void printMat(float *mat, int N, int M)
{
	printf("printing mat\n");
	for(int i=0;i<N;i++)
	{
		for(int j=0;j<M;j++)
		{
			printf("%f ",mat[i*M+j]);
		}
		printf("\n");
	}
	printf("\n");
}



__global__ void initMatCuda(float *mat, float val, int N)								
{
	int blockNum = blockIdx.z * (gridDim.x * gridDim.y) + blockIdx.y * gridDim.x + blockIdx.x;
	int threadNum = threadIdx.z * (blockDim.x * blockDim.y) + threadIdx.y * (blockDim.x) + threadIdx.x;
	int id = blockNum * (blockDim.x * blockDim.y * blockDim.z) + threadNum;
	if(id<N)	
	{
		mat[id] = val;
	}
}

/**************************************************************************
* This is utility function initialize the matrix
*   1. Parameter is float type matrix pointer (*mat), float val, 
*		size of matrix 
*   2. Return type void
**************************************************************************/
void initMat(float *mat, float val, int N)								
{
	dim3 block = 1024;
	dim3 grid = (N+1024-1)/1024;

	initMatCuda<<<grid, block>>>(mat, val, N);
}



float *newMatrixCUDA(int n, int m)			
{
	float *tmp = NULL;
	
	cudaError_t err = cudaMalloc((void **)&tmp, n*m*sizeof(float));

	if ( err != cudaSuccess )
	{
		printf (" Failed to allocate device matrix! %s\n", cudaGetErrorString(err));
		exit ( EXIT_FAILURE ) ;
	}

	initMat(tmp, 0, n*m);
	return tmp;
}
/**************************************************************************
* This is utility function for create new  matrix
*   1. Parameter is (int n, int m) dimension of (n X m matrix) , 
*	2. Return pointer of new matrix
*   3. This function create dynamic size matrix using malloc
**************************************************************************/
float *newMatrix(int n, int m)			
{
	float *tmp = (float *)malloc(n*m*sizeof(float));
	for(int i=0;i<n*m;i++)
	{
		tmp[i] = 0;
	}
	return tmp;
}



void copyToDevice(float *dM, float *hM, int n, int m)
{
	int size = n*m;
	cudaMemcpy (dM ,hM, size * sizeof ( float ) , cudaMemcpyHostToDevice );
}

void copyToHost(float *hM, float *dM, int n, int m)
{
	int size = n*m;
	cudaMemcpy (hM ,dM, size * sizeof ( float ) , cudaMemcpyDeviceToHost );
}



__global__ void copyMatrixCuda(float *output, float *mat, int a, int b)		
{
	int blockNum = blockIdx.z * (gridDim.x * gridDim.y) + blockIdx.y * gridDim.x + blockIdx.x;
	int threadNum = threadIdx.z * (blockDim.x * blockDim.y) + threadIdx.y * (blockDim.x) + threadIdx.x;
	int id = blockNum * (blockDim.x * blockDim.y * blockDim.z) + threadNum;
	if(id<a*b)	
	{
		output[id] = mat[id];
	}
}

void copyMatrix(float *output, float *mat, int a, int b)		
{
	dim3 block = 1024;
	dim3 grid = (a*b+1024-1)/1024;

	copyMatrixCuda<<<grid,block>>>(output, mat, a, b);
}



__global__ void transposeCuda(float *odata, float *idata, int n, int m)
{
	int x = blockIdx.x * blockDim.x + threadIdx.x;
	int y = blockIdx.y * blockDim.y + threadIdx.y;
	
	if(x<n && y<m)
		odata[y*n+x] = idata[x*m+y];
}

void transpose(float *odata, float *idata, int n, int m)
{
	dim3 block(32,32,1);
	dim3 grid((n+31)/32, (m+31)/32);
	
	transposeCuda<<<grid,block>>>(odata,idata,n,m);
}



__global__ void matrixMultiplyCuda(float *output, float *matrix1, float *matrix2, int a, int b, int c) 		//mat1-a*b	mat2-b*c
{		
	int x = blockIdx.x * blockDim.x + threadIdx.x;
	int y = blockIdx.y * blockDim.y + threadIdx.y;
		
	if(x<a && y<c)
	{
		float val = 0;
		for(int k=0;k<b;k++)
		{
			val += matrix1[x*b+k]*matrix2[k*c+y];
		}
		output[x*c+y] = val;
	}
}

void matrixMultiply(float *output, float *mat1, int transpose1, float *mat2, int transpose2, int a, int b, int c) 		//mat1-a*b	mat2-b*c 	
{
	float *tmp = newMatrixCUDA(a,c);
	
	float *matrix1;
	float *matrix2;
	
	if(transpose1 && a!=1 && b!=1)
	{
		matrix1 = newMatrixCUDA(a,b);
		transpose(matrix1, mat1, b,a);
			
	}
	else
	{
		matrix1 = mat1;
	}
	
	if(transpose2 && b!=1 && c!=1)
	{
		matrix2 = newMatrixCUDA(b,c);
		transpose(matrix2, mat1, c,b);
		
	}
	else
	{
		matrix2 = mat2;
	}
	
	dim3 block(32,32,1);
	dim3 grid((a+31)/32, (c+31)/32);
	matrixMultiplyCuda<<<grid, block>>>(output, matrix1, matrix2, a, b, c);
	
	if(transpose1 && a!=1 && b!=1)
	{
		cudaFree(matrix1);
	}
	if(transpose2 && b!=1 && c!=1)
	{
		cudaFree(matrix2);
	}

	cudaFree(tmp);
}

/**************************************************************************
* This is utility function for generating addition or substraction 
*	of two matrix
*   1. Parameter is (pointer of matrix1, pointer of matrix2, float sign,int n int m)
*		dimension of (n X m matrix) 
*	2. sign parameters for decide addition or substraction
*	3. Result write back in matrix1
**************************************************************************/

__global__ void matrixAddCuda(float *A, float *B, float sign, int a, int b) 			// adds b to a 	
{
	int blockNum = blockIdx.z * (gridDim.x * gridDim.y) + blockIdx.y * gridDim.x + blockIdx.x;
	int threadNum = threadIdx.z * (blockDim.x * blockDim.y) + threadIdx.y * (blockDim.x) + threadIdx.x;
	int id = blockNum * (blockDim.x * blockDim.y * blockDim.z) + threadNum;
	if(id<a*b)	
	{
		A[id] += sign * B[id];
	}
}

void matrixAdd(float *A, float *B, float sign, int a, int b) 			// adds b to a 	
{
	dim3 block = 1024;
	dim3 grid = (a*b+1024-1)/1024;

	matrixAddCuda<<<grid,block>>>(A,B,sign,a,b);
}



__global__ void negateMatrixCuda(float *mat, int n, int m)			
{
	int blockNum = blockIdx.z * (gridDim.x * gridDim.y) + blockIdx.y * gridDim.x + blockIdx.x;
	int threadNum = threadIdx.z * (blockDim.x * blockDim.y) + threadIdx.y * (blockDim.x) + threadIdx.x;
	int id = blockNum * (blockDim.x * blockDim.y * blockDim.z) + threadNum;
	if(id<n*m)	
	{
		mat[id] = -mat[id];
	}
}

void negateMatrix(float *mat, int n, int m)			
{
	dim3 block = 1024;
	dim3 grid = (n*m+1024-1)/1024;

	negateMatrixCuda<<<grid,block>>>(mat,n,m);
}



__global__ void matrixPosCuda(float *mat1, float *mat2, int n, int m)			
{
	int blockNum = blockIdx.z * (gridDim.x * gridDim.y) + blockIdx.y * gridDim.x + blockIdx.x;
	int threadNum = threadIdx.z * (blockDim.x * blockDim.y) + threadIdx.y * (blockDim.x) + threadIdx.x;
	int id = blockNum * (blockDim.x * blockDim.y * blockDim.z) + threadNum;
	if(id<n*m)	
	{
		mat1[id] = fmaxf(0.0, mat2[id]);

	}
}

void matrixPos(float *mat1, float *mat2, int n, int m)			
{
	dim3 block = 1024;
	dim3 grid = (n*m+1024-1)/1024;

	matrixPosCuda<<<grid,block>>>(mat1,mat2,n,m);
}



__global__ void matrixNegCuda(float *mat1, float *mat2, int n, int m)			
{
	int blockNum = blockIdx.z * (gridDim.x * gridDim.y) + blockIdx.y * gridDim.x + blockIdx.x;
	int threadNum = threadIdx.z * (blockDim.x * blockDim.y) + threadIdx.y * (blockDim.x) + threadIdx.x;
	int id = blockNum * (blockDim.x * blockDim.y * blockDim.z) + threadNum;
	if(id<n*m)	
	{
		mat1[id] = fmaxf(0.0, -mat2[id]);
	}
}

void matrixNeg(float *mat1, float *mat2, int n, int m)			
{
	dim3 block = 1024;
	dim3 grid = (n*m+1024-1)/1024;

	matrixNegCuda<<<grid,block>>>(mat1,mat2,n,m);
}



__global__ void diagonalAddCuda(float *theta, float *tmp, int N)			
{
	int blockNum = blockIdx.z * (gridDim.x * gridDim.y) + blockIdx.y * gridDim.x + blockIdx.x;
	int threadNum = threadIdx.z * (blockDim.x * blockDim.y) + threadIdx.y * (blockDim.x) + threadIdx.x;
	int id = blockNum * (blockDim.x * blockDim.y * blockDim.z) + threadNum;
	if(id<N)	
	{
		theta[id*N+id] = fmaxf(tmp[id],5.0);
	}
}

void diagonalAdd(float *theta, float *tmp, int N)			
{
	dim3 block = 1024;
	dim3 grid = (N+1024-1)/1024;

	diagonalAddCuda<<<grid,block>>>(theta,tmp,N);
}



__global__ void compareCuda(float *GpU, float *Kp, int *re, int N)				
{
	int blockNum = blockIdx.z * (gridDim.x * gridDim.y) + blockIdx.y * gridDim.x + blockIdx.x;
	int threadNum = threadIdx.z * (blockDim.x * blockDim.y) + threadIdx.y * (blockDim.x) + threadIdx.x;
	int id = blockNum * (blockDim.x * blockDim.y * blockDim.z) + threadNum;
	if(id<N)	
	{
		if(GpU[id] > Kp[id]+fmaxf(erc*Kp[id], eac))
		{
			*re = 0;
		}
	}
}

void compare(float *GpU, float *Kp, int *re, int N)				
{
	dim3 block = 1024;
	dim3 grid = (N+1024-1)/1024;

	compareCuda<<<grid,block>>>(GpU, Kp, re, N);
}




__global__ void updYCuda(float *Y_next, float *numerator, float *denominator, float *Y, int N)   
{
	int blockNum = blockIdx.z * (gridDim.x * gridDim.y) + blockIdx.y * gridDim.x + blockIdx.x;
	int threadNum = threadIdx.z * (blockDim.x * blockDim.y) + threadIdx.y * (blockDim.x) + threadIdx.x;
	int id = blockNum * (blockDim.x * blockDim.y * blockDim.z) + threadNum;
	
	if(id<N)
	{
		Y_next[id] = numerator[id]/denominator[id]*Y[id];
	}
}

void updY(float *Y_next, float *numerator, float *denominator, float *Y, int N)   
{
	dim3 block = 1024;
	dim3 grid = (N+1023)/1024;
	
	updYCuda<<<grid, block>>>(Y_next, numerator, denominator, Y, N);
}




void Gauss_Jordan(float *A,float *res, int N)
{
    /*
    size=Size of input matrix
    A=input matrix
    res= inverted matrix
    */
    float temp;
    float *matrix = newMatrix(N, 2*N);

    for (int i = 0; i < N; i++) 
    { 
        for (int j = 0; j < 2 * N; j++) 
        { 
            matrix[i*2*N+j]=0;
            if (j == (i + N)) 
                matrix[i*2*N+j] = 1; 
        } 
    }

    for (int i = 0; i < N; i++) 
    { 
        for (int j = 0; j < N; j++) 
        { 
            matrix[i*2*N+j]=A[i*N+j];

        } 
    }

    for (int i = N - 1; i > 0; i--) 
    { 
        if (matrix[(i - 1)*2*N+0] < matrix[i*2*N+0]) 
            for (int j = 0; j < 2 * N; j++) 
            { 
                temp = matrix[i*2*N+j]; 
                matrix[i*2*N+j] = matrix[(i - 1)*2*N+j]; 
                matrix[(i - 1)*2*N+j] = temp; 
            } 
    }

    for (int i = 0; i < N; i++)
    { 

        for (int j = 0; j < N; j++) 
        { 
            if (j != i) 
            { 
                temp = matrix[j*2*N+i] / matrix[i*2*N+i]; 
                for (int k = 0; k < 2 * N; k++) 
                { 
                    matrix[j*2*N+k] -= matrix[i*2*N+k] * temp; 
                } 
            } 
        } 
    } 

    for (int i = 0; i < N; i++)
    { 
        temp = matrix[i*2*N+i]; 
        for (int j = 0; j < 2 * N; j++)
        {
            matrix[i*2*N+j] = matrix[i*2*N+j] / temp; 
        } 
    }

    for (int i = 0; i < N; i++) 
    { 
        for (int j = N; j <2*N; j++) 
        { 
            res[i*N+j-N]=matrix[i*2*N+j];

        } 
    }

    free(matrix);
}



void computeUfromY(float *U, float *Y, float *Fp, float *Gp, float *Qp_inv, int N, int M)
{
	float *tmp = newMatrixCUDA(M,1);
	matrixMultiply(tmp, Gp, 1, Y, 0, M, N, 1);
	matrixAdd(tmp, Fp, 1, M, 1);
	matrixMultiply(U, Qp_inv, 0, tmp, 0, M, M, 1);
	negateMatrix(U, M, 1);
	cudaFree(tmp);
}

void computeFp(float *Fp, float *Fp1, float *Fp2, float *Fp3, float *D, float *x)
{
	matrixMultiply(Fp, Fp1, 0, D, 0, nInput*pHorizon, nDis*pHorizon, 1);
	float *Fp2x = newMatrixCUDA(nInput*pHorizon,1);
	matrixMultiply(Fp2x, Fp2, 0, x, 0, nInput*pHorizon, nState, 1);
	matrixAdd(Fp, Fp2x, 1, nInput*pHorizon, 1);
	matrixAdd(Fp, Fp3, -1, nInput*pHorizon, 1);
	
	cudaFree(Fp2x);	
}

void computeMp(float *Mp, float *Mp1, float *Mp2, float *Mp3, float *Mp4, float *Mp5, float *Mp6, float *D, float *x)
{
	initMat(Mp, 0, 1);

	float *tmp = newMatrixCUDA(1,nState);
	matrixMultiply(tmp, x, 1, Mp1, 0, 1, nState, nState);
	matrixMultiply(tmp, tmp, 0, x, 0, 1, nState, 1);

	matrixAdd(Mp, tmp, 0.5, 1,1);
//	printMat<<<1,1>>>(Mp, 1, 1);

	matrixMultiply(tmp, D, 1, Mp2, 0, 1, nDis*pHorizon, nState);
	matrixMultiply(tmp, tmp, 0, x, 0, 1, nState, 1);

	matrixAdd(Mp, tmp, 0.5, 1,1);
	
	matrixMultiply(tmp, Mp4, 1, x, 0, 1, nState, 1);

	matrixAdd(Mp, tmp, 0.5, 1,1);

	cudaFree(tmp);
	tmp = newMatrixCUDA(1, nDis*pHorizon);
	matrixMultiply(tmp, D, 1, Mp3, 0, 1, nDis*pHorizon, nDis*pHorizon);
	matrixMultiply(tmp, tmp, 0, D, 0, 1, nDis*pHorizon, 1);

	matrixAdd(Mp, tmp, 0.5, 1,1);

	matrixMultiply(tmp, Mp5, 1, D, 0, 1, nDis*pHorizon, 1);

	matrixAdd(Mp, tmp, 0.5, 1,1);

	matrixAdd(Mp, Mp6, 0.5, 1,1);
	cudaFree(tmp);
}

void computeQd(float *Qd, float *Gp_Qp_inv, float *Gp, int N, int M)
{
	matrixMultiply(Qd, Gp_Qp_inv, 0, Gp, 1, N, M, N);	
}

void computeFd(float *Fd, float *Gp_Qp_inv, float *Fp, float *Kp, int N, int M)
{
	matrixMultiply(Fd, Gp_Qp_inv, 0, Fp, 0, N, M, 1);
	matrixAdd(Fd, Kp, 1, N, 1);
}

void computeMd(float *Md, float *Fp, float* Qp_inv, float* Mp, int N, int M)
{
	float *tmp = newMatrixCUDA(1,M);
	matrixMultiply(tmp, Fp, 1, Qp_inv, 0, 1, M, M);
	matrixMultiply(Md, tmp, 0, Fp, 0, 1, M, 1);
	matrixAdd(Md, Mp, -1, 1, 1);
	cudaFree(tmp);
}

void convertToDual(float *Qd, float *Fd, float *Md, float *Qp_inv, float *Gp, float *Kp, float *Fp, float *Mp, int N, int M)
{	
	float *Gp_Qp_inv = newMatrixCUDA(N,M);
	matrixMultiply(Gp_Qp_inv, Gp, 0, Qp_inv, 0, N, M, M);
	computeQd(Qd, Gp_Qp_inv, Gp, N, M);
	computeFd(Fd, Gp_Qp_inv, Fp, Kp, N, M);
	computeMd(Md, Fp, Qp_inv, Mp, N, M);

	cudaFree(Gp_Qp_inv);
}

void computeTheta(float *theta, float *Qd, int N)
{
	float *Qdn = newMatrixCUDA(N,N);
	matrixNeg(Qdn, Qd, N, N);

	float *one = newMatrixCUDA(N,1);
	initMat(one, 1, N);

	float *tmp = newMatrixCUDA(N,1);
	matrixMultiply(tmp, Qdn, 0, one, 0, N,N,1);

	diagonalAdd(theta, tmp, N);

	cudaFree(Qdn);
	cudaFree(one);
	cudaFree(tmp);
}

void computeQdp_theta(float *Qdp_theta, float *Qd, float *theta, int N)
{
	matrixPos(Qdp_theta, Qd, N, N);
	matrixAdd(Qdp_theta, theta, 1, N, N);
}

void computeQdn_theta(float *Qdn_theta, float *Qd, float *theta, int N)
{
	matrixNeg(Qdn_theta, Qd, N, N);
	matrixAdd(Qdn_theta, theta, 1, N, N);
}

void computealphaY(float *alphaY, float *ph, float *Qd, float *Y, float *Fd, int N)
{
	float *temp = newMatrixCUDA(1,N);

	matrixMultiply(temp, ph, 1, Qd, 0, 1, N, N);
	matrixMultiply(temp, temp, 0, ph, 0, 1, N, 1);

	float *com = newMatrix(1,1);
	copyToHost(com,temp,1,1);
	if(com[0] > 0)
	{
		float *temp2 = newMatrixCUDA(1,N);

		matrixMultiply(temp2, Y, 1, Qd, 0, 1, N, N);
		
		matrixAdd(temp2, Fd, 1, 1, N);
		
		matrixMultiply(temp2, temp2, 0, ph, 0, 1, N, 1);

		float *com2 = newMatrix(1,1);
		copyToHost(com2, temp2, 1,1);
		*alphaY = -com2[0]/com[0];

		free(com2);
		cudaFree(temp2);
	}
	else
	{
		alphaY = 0;
	}
	free(com);
	cudaFree(temp);
}

void updateY1(float *Y_next, float *Y, float alphaY, float *ph, int N)
{
	copyMatrix(Y_next, Y, N, 1);
	matrixAdd(Y_next, ph, alphaY, N, 1);
}

void updateY2(float *Y_next, float *Y, float *Qdp_theta, float *Qdn_theta, float *Fd, float *Fdp, float *Fdn, int N)
{
	float *numerator = newMatrixCUDA(N,1);
	float *denominator = newMatrixCUDA(N,1);

	matrixMultiply(numerator, Qdn_theta, 0, Y, 0, N, N, 1);
	matrixMultiply(denominator, Qdp_theta, 0, Y, 0, N, N, 1);

	matrixAdd(numerator, Fdn, 1, N, 1);
	matrixAdd(denominator, Fdp, 1, N, 1);

	updY(Y_next, numerator, denominator, Y, N);

	cudaFree(numerator);
	cudaFree(denominator);
}

void computeph(float *ph, float *Qd, float *Y, float *Fd, int N)
{
	matrixMultiply(ph, Qd, 0, Y, 0, N, N, 1);
	matrixAdd(ph, ph, 1, N, 1);
	matrixNeg(ph, ph, N, 1);
}

int checkFeas(float *U, float *Gp, float *Kp, int N, int M)
{
	float *tmp = newMatrixCUDA(N,1);
	matrixMultiply(tmp, Gp, 0, U, 0, N, M, 1);
	int re = 1;
	compare(tmp, Kp, &re, N);

	cudaFree(tmp);
	return re;
}	

float computeCost(float *Z, float *Q, float *F, float *M, int N)
{
	float *J=newMatrixCUDA(1,1);

	float *tmp = newMatrixCUDA(1,N);
	matrixMultiply(tmp, Z, 1, Q, 0, 1, N, N);
	matrixMultiply(tmp, tmp, 0, Z, 0, 1, N, 1);

	matrixAdd(J, tmp, 0.5, 1,1);

	matrixMultiply(tmp, F, 1, Z, 0, 1, N, 1);

	matrixAdd(J, tmp, 1, 1,1);

	matrixAdd(J, M, 0.5, 1,1);
	

	float *hJ = newMatrix(1,1);
	copyToHost(hJ,J,1,1);

	float cost = hJ[0];
	free(hJ);
	cudaFree(J);
	cudaFree(tmp);

	return cost;
}

int terminate(float *Y, float *Qd, float *Fd, float *Md, float *U, float *Qp, float *Qp_inv, float *Fp, float *Mp, float *Gp, float *Kp, int N, int M)
{
	computeUfromY(U, Y, Fp, Gp, Qp_inv, N, M);

	if(!checkFeas(U, Gp, Kp, N, M))	return 0;

	float Jd = computeCost(Y, Qd, Fd, Md, N);
	float Jp = computeCost(U, Qp, Fp, Mp, M);

	if(Jp>-Jd)	return 0;
	if(Jp+Jd>eaj)	return 0;
	if((Jp+Jd)/fabs(Jd)>erj) return 0;

	return 1;
}

void solveQuadraticDual(float *Y, float *Qd, float *Fd, float *Md, float *U, float *Qp, float *Qp_inv, float *Fp, float *Mp, float *Gp, float *Kp, int N, int M)
{
	float *theta = newMatrixCUDA(N,N);
	float *Qdp_theta = newMatrixCUDA(N,N);
	float *Qdn_theta = newMatrixCUDA(N,N);
	float *Y_next = newMatrixCUDA(N,1);
	
	float *Fdn = newMatrixCUDA(N,1);
	float *Fdp = newMatrixCUDA(N,1);

	matrixPos(Fdp, Fd, N, 1);
	matrixNeg(Fdn, Fd, N, 1);
	
	computeTheta(theta, Qd, N);
	computeQdp_theta(Qdp_theta, Qd, theta, N);
	computeQdn_theta(Qdn_theta, Qd, theta, N);

	initMat(Y, 1000.0, N);

	float *ph = newMatrixCUDA(N,1);
	long int h=1;

	while(h<NUM_ITER)
	//while(!terminate(Y, Qd, Fd, Md, U, Qp, Qp_inv, Fp, Mp, Gp, Kp, N, M))
	{	
		if(1)
		{
			//update
			updateY2(Y_next, Y, Qdp_theta, Qdn_theta, Fd, Fdp, Fdn, N);			
		}
//		else
//		{
//			// accelerate
//			float alphaY=0;
//			computeph(ph, Qd, Y, Fd, N);
//			computealphaY(&alphaY, ph, Qd, Y, Fd, N);
//			updateY1(Y_next, Y, alphaY/10, ph, N);
//
//		}

		copyMatrix(Y, Y_next, N, 1);

		h++;
	}
	printf("Printing number of iterations = %ld\n",h);

	cudaFree(theta);
	cudaFree(Qdp_theta);
	cudaFree(Qdn_theta);
	cudaFree(Y_next);
	cudaFree(ph);
	cudaFree(Fdp);
	cudaFree(Fdn);
}

void input(float *Qp_inv, float *Fp, float *Mp, float *Gp, float *Kp, float *x, float *D, float *theta, float *Z, int N, int M, char *fi)
{
	int tmp;
	FILE *fp = fopen(fi, "r");
	fscanf(fp, "%d%d", &tmp,&tmp);
	for(int i=0;i<M;i++)
	{
		fscanf(fp, "%f", &Qp_inv[i*M+i]);
	}

	for(int i=0;i<M;i++)
	{
		fscanf(fp, "%f", &Fp[i]);
	}

 	fscanf(fp, "%f", Mp);

	for(int i=0;i<N;i++)
	{
		fscanf(fp, "%f", &Kp[i]);
	}

	for(int i=0;i<N;i++)
	{
		Kp[i] = fabs(10.0*rand()/RAND_MAX);
		for(int j=0;j<M;j++)
		{
			int tmp;
			fscanf(fp, "%d",&tmp);
			if(tmp%3 == 0)
			{
				Gp[i*M+j] = 0;
			}
			else if(tmp%3==2)
			{
				Gp[i*M+j] = -1;
			}
			else
			{
				Gp[i*M+j] = 1;
			}
		}
	}
}

int main(int argc, char *argv[])
{
	// QP is of parametric from 
	// J(U) = min U 1/2*U'QpU + Fp'U + 1/2*Mp
	// st GpU <= Kp
	
	cudaDeviceReset();
	 
	int N, M;
	FILE *fp;
	fp = fopen(argv[1], "r");
	fscanf(fp, "%d%d", &M, &N);
	fclose(fp);
	// host matrix
	float *hQp_inv = newMatrix(M,M);
	float *hQp = newMatrix(M,M);

	float *hFp1;
	float *hFp2;
	float *hFp3;

	float *hMp1;
	float *hMp2;
	float *hMp3;
	float *hMp4;
	float *hMp5;
	float *hMp6;

	float *hFp = newMatrix(M,1);
	float *hMp = newMatrix(1,1);
	float *hGp;
	float *hKp;
	float *hx;
	float *hD; 
	float *htheta; 
	float *hZ; 

	hFp1 = newMatrix(nInput*pHorizon, nDis*pHorizon);
	hFp2 = newMatrix(nInput*pHorizon, nState);
	hFp3 = newMatrix(1, nInput*pHorizon);
	hMp1 = newMatrix(nState, nState);
	hMp2 = newMatrix(nDis*pHorizon, nState);
	hMp3 = newMatrix(nDis*pHorizon, nDis*pHorizon);
	hMp4 = newMatrix(1, nState);
	hMp5 = newMatrix(1, nDis*pHorizon);
	hMp6 = newMatrix(1,1);
	hGp = newMatrix(N,M);
	hKp = newMatrix(N,1);
	hZ = newMatrix(nOutput*pHorizon, nState);
	htheta = newMatrix(nOutput*pHorizon, nDis*pHorizon);
	hD = newMatrix(nDis*pHorizon,1);
	hx = newMatrix(nState, 1);

	// device matrix
	float *Qp_inv = newMatrixCUDA(M,M);
	float *Qp = newMatrixCUDA(M,M);

	float *Fp1;
	float *Fp2;
	float *Fp3;

	float *Mp1;
	float *Mp2;
	float *Mp3;
	float *Mp4;
	float *Mp5;
	float *Mp6;

	float *Fp = newMatrixCUDA(M,1);
	float *Mp = newMatrixCUDA(1,1);
	float *Gp;
	float *Kp;
	float *x;
	float *D; 
	float *theta; 
	float *Z; 

	Fp1 = newMatrixCUDA(nInput*pHorizon, nDis*pHorizon);
	Fp2 = newMatrixCUDA(nInput*pHorizon, nState);
	Fp3 = newMatrixCUDA(1, nInput*pHorizon);
	Mp1 = newMatrixCUDA(nState, nState);
	Mp2 = newMatrixCUDA(nDis*pHorizon, nState);
	Mp3 = newMatrixCUDA(nDis*pHorizon, nDis*pHorizon);
	Mp4 = newMatrixCUDA(1, nState);
	Mp5 = newMatrixCUDA(1, nDis*pHorizon);
	Mp6 = newMatrixCUDA(1,1);
	Gp = newMatrixCUDA(N,M);
	Kp = newMatrixCUDA(N,1);
	Z = newMatrixCUDA(nOutput*pHorizon, nState);
	theta = newMatrixCUDA(nOutput*pHorizon, nDis*pHorizon);
	D = newMatrixCUDA(nDis*pHorizon,1);
	x = newMatrixCUDA(nState, 1);	

	input(hQp_inv, hFp, hMp, hGp, hKp, hx, hD, htheta, hZ, N, M, argv[1]);
	float tmp;
	fscanf(fp, "%f",&tmp);
	fclose(fp);
	Gauss_Jordan(hQp_inv, hQp, M);
	copyToDevice(Qp_inv, hQp_inv, M, M);
	copyToDevice(Qp, hQp, M, M);
	copyToDevice(Fp1, hFp1, nInput*pHorizon, nDis*pHorizon);
	copyToDevice(Fp2, hFp2, nInput*pHorizon, nState);
	copyToDevice(Fp3, hFp3, 1, nInput*pHorizon);
	copyToDevice(Mp1, hMp1, nState, nState);
	copyToDevice(Mp2, hMp2, nDis*pHorizon, nState);
	copyToDevice(Mp3, hMp3, nDis*pHorizon, nDis*pHorizon);
	copyToDevice(Mp4, hMp4, 1, nState);
	copyToDevice(Mp5, hMp5, 1, nDis*pHorizon);
	copyToDevice(Mp6, hMp6, 1,1);
	copyToDevice(Gp, hGp, 4*pHorizon*nInput, nInput*pHorizon);
	copyToDevice(Kp, hKp, 1,4*pHorizon*nInput);
	copyToDevice(Z, hZ, nOutput*pHorizon, nState);
	copyToDevice(D, hD, nDis*pHorizon,1);
	copyToDevice(theta, htheta, nOutput*pHorizon, nDis*pHorizon);
	copyToDevice(x, hx, nState, 1);

	//computeFp(Fp, Fp1, Fp2, Fp3, D, x);
	//computeMp(Mp, Mp1, Mp2, Mp3, Mp4, Mp5, Mp6, D, x);

	// matrices and vectors required for dual form of QP
	float *Qd = newMatrixCUDA(N,N);
	float *Fd = newMatrixCUDA(N,1);
	float *Md = newMatrixCUDA(1,1);	
	float *Y  = newMatrixCUDA(N,1);
	float *U  = newMatrixCUDA(M,1);

	convertToDual(Qd, Fd, Md, Qp_inv, Gp, Kp, Fp, Mp, N, M);

	solveQuadraticDual(Y, Qd, Fd, Md, U, Qp, Qp_inv, Fp, Mp, Gp, Kp, N, M);

	computeUfromY(U, Y, Fp, Gp, Qp_inv, N, M);

	float Jp = computeCost(U, Qp, Fp, Mp, M);
	float Jd = computeCost(Y, Qd, Fd, Md, N);

	printf("Jp = %f\n", Jp);
	printf("Jd = %f\n", Jd);
	
	float *hU = newMatrix(M,1);
	float *hY = newMatrix(N,1);

	copyToHost(hU,U,M,1);
	copyToHost(hY,Y,N,1);

	printf("Printing U*\n");
	for(int i=0;i<M;i++)
	{
		printf("\t%f\n", hU[i]);
	}

	free(hQp_inv);
	free(hQp);
	free(hFp1);
	free(hFp2);
	free(hFp3);
	free(hMp1);
	free(hMp2);
	free(hMp3);
	free(hMp4);
	free(hMp5);
	free(hMp6); 
	free(hFp);
	free(hMp);
	free(hGp);
	free(hKp);
	free(hx);
	free(hD);
	free(htheta);
	free(hZ);

	cudaFree(Qp_inv);
	cudaFree(Qp);
	cudaFree(Fp1);
	cudaFree(Fp2);
	cudaFree(Fp3);
	cudaFree(Mp1);
	cudaFree(Mp2);
	cudaFree(Mp3);
	cudaFree(Mp4);
	cudaFree(Mp5);
	cudaFree(Mp6); 
	cudaFree(Fp);
	cudaFree(Mp);
	cudaFree(Gp);
	cudaFree(Kp);
	cudaFree(x);
	cudaFree(D);
	cudaFree(theta);
	cudaFree(Z);
	
	cudaFree(Qd);
	cudaFree(Fd);
	cudaFree(Md);
	cudaFree(Y);
	cudaFree(U);
}