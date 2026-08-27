pipeline {
    agent any

    environment {
        AWS_DEFAULT_REGION = 'ap-south-1'
    }

    stages {

        stage('Welcome') {
            steps {
                echo 'Starting Jenkins Terraform Pipeline...'
            }
        }

        stage('Environment Check') {
            steps {
                sh 'java --version'
                sh 'git --version'
                sh 'docker --version'
                sh 'aws --version'
                sh 'terraform -version'
            }
        }

        stage('AWS Identity Check') {
            steps {
                sh 'aws sts get-caller-identity'
            }
        }

        stage('Terraform Init') {
            steps {
                dir('terraform-Sushmita/envs/dev') {
                    sh 'terraform init -backend-config=backend.hcl -input=false'
                }
            }
        }

        stage('Terraform Validate') {
            steps {
                dir('terraform-Sushmita/envs/dev') {
                    sh 'terraform validate'
                }
            }
        }

        stage('Terraform Plan') {
            steps {
                dir('terraform-Sushmita/envs/dev') {
                    sh 'terraform plan -input=false'
                }
            }
        }
    }

    post {
        success {
            echo 'Jenkins Terraform pipeline completed successfully!'
        }

        failure {
            echo 'Jenkins Terraform pipeline failed.'
        }
    }
}
