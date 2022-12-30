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

resource "kubernetes_namespace" "ping_pong_ns" {
  metadata {
    labels = {
      app = "ping-pong"
    }

    name = "ping-pong"
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

resource "kubernetes_secret" "argocd_ping_pong_repo" {
    metadata {
        name = "ping-pong-repository"
        namespace = "argocd"
        labels = {
            "argocd.argoproj.io/secret-type" = "repository"
        }
    }

    data = {
        type = "git"
        url = "https://github.com/PanagiotisPtr/ping-pong"
    }

    depends_on = [
        helm_release.argocd_service
    ]
}

resource "kubernetes_manifest" "argocd_pong_app" {
    manifest = yamldecode(file("../infra/argocd/applications/pong.yaml"))

    depends_on = [
        kubernetes_namespace.ping_pong_ns
    ]
}

resource "kubernetes_manifest" "argocd_ping_app" {
    manifest = yamldecode(file("../infra/argocd/applications/ping.yaml"))

    depends_on = [
        kubernetes_namespace.ping_pong_ns
    ]
}
