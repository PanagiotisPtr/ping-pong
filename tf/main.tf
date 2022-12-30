variable "kube_context" {
    type = string
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kube_context
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

resource "helm_release" "argocd_service" {
  name  = "argocd"

  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  version          = "5.16.9"
  create_namespace = true

  values = [
    file("../infra/argocd/values.yaml")
  ]
}
