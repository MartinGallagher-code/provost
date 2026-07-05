# Handoff -- EnvoyExtract/strategies/hpc

## Status: Complete (12 strategies)

HPC job scheduler and MPI-related extraction strategies for High Performance Computing environments.

## Strategies

| File | Format | Description |
|------|--------|-------------|
| `slurm.sh` | Slurm scheduler output | `sacct`, `squeue`, `sinfo`, `scontrol show job` |
| `pbs.sh` | PBS/Torque output | `qstat`, `pbsnodes`, job output files |
| `lsf.sh` | IBM LSF output | `bjobs`, `bhosts`, `bqueues` |
| `sge.sh` | SGE/UGE output | `qstat`, `qhost`, accounting files |
| `mpi-profile.sh` | MPI profiling output | mpiP summaries, Intel MPI statistics |
| `mpi-ranklog.sh` | Multi-rank MPI output | Rank-prefixed interleaved stdout |
| `mpi-display-map.sh` | Open MPI display-map | Process placement and binding info |
| `darshan.sh` | Darshan I/O logs | `darshan-parser` text output |
| `flux.sh` | Flux scheduler output | `flux jobs`, `flux resource list`, `flux job info` |
| `htcondor.sh` | HTCondor output | `condor_q`, `condor_status`, classad key=value |
| `kubectl-top-nodes.sh` | kubectl top nodes | Node CPU/memory resource usage |
| `kubectl-top-pods.sh` | kubectl top pods | Pod CPU/memory resource usage |

## Next Steps

- Add sample files for remaining strategies without samples
