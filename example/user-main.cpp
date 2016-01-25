#include "mpi.h"
#include "diffusion.h"

const int T_MAX = 100;

int main (int argc, char **argv) {
  Formura_Navigator navi;
  MPI_Init(argc, argv);
  Formura_Init(&navi, MPI_WORLD_COMM);
  while(navi.time_step < T_MAX) {
    Formura_Forward(&navi);
  }
  MPI_Finalize();
}
