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

resource "random_password" "elasticsearch_password" {
    length           = 16
    special          = false
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

    set {
      name = "service.loadBalancerSourceRanges"
      value = "{${var.vpn_cidr}}"
    }

    timeout = 900

    depends_on = [
        kubernetes_namespace.monitoring_ns,
        helm_release.prometheus_service,
        kubernetes_secret.grafana_credentials,
        kubernetes_config_map.grafana_kubernetes_dashboard
    ]
}

resource "kubernetes_config_map" "grafana_kubernetes_dashboard" {
    metadata {
        labels = {
            "grafana_dashboard" = "1"
        }
        name = "kubernetes-cluster-monitoring-via-prometheus"
        namespace = "monitoring"
    }

    data = {
        "kubernetes-cluster-monitoring-via-prometheus.json" = "${file("../infra/grafana/dashboards/kubernetes-cluster-monitoring-via-prometheus.json")}"
    }

    depends_on = [
        kubernetes_namespace.monitoring_ns,
        helm_release.prometheus_service,
        kubernetes_secret.grafana_credentials
    ]
}

resource "kubernetes_secret" "escluster_credentials" {
    metadata {
        name = "escluster-admin-credentials"
        namespace = "monitoring"
    }

    type = "kubernetes.io/basic-auth"

    data = {
        username = "admin"
        password = random_password.elasticsearch_password.result
        roles = "superuser"
    }

    depends_on = [
        random_password.elasticsearch_password
    ]
}

resource "kubernetes_manifest" "elasticsearch_service" {
    field_manager {
        force_conflicts = true
    }

    manifest = yamldecode(file("../infra/elastic/elasticsearch-cluster.yaml"))

    computed_fields = ["metadata.labels", "metadata.annotations", "spec", "status"]

    depends_on = [
        kubernetes_secret.escluster_credentials,
        kubernetes_namespace.monitoring_ns
    ]
}

resource "kubernetes_manifest" "kibana_service" {
    manifest = {
        apiVersion = "kibana.k8s.elastic.co/v1"
        kind       = "Kibana"

        metadata   = {
            name      = "kibana"
            namespace = "monitoring"
        }

        spec = {
            version          = "8.5.2"
            count            = 1
            elasticsearchRef = {
                name = "escluster"
            }
            http = {
                tls = {
                    selfSignedCertificate = {
                        disabled = true
                    }
                }
                service = {
                    spec = {
                        type = "LoadBalancer"
                        loadBalancerSourceRanges = [
                            var.vpn_cidr
                        ]
                    }
                }
            }
        }
    }

    depends_on = [
        kubernetes_namespace.monitoring_ns,
        kubernetes_manifest.elasticsearch_service
    ]

    timeouts {
        create = "10m"
        update = "10m"
        delete = "10m"
    }
}

resource "kubernetes_manifest" "fluentd_configmap" {
    manifest = yamldecode(file("../infra/fluentd/fluentd-config.yaml"))

    depends_on = [
        random_password.elasticsearch_password,
        kubernetes_manifest.elasticsearch_service,
        kubernetes_namespace.monitoring_ns
    ]
}
 
resource "helm_release" "fluentd_daemnonset" {
    name  = "fluentd"

    repository       = "https://fluent.github.io/helm-charts"
    chart            = "fluentd"
    namespace        = "monitoring"
    version          = "0.3.9"
    create_namespace = false

    values = [
        file("../infra/fluentd/values.yaml")
    ]

    depends_on = [
        random_password.elasticsearch_password,
        kubernetes_manifest.elasticsearch_service,
        kubernetes_namespace.monitoring_ns,
        kubernetes_manifest.fluentd_configmap
    ]
}
