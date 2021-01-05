pipeline {
    agent { label 'linux' }

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
        stage('Notify Start') {
            steps {
                script {
                    slackSend(
                        channel: 'nimbus',
                        message: "${env.JOB_NAME} - ${currentBuild.displayName} ${currentBuild.buildCauses[0].shortDescription} (<${env.JOB_URL}|Open>)",
                        color: (currentBuild.previousBuild?.result == 'SUCCESS') ? 'good' : 'danger'
                    )
                }
            }
        }

        stage('Setup') {
            steps {
                checkout scm
            }
        }

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
                    expression { params.DOCKERAPP_FORCE_PUSH }
                }
            }
            steps {
                script {
                    // Assumptions:
                    //  - Github and Docker Hub organizations match
                    //  - Job is in root folder of this instance
                    pushOpts = $/--namespace "${env.JOB_NAME.split('/')[0]}"/$

                    if (params.DOCKERAPP_FORCE_PUSH && params.DOCKERAPP_TAG) {
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
                    ./nimbusapp version
                ) 2>&1 | tee test-versions.txt
                '''
            }
        } // Test Setup

        stage('Test') {
            steps {
                lock('nimbusapp-test') {
                    sh '''
                        export PATH="$PWD/bats-core/libexec/bats-core:$PATH"
                        bats tests --tap | tee bats-tap.log
                    '''
                }
            }
            post {
                always {
                    step([$class: 'TapPublisher', testResults: 'bats-tap.log'])
                }
            }
        } // Test

        stage('Archive') {
            steps {
                sh '''
                tar -czvf nimbusapp.tar.gz nimbusapp
                '''
                archiveArtifacts artifacts: 'nimbusapp,nimbusapp.tar.gz,bats-tap.log,test-versions.txt'
            }
        } // Archive
    } // stages
    post {
        always {
            slackSend(
                channel: 'nimbus',
                message: "${env.JOB_NAME} - ${currentBuild.displayName} *${currentBuild.currentResult}* in ${currentBuild.durationString.replaceAll(' and counting', '')}" + ((currentBuild.currentResult != 'SUCCESS') ? " (<${env.BUILD_URL}console|Console>)" : ''),
                color: (currentBuild.currentResult == 'SUCCESS') ? 'good' : 'danger'
            )
        }
    } // post
} // pipeline

