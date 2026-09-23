terraform {
  cloud {
    organization = "vvr-org"
    workspaces {
      name = "project2-acr-appservice"
    }
  }
}