# gitops-example

A reference repository for the **Harness GitOps multi-repo, multi-cluster deployment** training video.

It demonstrates:
- A real (but simple) application with a Dockerfile
- Kustomize-based manifests with `base` + per-environment overlays
- An Argo CD **ApplicationSet** that fans out to a dev cluster and a production cluster from a single template
- A Harness pipeline that builds, deploys to dev, gates on human approval, then promotes to prod
- A promotion script for ad-hoc or demo use

---

## Repository layout

```
gitops-example/
├── app/                        # ① Application source  (mirrors an "app-repo")
│   ├── src/index.js
│   ├── package.json
│   └── Dockerfile
│
├── gitops/                     # ② GitOps manifests    (mirrors a "gitops-repo")
│   ├── base/                   #    Shared k8s objects (Deployment, Service, Namespace)
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── namespace.yaml
│   │   └── kustomization.yaml
│   ├── overlays/
│   │   ├── dev/                #    Dev-specific overrides (1 replica, dev env vars)
│   │   │   ├── kustomization.yaml   ← image tag updated by CI
│   │   │   └── env-patch.yaml
│   │   └── production/         #    Prod-specific overrides (3 replicas, prod env vars)
│   │       ├── kustomization.yaml   ← image tag updated by promote step
│   │       └── env-patch.yaml
│   └── applicationsets/
│       └── demo-app.yaml       #    Argo CD ApplicationSet (multi-cluster fan-out)
│
├── .harness/
│   └── pipeline.yaml           # ③ Harness pipeline (CI → dev → approval → prod)
│
└── scripts/
    └── promote.sh              #    Ad-hoc promotion helper
```

---

## Multi-repo pattern

In production GitOps setups the application code and the deployment manifests live in **separate repositories** so they evolve independently and have separate access controls.

This repo uses `app/` and `gitops/` directories to mirror that separation while keeping everything in one place for the training demo. When you adapt this for real use:

| Directory | Becomes |
|-----------|---------|
| `app/` | `github.com/your-org/gitops-demo` (app repo) |
| `gitops/` | `github.com/your-org/gitops-demo-config` (config / gitops repo) |

The Harness pipeline's **UpdateReleaseRepo** step commits the new image tag into the config repo — it never touches application source.

---

## Multi-cluster pattern

The [Argo CD ApplicationSet](gitops/applicationsets/demo-app.yaml) uses a **List generator** to create one `Application` resource per target cluster.

```
ApplicationSet (management cluster)
  ├── Application: gitops-demo-dev        → dev-cluster   (gitops/overlays/dev)
  └── Application: gitops-demo-production → prod-cluster  (gitops/overlays/production)
```

Each cluster runs a **Harness GitOps Agent** (lightweight Argo CD instance) that watches this repo and reconciles the live state to match the declared manifests.

To add a third cluster (e.g. staging), add one element to the `generators.list.elements` array in `demo-app.yaml` and create a matching overlay under `gitops/overlays/staging/`.

---

## Promotion workflow

```
  Developer push
       │
       ▼
  ┌──────────┐    builds image          ┌─────────────────────────────┐
  │  CI Stage│──────────────────────────▶  docker.io/your-org/gitops- │
  │(Harness) │    tags: <sequenceId>    │  demo:<sequenceId>          │
  └────┬─────┘                          └─────────────────────────────┘
       │ UpdateReleaseRepo
       │ patches gitops/overlays/dev/kustomization.yaml → newTag: <sequenceId>
       ▼
  ┌──────────┐
  │ Deploy   │  Argo CD syncs dev-cluster  →  gitops-demo-dev namespace
  │   Dev    │
  └────┬─────┘
       │
       ▼
  ┌──────────┐
  │ Approval │  Human reviews dev, clicks Approve
  │   Gate   │
  └────┬─────┘
       │ UpdateReleaseRepo
       │ patches gitops/overlays/production/kustomization.yaml → newTag: <sequenceId>
       ▼
  ┌──────────┐
  │ Deploy   │  Argo CD syncs prod-cluster  →  gitops-demo-prod namespace
  │  Prod    │
  └──────────┘
```

---

## Setup checklist

### 1. Prerequisites

| Tool | Version |
|------|---------|
| kubectl | ≥ 1.28 |
| kustomize | ≥ 5.0 |
| Harness account | any edition with GitOps feature enabled |
| Two Kubernetes clusters | dev + prod (can be minikube/kind for demos) |

### 2. Install Harness GitOps Agents

Install one agent per cluster.  In Harness: **GitOps → Agents → New Agent**.

Follow the wizard — it generates a `kubectl apply` command that deploys the agent into the `harness-gitops` namespace on each cluster.

### 3. Register clusters and repositories in Harness

- **Clusters**: GitOps → Clusters → New Cluster (point at each agent)
- **Repositories**: GitOps → Repositories → New Repository (point at this repo)

### 4. Apply the ApplicationSet

```bash
# From the management cluster (where Argo CD / Harness GitOps Agent runs)
# Update the repoURL and server fields in the file first
kubectl apply -f gitops/applicationsets/demo-app.yaml -n argocd
```

### 5. Import the Harness pipeline

1. Open Harness → Pipelines → Import from Git
2. Select the repo and path `.harness/pipeline.yaml`
3. Replace every `REPLACE_*` placeholder:
   - `REPLACE_GITHUB_CONNECTOR` — your GitHub connector ID
   - `REPLACE_DOCKER_CONNECTOR` — your container registry connector ID
   - `REPLACE_K8S_BUILD_CONNECTOR` — Kubernetes connector for CI build infra
   - `REPLACE_DEV_CLUSTER_IDENTIFIER` — cluster ID registered in step 3
   - `REPLACE_PROD_CLUSTER_IDENTIFIER` — cluster ID registered in step 3
   - `REPLACE_APPROVER_USER_GROUP` — Harness user group for the approval gate

### 6. Run the pipeline

Trigger a run from Harness UI or push a commit to `main`.  
Watch the pipeline progress through Build → Deploy Dev → Approval → Deploy Prod.

---

## Ad-hoc promotion

To promote a specific image tag outside of the pipeline (useful for demos):

```bash
./scripts/promote.sh 42
```

This patches `gitops/overlays/production/kustomization.yaml`, commits, and pushes.  
Argo CD detects the change and syncs the production cluster within seconds.

---

## Verifying deployments

```bash
# Check dev
kubectl get pods -n gitops-demo-dev
kubectl port-forward svc/gitops-demo 8080:80 -n gitops-demo-dev
curl http://localhost:8080/

# Check prod
kubectl get pods -n gitops-demo-prod --context prod-cluster
kubectl port-forward svc/gitops-demo 8081:80 -n gitops-demo-prod --context prod-cluster
curl http://localhost:8081/
```

Expected response:
```json
{
  "app": "gitops-demo",
  "version": "42",
  "environment": "production",
  "message": "Hello from Harness GitOps! Running in production."
}
```
