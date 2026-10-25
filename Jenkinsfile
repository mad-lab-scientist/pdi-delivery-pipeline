// PDI release pipeline (docs/11-pipeline-showcase.md). Every stage calls ci/run.mjs, the same runner used on a
// workstation, so a Jenkins run and a local run produce the same kind of record. Nothing here deploys: the last
// stage asks for approval, and the Owner deploys the archived upload folder with the scripts' own preflight and
// automatic rollback.
//
// Agent requirements (label pdi-linux): Linux, Node 24.x on PATH (node:sqlite), npm, internet access for npm ci and
// npm audit, and Docker for the deploy rehearsal. Run the agent on a VM, not inside the Jenkins container: the
// rehearsal mounts the workspace into a container, which needs the workspace path to exist on the Docker host.
pipeline {
  agent { label 'pdi-linux' }
  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '30', artifactNumToKeepStr: '10'))
    timeout(time: 60, unit: 'MINUTES')
  }
  environment {
    RUN_ID = "jenkins-${env.BUILD_NUMBER}"
    WORK   = "${env.WORKSPACE}/ci/out/work"
  }
  stages {
    stage('Facts & claims')        { steps { sh 'node ci/run.mjs facts --id "$RUN_ID" --commit "$GIT_COMMIT" --work "$WORK"' } }
    stage('Build from source')     { steps { sh 'node ci/run.mjs build --id "$RUN_ID" --work "$WORK"' } }
    stage('Release integrity')     { steps { sh 'node ci/run.mjs static --id "$RUN_ID" --work "$WORK"' } }
    stage('Live application test') { steps { sh 'node ci/run.mjs smoke --id "$RUN_ID" --work "$WORK"' } }
    stage('Secret scan')           { steps { sh 'node ci/run.mjs secrets --id "$RUN_ID" --work "$WORK"' } }
    stage('Dependencies & SBOM')   { steps { sh 'node ci/run.mjs deps --id "$RUN_ID" --work "$WORK"' } }
    stage('Deploy rehearsal')      { steps { sh 'node ci/run.mjs rehearsal --id "$RUN_ID" --work "$WORK"' } }
    stage('Approve release') {
      when { branch 'main' }
      options { timeout(time: 3, unit: 'DAYS') }
      steps { input message: 'All stages passed. Approve this release candidate for the Owner to deploy?', ok: 'Approve' }
    }
  }
  post {
    always {
      sh 'node ci/run.mjs summarize || true'
      archiveArtifacts artifacts: 'ci/out/**, portal/build/upload/**', allowEmptyArchive: true, fingerprint: true
    }
  }
}
