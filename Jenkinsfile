pipeline {
    agent { label 'master' }

    stages {
        stage("Docker Hub") {
            when {
                anyOf {
                    branch 'master'
                    branch 'issue-21-22'
                }
                changeset "tests/nimbusapp-test.dockerapp"
            }
            steps {
                script {
                    // Assumptions:
                    //  - Github and Docker Hub organizations match
                    //  - Job is in root folder of this instance
                    dockerNamespace = env.JOB_NAME.split('/')[0]
                }
                withCredentials([usernamePassword(credentialsId: '5d4e53f3-62ed-471f-85da-83075e934eaf', passwordVariable: 'HUB_PASS', usernameVariable: 'HUB_USER')]) {
                    sh 'docker login --username $HUB_USER --password-stdin <<< $HUB_PASS'
                }
                sh 'docker-app validate tests/nimbusapp-test.dockerapp'
                sh 'docker-app push tests/nimbusapp-test.dockerapp --namespace "${dockerNamespace}"'
            }
        }

        stage("Framework Setup") {
            steps {
                dir("bats-core") {
                    git(url: "https://github.com/bats-core/bats-core")
                }
            }
        } // framework setup

        stage("Test") {
            steps {
                sh '''
                        export PATH="$PWD/bats-core/libexec/bats-core:$PATH"
                        bats tests --tap | tee bats-tap.log
                    '''
            }
            post {
                always {
                    step([$class: "TapPublisher", testResults: "bats-tap.log"])
                }
            }
        } // test

        stage("Archive") {
            steps {
                script {
                    releaseDate = new Date().format("YYYY-MM-dd")
                }
                sh """
                    sed -i -e 's#\\(readonly NIMBUS_RELEASE_VERSION=\\).*#\\1"${env.BRANCH_NAME}"#' \\
                           -e 's#\\(readonly NIMBUS_RELEASE_DATE=\\).*#\\1"${releaseDate}"#' nimbusapp
                """

                archiveArtifacts artifacts: 'nimbusapp'
            }
        }
    }
} // pipeline

