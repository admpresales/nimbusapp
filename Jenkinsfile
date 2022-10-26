@Library("nimbus-pipeline-library") _

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
                    notifyStart()
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
                    pushOpts = """ --namespace "${env.JOB_NAME.split('/')[0]}" """

                    if (params.DOCKERAPP_FORCE_PUSH && params.DOCKERAPP_TAG) {
                        pushOpts += """ --tag "${params.DOCKERAPP_TAG}" """
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
                sh """
                set -xe
                docker build . -t nimbusapp-builder:${env.BRANCH_NAME}
                docker run --rm -v "\$PWD:/app" -w /app nimbusapp-builder:${env.BRANCH_NAME} perl build.pl ${env.BRANCH_NAME}
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
                    set -xe
                    bats -v
                    perl -V
                    docker version
                    docker-compose version
                    docker-app version
                    ./build/nimbusapp.packed.pl version
                ) 2>&1 | tee test-versions.txt
                '''
            }
        } // Test Setup

        stage('Test') {
            steps {
                lock('nimbusapp-test') {
                    sh '''
                        set -xe

                        export PATH="$PWD/bats-core/bin:$PWD/bats-core/libexec/bats-core:$PATH"
                        export NIMBUS_EXE="./build/nimbusapp.packed.pl"
                        export PERLBREW_ROOT=/opt/perl5

                        /opt/perl5/bin/perlbrew exec --with 5.20.3 bats tests --tap | tee bats-tap.log
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
                archiveArtifacts artifacts: 'build/nimbusapp.tar.gz,build/nimbusapp.zip,bats-tap.log,test-versions.txt'
            }
        } // Archive
    } // stages
    post {
        always {
            notifyComplete()
        }
    } // post
} // pipeline

