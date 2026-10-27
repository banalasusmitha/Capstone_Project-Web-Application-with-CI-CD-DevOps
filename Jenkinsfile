// =============================================================================
// Job: shopnow/3-app-cicd                                            (Sprint 4)
//
// Code push -> test -> build 3 images -> test the images -> push to ECR ->
// deploy to EKS -> post-deployment smoke tests -> notify on failure.
//
// Triggers: GitHub push webhook (and SCM polling as a fallback) on this repo
//           AND on the application repo, because both are checked out here.
// App source:  https://github.com/banalasusmitha/shopNow   (frontend, admin, backend)
// Manifests:   kubernetes-Avinash/  in this repo
// AWS access:  the Jenkins server's IAM instance profile - no access keys.
// =============================================================================

pipeline {
    agent any

    triggers {
        githubPush()
        pollSCM('H/5 * * * *')   // fallback if the webhook cannot reach Jenkins
    }

    parameters {
        string(name: 'APP_BRANCH', defaultValue: 'main', description: 'Branch of the shopNow application repo to build.')
        booleanParam(name: 'SKIP_DEPLOY', defaultValue: false, description: 'Build, test and push only - do not touch the cluster.')
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '30'))
        timeout(time: 60, unit: 'MINUTES')
    }

    environment {
        AWS_DEFAULT_REGION = 'ap-south-1'
        AWS_REGION         = 'ap-south-1'
        EXPECTED_ACCOUNT   = '095355901688'
        CLUSTER_NAME       = 'shopnow-eks-dev'
        APP_REPO           = 'https://github.com/banalasusmitha/shopNow.git'
        USER_NAME          = 'avinash'            // baked into the React bundles; must match the ingress paths
        ECR_NAMESPACE      = 'avinash-shopnow'
        K8S_NAMESPACE      = 'default'
        MANIFEST_DIR       = 'kubernetes-Avinash'
        IMAGE_TAG          = "${BUILD_NUMBER}"    // unique per build, so Kubernetes always rolls out
        KUBECONFIG         = "${WORKSPACE}/.kube/config"
        DOCKER_BUILDKIT    = '1'
    }

    stages {

        // ---------------------------------------------------------------------
        stage('Checkout') {
            steps {
                checkout scm                                  // pipeline, manifests, test scripts
                dir('app') {
                    git url: env.APP_REPO, branch: params.APP_BRANCH   // application source
                }
                script {
                    env.APP_COMMIT = sh(returnStdout: true, script: 'git -C app rev-parse --short HEAD').trim()
                    currentBuild.description = "app@${env.APP_COMMIT} -> tag ${env.IMAGE_TAG}"
                }
                sh 'git -C app log -1 --format="App commit %h by %an: %s"'
            }
        }

        // ---------------------------------------------------------------------
        stage('Preflight') {
            steps {
                script {
                    sh '''
                        set -e
                        docker --version; aws --version; kubectl version --client | head -1; helm version --short
                        ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
                        if [ "$ACCOUNT" != "$EXPECTED_ACCOUNT" ]; then
                            echo "ERROR: running in account $ACCOUNT, expected $EXPECTED_ACCOUNT"; exit 1
                        fi
                    '''
                    env.ECR_REGISTRY = "${env.EXPECTED_ACCOUNT}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
                    env.IMAGE_PREFIX = "${env.ECR_REGISTRY}/${env.ECR_NAMESPACE}"
                }
            }
        }

        // ---------------------------------------------------------------------
        stage('Static checks & unit tests') {
            parallel {
                stage('Backend') {
                    steps {
                        // Runs inside node:18 (same as the image) so the server needs no Node install.
                        sh '''
                            docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e npm_config_cache=/tmp/.npm \
                              -v "$WORKSPACE/app/backend:/src" -w /src node:18-alpine sh -c '
                                set -e
                                npm ci --no-audit --no-fund
                                node --check server.js
                                echo "backend: dependencies install and server.js parses"
                                npm audit --omit=dev --audit-level=critical || echo "WARN: npm audit found critical issues"
                              '
                        '''
                    }
                }
                stage('Dockerfile lint') {
                    steps {
                        sh '''
                            for svc in frontend admin backend; do
                              echo "--- $svc/Dockerfile"
                              docker run --rm -i hadolint/hadolint:latest-alpine hadolint --no-fail - < "app/$svc/Dockerfile" || true
                            done
                        '''
                    }
                }
                stage('Manifest check') {
                    steps {
                        sh '''
                            set -e
                            ls "$MANIFEST_DIR"/*.y*ml
                            grep -q "kind: Deployment" "$MANIFEST_DIR"/*.y*ml
                            for d in frontend admin backend; do
                              grep -q "name: ${d}-deployment" "$MANIFEST_DIR"/*.y*ml \
                                || { echo "ERROR: ${d}-deployment missing in $MANIFEST_DIR"; exit 1; }
                            done
                            grep -q "readinessProbe" "$MANIFEST_DIR"/*.y*ml || echo "WARN: no readinessProbe in manifests (Sprint 4 requires health checks)"
                            grep -q "HorizontalPodAutoscaler" "$MANIFEST_DIR"/*.y*ml || echo "WARN: no HPA in manifests (Sprint 4 requires auto-scaling)"
                            grep -q "kind: Ingress" "$MANIFEST_DIR"/*.y*ml || echo "WARN: no Ingress in manifests - app will not be reachable from outside"
                        '''
                    }
                }
            }
        }

        // ---------------------------------------------------------------------
        stage('Build images') {
            // Sequential on purpose: two React builds at once can run a 4 GiB server out of memory.
            steps {
                sh '''
                    set -e
                    for svc in backend frontend admin; do
                      echo "=== building $svc"
                      ARGS=""
                      [ "$svc" != "backend" ] && ARGS="--build-arg USER_NAME=$USER_NAME"
                      docker build $ARGS \
                        --label "org.opencontainers.image.revision=$APP_COMMIT" \
                        --label "org.opencontainers.image.source=$APP_REPO" \
                        -t "$IMAGE_PREFIX/$svc:$IMAGE_TAG" \
                        -t "$IMAGE_PREFIX/$svc:latest" \
                        "app/$svc"
                    done
                    docker images "$IMAGE_PREFIX/*" --format "{{.Repository}}:{{.Tag}}  {{.Size}}"
                '''
            }
        }

        // ---------------------------------------------------------------------
        stage('Container tests') {
            steps {
                sh 'bash jenkins-Kaushik/tests/container-test.sh "$IMAGE_PREFIX" "$IMAGE_TAG" "$USER_NAME"'
            }
        }

        // ---------------------------------------------------------------------
        stage('Push to ECR') {
            steps {
                sh '''
                    set -e
                    aws ecr get-login-password | docker login --username AWS --password-stdin "$ECR_REGISTRY"
                    for svc in backend frontend admin; do
                      docker push "$IMAGE_PREFIX/$svc:$IMAGE_TAG"
                      docker push "$IMAGE_PREFIX/$svc:latest"
                    done
                    docker logout "$ECR_REGISTRY"
                '''
            }
        }

        // ---------------------------------------------------------------------
        stage('Deploy to EKS') {
            when { expression { !params.SKIP_DEPLOY } }
            steps {
                sh '''
                    set -e
                    mkdir -p "$(dirname "$KUBECONFIG")"
                    aws eks update-kubeconfig --name "$CLUSTER_NAME" --kubeconfig "$KUBECONFIG"
                    kubectl get nodes

                    # Cluster prerequisites (idempotent)
                    kubectl apply -f terraform-Sushmita/extras/storageclass-gp3.yaml
                    if grep -q "kind: Ingress" "$MANIFEST_DIR"/*.y*ml; then
                      helm upgrade --install ingress-nginx ingress-nginx \
                        --repo https://kubernetes.github.io/ingress-nginx \
                        --namespace ingress-nginx --create-namespace --wait --timeout 10m
                    fi

                    # Render the manifests with this build's image tag. Whatever tag the
                    # files contain (v1, latest...), every ECR image of ours gets IMAGE_TAG.
                    rm -rf build/k8s && mkdir -p build/k8s
                    cp "$MANIFEST_DIR"/*.y*ml build/k8s/
                    sed -i -E "s#(image:[[:space:]]*)[^[:space:]]*/$ECR_NAMESPACE/(frontend|admin|backend)(:[^[:space:]]*)?#\\1$IMAGE_PREFIX/\\2:$IMAGE_TAG#" build/k8s/*.y*ml
                    echo "--- images being deployed"
                    grep -h "image:" build/k8s/*.y*ml

                    kubectl apply --dry-run=server -n "$K8S_NAMESPACE" -f build/k8s/
                    kubectl apply -n "$K8S_NAMESPACE" -f build/k8s/
                '''
                script {
                    def workloads = sh(returnStdout: true,
                        script: 'kubectl get -n "$K8S_NAMESPACE" -f build/k8s/ -o name | grep -E "^(deployment|statefulset)" || true').trim()
                    for (w in workloads.split('\n')) {
                        if (!w) { continue }
                        def rc = sh(returnStatus: true, script: "kubectl rollout status ${w} -n \"\$K8S_NAMESPACE\" --timeout=5m")
                        if (rc != 0) {
                            sh """
                                echo '--- diagnostics for ${w}'
                                kubectl describe ${w} -n "\$K8S_NAMESPACE" | tail -40
                                kubectl get pods -n "\$K8S_NAMESPACE" -o wide
                                kubectl get events -n "\$K8S_NAMESPACE" --sort-by=.lastTimestamp | tail -20
                            """
                            if (w.startsWith('deployment')) {
                                sh "kubectl rollout undo ${w} -n \"\$K8S_NAMESPACE\" || true"
                                error("Rollout of ${w} failed - rolled back to the previous version.")
                            }
                            error("Rollout of ${w} failed.")
                        }
                    }
                }
                sh 'kubectl get deploy,statefulset,svc,hpa,ingress,pvc -n "$K8S_NAMESPACE" -o wide'
            }
        }

        // ---------------------------------------------------------------------
        stage('Smoke tests') {
            when { expression { !params.SKIP_DEPLOY } }
            steps {
                script {
                    def rc = sh(returnStatus: true, script: '''
                        mkdir -p build
                        bash jenkins-Kaushik/tests/smoke-test.sh "$K8S_NAMESPACE" "$USER_NAME" > build/smoke-test.log 2>&1
                        rc=$?; cat build/smoke-test.log; exit $rc
                    ''')
                    def appUrl = sh(returnStdout: true,
                                    script: "sed -n 's/^APP_URL=//p' build/smoke-test.log | head -1").trim()
                    if (appUrl) {
                        env.APP_URL = appUrl
                        currentBuild.description += " | ${appUrl}"
                    }
                    if (rc == 3) {
                        unstable('App works inside the cluster but is not reachable through the ingress.')
                    } else if (rc != 0) {
                        error('Post-deployment smoke tests failed.')
                    }
                }
            }
        }
    }

    post {
        success {
            echo "Deployed ${env.IMAGE_TAG} (app@${env.APP_COMMIT}). ${env.APP_URL ? 'App: ' + env.APP_URL : ''}"
        }
        unstable {
            script { notify('UNSTABLE') }
        }
        failure {
            script { notify('FAILED') }
        }
        always {
            archiveArtifacts artifacts: 'build/**', allowEmptyArchive: true
            // Keep the server's disk from filling up with old image layers.
            sh 'docker image prune -f --filter "until=72h" >/dev/null || true'
        }
    }
}

// Email if NOTIFY_EMAIL is set as a global env var (Manage Jenkins > System >
// Global properties) and SMTP is configured. Prometheus/Alertmanager also
// alert on failed builds via the Jenkins /prometheus endpoint (Sprint 5).
def notify(String status) {
    def to = env.NOTIFY_EMAIL
    if (!to) {
        echo "NOTIFY_EMAIL not set - skipping email notification (${status})."
        return
    }
    try {
        mail to: to,
             subject: "${status}: ${env.JOB_NAME} #${env.BUILD_NUMBER} (app@${env.APP_COMMIT ?: '?'})",
             body: "ShopNow deployment ${status}.\n\nImage tag: ${env.IMAGE_TAG}\nConsole: ${env.BUILD_URL}console\n"
    } catch (err) {
        echo "Could not send email: ${err}"
    }
}
