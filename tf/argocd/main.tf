variable "kube_context" {
    type = string
}

variable "vpn_cidr" {
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

resource "kubernetes_namespace" "argocd_ns" {
    metadata {
        labels = {
            app = "argocd"
        }

        name = "argocd"
    }
}

resource "helm_release" "argocd_service" {
    name  = "argocd"

    repository       = "https://argoproj.github.io/argo-helm"
    chart            = "argo-cd"
    namespace        = "argocd"
    version          = "5.16.9"
    create_namespace = false

    timeout = 900

    values = [
        file("../../infra/argocd/values.yaml")
    ]

    set {
      name = "server.service.loadBalancerSourceRanges"
      value = "{${var.vpn_cidr}}"
    }

    depends_on = [
        kubernetes_namespace.argocd_ns
    ]
}
