
pipeline {
    agent any

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
                sh 'kubectl version --client'
                sh 'eksctl version'
            }
        }

        stage('Pipeline Test') {
            steps {
                echo 'Jenkins is successfully connected to GitHub.'
                echo 'DevOps environment is ready.'
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
        always {
            echo 'End of pipeline.'
        }
    }
}
