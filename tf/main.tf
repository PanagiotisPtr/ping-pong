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

resource "kubernetes_namespace" "monitoring_ns" {
    metadata {
        labels = {
            app = "monitoring"
        }

        name = "monitoring"
    }
}

resource "random_password" "grafana_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "kubernetes_secret" "grafana_credentials" {
    metadata {
        name = "grafana-credentials"
        namespace = "monitoring"
    }

    data = {
        username = "admin"
        password = random_password.grafana_password.result
    }

    depends_on = [
        random_password.grafana_password
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

resource "helm_release" "prometheus_service" {
    name  = "prometheus"

    repository       = "https://prometheus-community.github.io/helm-charts"
    chart            = "prometheus"
    namespace        = "monitoring"
    version          = "19.2.2"
    create_namespace = false

    values = [
        file("../infra/prometheus/values.yaml")
    ]

    depends_on = [
        kubernetes_namespace.monitoring_ns
    ]
}

resource "helm_release" "grafana_service" {
    name  = "grafana"

    repository       = "https://grafana.github.io/helm-charts"
    chart            = "grafana"
    namespace        = "monitoring"
    version          = "6.48.2"
    create_namespace = false

    values = [
        file("../infra/grafana/values.yaml")
    ]

    depends_on = [
        kubernetes_namespace.monitoring_ns,
        helm_release.prometheus_service,
        kubernetes_secret.grafana_credentials
    ]
}
