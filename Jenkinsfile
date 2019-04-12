pipeline {
    agent any

    parameters {
        booleanParam(
                name: 'DOCKERAPP_FORCE_PUSH',
                defaultValue: false,
                description: 'Override conditions and push dockerapp'
        )

        string(
                name: 'DOCKERAPP_TAG',
                defaultValue: '',
                description: 'Override the tag in nimbusapp-test.dockerapp. Requires DOCKERAPP_FORCE_PUSH'
        )
    }

    stages {
        stage('Docker Hub') {
            when {
                anyOf {
                    allOf {
                        anyOf {
                            branch 'master'
                            branch 'issue-21-22'
                        }
                        changeset 'tests/nimbusapp-test.dockerapp'
                    }
                    expression { params.FORCE_PUSH_DOCKERAPP }
                }
            }
            steps {
                script {
                    // Assumptions:
                    //  - Github and Docker Hub organizations match
                    //  - Job is in root folder of this instance
                    pushOpts = $/--namespace "${env.JOB_NAME.split('/')[0]}"/$

                    if (params.FORCE_PUSH_DOCKERAPP && params.DOCKERAPP_TAG) {
                        pushOpts += $/ --tag "${params.DOCKERAPP_TAG}"/$
                    }
                }

                withCredentials([usernamePassword(credentialsId: '5d4e53f3-62ed-471f-85da-83075e934eaf', passwordVariable: 'HUB_PASS', usernameVariable: 'HUB_USER')]) {
                    sh 'docker login --username "$HUB_USER" --password-stdin <<< $HUB_PASS'
                }

                sh 'docker-app validate tests/nimbusapp-test.dockerapp'
                sh "docker-app push tests/nimbusapp-test.dockerapp ${pushOpts}"
            }
        } // Docker Hub

        stage('Build') {
            steps {
                script {
                    releaseDate = new Date().format('YYYY-MM-dd')
                }

                sh """
                    sed -i -e 's#\\(readonly NIMBUS_RELEASE_VERSION=\\).*#\\1"${env.BRANCH_NAME}"#' \\
                           -e 's#\\(readonly NIMBUS_RELEASE_DATE=\\).*#\\1"${releaseDate}"#' nimbusapp
                """
            }
        }

        stage('Test Setup') {
            steps {
                dir('bats-core') {
                    git(url: 'https://github.com/bats-core/bats-core')
                }
                sh '''
                (
                    set -x
                    docker version
                    docker-compose version
                    docker-app version
                    nimbusapp version
                ) 2>&1 | tee test-versions.txt
                '''
            }
        } // Test Setup

        stage('Test') {
            steps {
                sh '''
                    export PATH="$PWD/bats-core/libexec/bats-core:$PATH"
                    bats tests --tap | tee bats-tap.log
                '''
            }
            post {
                always {
                    step([$class: 'TapPublisher', testResults: 'bats-tap.log'])
                }
            }
        } // Test

        stage('Archive') {
            steps {
                archiveArtifacts artifacts: 'nimbusapp,bats-tap.log,test-versions.txt'
            }
        } // Archive
    } // stages
} // pipeline

