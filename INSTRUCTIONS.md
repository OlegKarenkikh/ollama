# Docker Build and Push Instructions

The environment encountered significant issues downloading the large base images required for the ROCm build (`rocm/dev-almalinux-8:7.1.1-complete`). As a result, the builds could not be completed within the session.

However, a script `push_images.sh` has been provided to automate the tagging and pushing process once the images are successfully built.

## To Build Manually

Run the following commands (adjust `PARALLEL` as needed):

```bash
# Login (if not already)
echo "dckr_pat_..." | docker login -u olegkarenkikh --password-stdin

# Build Latest
docker build . --build-arg PARALLEL=4 -t olegkarenkikh/ollama:latest

# Build ROCm
docker build . --build-arg PARALLEL=4 --build-arg FLAVOR=rocm -t olegkarenkikh/ollama:rocm
```

## To Push

Once built, run the script:

```bash
./push_images.sh
```
