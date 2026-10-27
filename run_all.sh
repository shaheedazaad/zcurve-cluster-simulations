#!/bin/zsh
# Run from simulations/. Reinstalls the fork from GitHub (fork_repo below), then fits the chosen conditions on output/sim_data.rds.
# Regenerates output/sim_data.rds whenever gen_data.R has changed since it was written.
# Optional arguments: number of datasets to fit ("all" for every dataset), then which versions to fit.
# By default only the fork is refitted; existing old/unclustered results are kept and still compared.
#   ./run_all.sh                             every dataset, fork only
#   ./run_all.sh 36                          quick check, fork only
#   ./run_all.sh all old unclustered fork    every dataset, all versions
set -e
setopt pipefail
cd "${0:A:h}"

typeset -F SECONDS
n_datasets=$1
[[ $n_datasets == all ]] && n_datasets=
fits=(${@:2})
(( ${#fits} )) || fits=(fork)

# Whole seconds as e.g. 1h02m03s / 2m03s / 3s.
fmt_time() {
  local s=${1%.*}
  if (( s >= 3600 )); then printf '%dh%02dm%02ds' $((s / 3600)) $((s % 3600 / 60)) $((s % 60))
  elif (( s >= 60 )); then printf '%dm%02ds' $((s / 60)) $((s % 60))
  else printf '%ds' $s
  fi
}

# Reads a step's log on stdin and redraws a progress bar on every "... i of n" line.
track() {
  local start=$SECONDS line i n pct filled elapsed eta width=30
  while IFS= read -r line; do
    [[ $line =~ '([0-9]+) of ([0-9]+)' ]] || continue
    i=$match[1] n=$match[2]
    pct=$(( i * 100 / n ))
    filled=$(( i * width / n ))
    elapsed=$(( SECONDS - start ))
    eta=$(( elapsed / i * (n - i) ))
    printf '\r\033[K      [%s%s] %3d%%  %d/%d  elapsed %s  ETA %s' \
      "${(l:filled::#:)}" "${(l:width - filled::.:)}" $pct $i $n \
      "$(fmt_time $elapsed)" "$(fmt_time $eta)"
  done
  printf '\r\033[K'
}

# Branch of the fork that is installed into ../lib/fork.
fork_repo=shaheedazaad/zcurve@fix-issue-36

steps=()
[[ output/sim_data.rds -nt gen_data.R ]] || steps+=gen
(( ${fits[(Ie)fork]} )) && steps+=install
steps+=($fits compare)
k=0

# step <label> <log file> <command...>: runs a command, showing a live bar if it reports "i of n".
step() {
  local label=$1 log=$2 t0=$SECONDS
  shift 2
  print "[$((++k))/${#steps}] $label"
  "$@" 2>&1 >/dev/null | tee $log | track || {
    print "      failed, see $log:"
    tail -5 $log | sed 's/^/      /'
    exit 1
  }
  print "      done in $(fmt_time $(( SECONDS - t0 )))"
}

total_start=$SECONDS

[[ output/sim_data.rds -nt gen_data.R ]] ||
  step "Generating datasets" output/log_gen.txt Rscript gen_data.R

(( ${fits[(Ie)fork]} )) && step "Installing fork ($fork_repo)" output/install_fork.log \
  Rscript -e "remotes::install_github('$fork_repo', lib = '../lib/fork', upgrade = 'never')"

(( ${fits[(Ie)old]} )) && step "Fitting old (2.4.7, clustered)" output/log_old.txt \
  Rscript fit.R ../lib/old clustered old $n_datasets
(( ${fits[(Ie)unclustered]} )) && step "Fitting unclustered (2.4.7)" output/log_unclustered.txt \
  Rscript fit.R ../lib/old unclustered unclustered $n_datasets
(( ${fits[(Ie)fork]} )) && step "Fitting fork (clustered)" output/log_fork.txt \
  Rscript fit.R ../lib/fork clustered fork $n_datasets

print "[$((++k))/${#steps}] Comparing results"
Rscript compare.R
print "\nAll steps done in $(fmt_time $(( SECONDS - total_start )))"
