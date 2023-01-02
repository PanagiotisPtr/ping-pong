variable "kube_context" {
    type = string
}

provider "kubernetes" {
    config_path    = "~/.kube/config"
    config_context = var.kube_context
}

provider "kubectl" {
    load_config_file       = true
    config_path            = "~/.kube/config"
    config_context_cluster = var.kube_context 
}

data "kubectl_file_documents" "eck_crds" {
    content = file("../../infra/elastic/crds.yaml")
}

data "kubectl_file_documents" "eck_operator" {
    content = file("../../infra/elastic/operator.yaml")
}

locals {
    crds_yaml_file = [
        for v in data.kubectl_file_documents.eck_crds.documents : {
            data : yamldecode(v)
            content : v
        }
    ]

    operator_yaml_file = [
        for v in data.kubectl_file_documents.eck_operator.documents : {
            data : yamldecode(v)
            content : v
        }
    ]
}

resource "kubernetes_manifest" "eck_crds" {
    for_each = {
        for v in local.crds_yaml_file : lower(join("/", compact([
            v.data.apiVersion,
            v.data.kind,
            lookup(lookup(v.data, "metadata", {}), "namespace", ""),
            lookup(lookup(v.data, "metadata", {}), "name", "")
        ]))) => v.content
    }

    manifest = yamldecode(each.value)
}

resource "kubernetes_manifest" "eck_operator" {
    for_each = {
        for v in local.operator_yaml_file : lower(join("/", compact([
            v.data.apiVersion,
            v.data.kind,
            lookup(lookup(v.data, "metadata", {}), "namespace", ""),
            lookup(lookup(v.data, "metadata", {}), "name", "")
        ]))) => v.content
    }

    manifest = yamldecode(each.value)
    
    depends_on = [
        kubernetes_manifest.eck_crds
    ]
}
