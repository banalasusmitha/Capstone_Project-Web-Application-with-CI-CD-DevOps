pipeline {
    agent any

    environment {
        AWS_ACCESS_KEY_ID = credentials('aws-access-key-id')
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')
        AWS_DEFAULT_REGION = 'ap-south-1'
    }

    stages {

        stage('Welcome') {
            steps {
                echo 'Starting Jenkins Pipeline...'
            }
        }

        stage('Environment Check') {
            steps {
                sh 'java --version'
                sh 'git --version'
                sh 'docker --version'
                sh 'aws --version'
            }
        }

        stage('AWS Authentication Test') {
            steps {
                sh 'aws sts get-caller-identity'
            }
        }
    }

    post {
        success {
            echo 'Pipeline completed successfully!'
        }
        failure {
            echo 'Pipeline failed.'
        }
    }
}
