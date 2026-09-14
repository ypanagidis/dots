# Kubernetes — use the local minikube cluster by default.
# The remote k8s-arc config remains available explicitly via KUBECONFIG.

[[ -d "$HOME/.local/bin" ]] && path=("$HOME/.local/bin" $path)
typeset -U path PATH
export PATH

export KUBECONFIG="$HOME/.kube/minikube.yaml"
[[ -f "$HOME/.talos/k8s-arc.yaml" ]] && export TALOSCONFIG="$HOME/.talos/k8s-arc.yaml"

alias k=kubectl
alias t=talosctl
