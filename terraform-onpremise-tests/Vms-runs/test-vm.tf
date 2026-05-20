###############################################################################
# test-vm.tf — Provisionnement de VMs VMware Workstation via Terraform
#
# Ce fichier orchestre la création de VMs à partir d'un template, en s'appuyant
# sur le provider `elsudano/vmworkstation` (qui dialogue avec l'API REST `vmrest`
# fournie par VMware Workstation Pro).
#
# La liste des VMs à provisionner est définie dans `servers.yaml`. Pour ajouter
# ou retirer un serveur, modifie ce fichier YAML puis exécute :
#     terraform apply -parallelism=1
#
# IMPORTANT : `vmrest` ne supporte pas les requêtes parallèles, il faut donc
# toujours passer `-parallelism=1` à terraform.
#
# Plusieurs `null_resource` sont utilisés pour contourner des bugs connus du
# provider (description non modifiable, race condition au démarrage, VMs
# invisibles dans la GUI, champ annotation manquant dans le .vmx).
###############################################################################

terraform {
  # Version minimale du provider et son origine.
  required_providers {
    vmworkstation = {
      source = "elsudano/vmworkstation"
    }
  }

  # On déplace le state local dans un sous-dossier `.state/` pour garder la
  # racine du module propre (sinon terraform.tfstate* pollue le répertoire).
  backend "local" {
    path = ".state/terraform.tfstate"
  }
}

###############################################################################
# Connexion au service vmrest (API REST locale de VMware Workstation Pro).
# - vmrest doit être démarré avant `terraform apply` :
#       & "C:\Program Files (x86)\VMware\VMware Workstation\vmrest.exe"
# - Les credentials sont définis une fois pour toutes via `vmrest.exe -C`.
# - Par défaut vmrest écoute en HTTP (https = false).
###############################################################################
provider "vmworkstation" {
  endpoint = "http://localhost:8697/api"
  username = "ubuntu"
  password = "Root@1234"
  https    = false
  debug    = "NONE" # NONE, INFO, ERROR, DEBUG
}

###############################################################################
# Variables locales (constantes du module).
# - vm_base_path : dossier racine où seront stockés les .vmx des VMs créées.
# - vmware_exe   : chemin vers vmware.exe (utilisé pour enregistrer la VM
#   dans la bibliothèque GUI après sa création par l'API).
# - vmrest_*     : credentials/URL de l'API vmrest, réutilisés dans les
#   `local-exec` qui pilotent l'état (on/off) des VMs.
# - inventory    : contenu du fichier `servers.yaml` parsé en map.
# - servers      : raccourci vers la sous-clé `servers:` de l'inventaire.
###############################################################################
locals {
  vm_base_path = "C:\\Users\\mbula\\OneDrive\\Documents\\Virtual Machines"
  vmware_exe   = "C:\\Program Files (x86)\\VMware\\VMware Workstation\\vmware.exe"
  vmrest_url   = "http://localhost:8697/api"
  vmrest_user  = "ubuntu"
  vmrest_pass  = "Root@1234"

  inventory = yamldecode(file("${path.module}/servers.yaml"))
  servers   = local.inventory.servers
}

###############################################################################
# Création des VMs à partir du template défini dans servers.yaml.
#
# `for_each` itère sur la map `servers` ; la clé YAML (ex: "test02") devient
# le nom (`denomination`) de la VM et son chemin (.vmx).
#
# Workaround important : on force `state = "off"` à la création. Le provider
# a une race condition lorsqu'il tente de démarrer la VM immédiatement après
# le clone (StatusCode 500). On démarre la VM séparément via `power_state`.
#
# `lifecycle.ignore_changes` :
# - description  / denomination : non modifiables après création (limitation
#   documentée du provider — l'API REST échoue).
# - state        : géré par `null_resource.power_state` ci-dessous.
###############################################################################
resource "vmworkstation_virtual_machine" "vm" {
  for_each = local.servers

  sourceid     = each.value.template_id                                          # ID vmrest de la VM template
  denomination = each.key                                                        # nom de la VM
  description  = each.value.description                                          # description (lecture seule après create)
  path         = "${local.vm_base_path}\\${each.key}\\${each.key}.vmx"           # emplacement du .vmx du clone
  processors   = each.value.processors                                           # nombre de vCPU
  memory       = each.value.memory                                               # RAM en Mo (multiple de 4)
  state        = "off"                                                           # toujours off à la création

  lifecycle {
    ignore_changes = [description, denomination, state]
  }
}

