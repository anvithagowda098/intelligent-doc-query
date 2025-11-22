provider "aws" {
  region = "us-west-2"  
}

module "bedrock_kb" {
  source = "../modules/bedrock_kb" 


  knowledge_base_name        = "my-bedrock-kb"
  knowledge_base_description = "Knowledge base connected to Aurora Serverless database"

  aurora_arn        = "arn:aws:rds:us-west-2:422471551086:cluster:my-aurora-serverless" 
  aurora_db_name    = "myapp"
  aurora_endpoint   = "my-aurora-serverless.cluster-cqzcvt29n8wu.us-west-2.rds.amazonaws.com" # TODO Update with output from stack1
  aurora_table_name = "bedrock_integration.bedrock_kb"
  aurora_primary_key_field = "id"
  aurora_metadata_field = "metadata"
  aurora_text_field = "chunks"
  aurora_verctor_field = "embedding"
  aurora_username   = "dbadmin"
  aurora_secret_arn = "arn:aws:secretsmanager:us-west-2:422471551086:secret:my-aurora-serverless-VVUcap" 
  s3_bucket_arn = "arn:aws:s3:::bedrock-kb-422471551086-5303" 
}