###############################################################################
# Workaround : ajoute le champ `annotation` dans le fichier .vmx généré.
#
# Le provider lit la description depuis `annotation` au prochain refresh, mais
# il ne l'écrit pas dans le .vmx lors du clone. Sans cette ligne, terraform
# affiche une erreur "The VM Description field is empty" au refresh suivant.
#
# On lit le .vmx en UTF-8, on ajoute `annotation = "..."` s'il n'y est pas,
# et on réécrit le fichier en UTF-8 sans BOM.
###############################################################################
resource "null_resource" "fix_annotation" {
  for_each = local.servers

  triggers = {
    vm_id = vmworkstation_virtual_machine.vm[each.key].id
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command     = <<-EOT
      $vmx = '${vmworkstation_virtual_machine.vm[each.key].path}'
      $bytes = [System.IO.File]::ReadAllBytes($vmx)
      $text = [System.Text.Encoding]::UTF8.GetString($bytes)
      if ($text -notmatch 'annotation\s*=') {
        $text = $text.TrimEnd() + "`r`nannotation = `"${each.value.description}`"`r`n"
        [System.IO.File]::WriteAllText($vmx, $text, [System.Text.UTF8Encoding]::new($false))
      }
    EOT
  }
}

###############################################################################
# Workaround : enregistre la VM dans la bibliothèque GUI de VMware Workstation.
#
# Les VMs créées via l'API vmrest n'apparaissent PAS automatiquement dans la
# liste de la GUI. On force leur enregistrement en ouvrant le .vmx avec
# `vmware.exe -t <path>`. VMware mémorise alors la VM dans sa bibliothèque
# et elle restera visible à chaque ouverture de l'application.
#
# `depends_on` : on attend que l'annotation soit fixée avant d'ouvrir la VM,
# sinon VMware peut écraser le .vmx au moment de la lecture.
###############################################################################
resource "null_resource" "register_in_gui" {
  for_each = local.servers

  triggers = {
    vm_id = vmworkstation_virtual_machine.vm[each.key].id
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command     = "& '${local.vmware_exe}' -t '${vmworkstation_virtual_machine.vm[each.key].path}'"
  }

  depends_on = [null_resource.fix_annotation]
}

###############################################################################
# Pilote on/off des VMs via l'API REST de vmrest.
#
# Le champ `state` du provider étant ignoré (cf. lifecycle plus haut), on
# pilote l'alimentation séparément. Ce `null_resource` est re-créé à chaque
# changement de la valeur `state` dans servers.yaml (grâce au trigger), ce
# qui ré-exécute le PUT /vms/{id}/power.
#
# Le `try/catch` PowerShell évite l'échec si la VM est déjà dans l'état cible
# (ex: déjà off quand on demande off).
###############################################################################
resource "null_resource" "power_state" {
  for_each = local.servers

  triggers = {
    vm_id = vmworkstation_virtual_machine.vm[each.key].id
    state = each.value.state # déclenche un re-run quand on/off change dans le YAML
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command     = <<-EOT
      $pair = '${local.vmrest_user}:${local.vmrest_pass}'
      $b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
      $headers = @{
        Authorization  = "Basic $b64"
        Accept         = 'application/vnd.vmware.vmw.rest-v1+json'
        'Content-Type' = 'application/vnd.vmware.vmw.rest-v1+json'
      }
      $body = '${each.value.state}'
      try {
        Invoke-RestMethod -Method Put -Uri '${local.vmrest_url}/vms/${vmworkstation_virtual_machine.vm[each.key].id}/power' -Headers $headers -Body $body
      } catch {
        Write-Host "Power command may have failed (already in target state?): $_"
      }
    EOT
  }

  depends_on = [null_resource.register_in_gui]
}

###############################################################################
# Sortie : récapitulatif des VMs provisionnées (id, path, IP, specs, state).
# Affichée à la fin de chaque `terraform apply` et accessible via
# `terraform output vms`.
###############################################################################
output "vms" {
  description = "Récapitulatif des VMs provisionnées"
  value = {
    for name, vm in vmworkstation_virtual_machine.vm : name => {
      id          = vm.id
      path        = vm.path
      ip          = vm.ip
      processors  = vm.processors
      memory      = vm.memory
      power_state = local.servers[name].state
    }
  }
}
