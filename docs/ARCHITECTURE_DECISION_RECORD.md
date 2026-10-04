# ADR-001: Intelligent DocQuery: RAG on Amazon Bedrock

**Status:** Built as a Udacity course project (proof of concept) · **Region:** us-west-2

## Context
The system answers natural-language questions about heavy-machinery spec sheets. A technician or salesperson asks a question, and the answer is grounded in the company's own PDFs, not the model's general knowledge. The current corpus is 5 PDFs (about 1.7 MB). I started from a Udacity template that defined the architecture. I deployed it in a course sandbox, wired the stacks together, rewrote the prompt classifier, and documented the temperature/top_p tuning.

**How it works.** I upload PDFs to S3 with a script and trigger a Bedrock Knowledge Base sync by hand. The KB embeds chunks with Titan Text Embeddings v1 and writes them to a pgvector table (1536-dim, HNSW index) on Aurora PostgreSQL, using the RDS Data API. A local Streamlit app sends each question to Claude, which classifies it; only heavy-machinery questions pass. The app then retrieves the top 3 chunks and has Claude (3 Haiku or 3.5 Sonnet, selectable) answer from them.

## Decisions as built
The choices came from the template. The alternatives and trade-offs are my own analysis now; I didn't weigh them at the time.

| Decision | Alternatives | Trade-offs | Why kept |
|---|---|---|---|
| **Bedrock** for LLM, embeddings and RAG orchestration | OpenAI/Azure; self-hosted model on GPUs | Pay-per-token with no idle GPU cost. Data stays in the AWS account under IAM. Chunking and sync are managed. Lock-in to the KB APIs; less control over chunking | Template; least ops for a PoC |
| **Aurora PostgreSQL + pgvector** as vector store | OpenSearch Serverless; Pinecone | One familiar SQL engine that can also hold relational data. OpenSearch Serverless bills $0.24/OCU-hour with an idle floor. pgvector tuning and scaling are on me | Template. My guess: lowest idle cost among Bedrock-supported stores |
| **Aurora Serverless v2** (0.5–1 ACU) | Provisioned instance; scale-to-zero | Scales with load, but a 0.5 ACU floor bills 24/7 | Template |
| **Terraform**, two stacks | Console; CDK; CloudFormation | Repeatable and reviewable. Hand-copied ARNs between stacks and local state are fragile | Template |
| **LLM prompt classifier** as guardrail | Bedrock Guardrails; keyword rules | Flexible, but one extra model call per question, and it fails closed on any API error | Template; I rewrote the prompt |

## Estimated cost (ESTIMATES, on-demand us-west-2 list prices, AWS Price List Sept–Oct 2026, 730 h/month)
Per-query assumptions:
- Classifier call: 200 tokens in, 10 tokens out.
- Answer call: 1,000 tokens in (3 chunks of about 300 tokens, the KB default since chunking isn't set), 500 tokens out (the `max_tokens` cap).
- Claude 3 Haiku ($0.25/$1.25 per M tokens) gives about $0.0009 per query. Sonnet-class ($3/$15) gives about $0.011.

| Item | PoC: 5 docs, 600 queries/month | Client: 10k docs, 60k queries/month |
|---|---|---|
| Aurora ($0.12/ACU-h) | 0.5 ACU floor ≈ $44 | Writer + reader, avg 2 ACU each ≈ $350 |
| NAT gateway + IPv4 ($0.045 + $0.005/h) | ≈ $37 | ≈ $37 |
| Bedrock (Haiku / Sonnet-class) | < $1 / ≈ $7 | ≈ $56 / ≈ $675 |
| S3, Secrets Manager, storage, Data API | < $2 | ≈ $3 + ≈ $10 one-time embedding |
| **Total** | **≈ $80–90/month** | **≈ $450 (Haiku) to ≈ $1,060 (Sonnet-class)** |

Not included: app hosting (the app runs locally today), I/O, data transfer, logging. Over 95% of PoC cost is idle infrastructure, not AI. The NAT gateway serves nothing in this build: Aurora is reached through the Data API and the app runs outside the VPC. Aurora PostgreSQL 14 leaves standard support on 28 Feb 2027; after that, Extended Support adds $0.085/ACU-hour.

## What would change at client scale
- **Multi-tenancy:** a KB per client, or metadata filters on every retrieve call.
- **PII and data residency:** the region becomes a contract term, not a hardcoded default. Add KMS customer-managed keys and PII redaction at ingestion.
- **Access control:** add authentication (e.g. Cognito/SSO). Use least-privilege IAM to replace `AmazonBedrockFullAccess` and `s3:GetObject` on `*`. Use a dedicated DB user instead of the master user.
- **Observability:** log questions, retrieved chunks and answers. Build an evaluation set to measure answer quality.
- **Failure modes:** errors currently return blank answers. Backups, a final snapshot and secret recovery are disabled. Sync is manual.
- **Cost control:** set budgets and alerts, route most queries to a cheap model, and drop or justify the NAT gateway.

## What I'd revisit
- The KB ID is hardcoded; the sidebar input is ignored.
- Temperature and top_p default to 1.0 in the app, though my own analysis recommends about 0.1–0.3 and 0.1.
- Claude 3.5 Sonnet (June 2024) appears to be past end-of-life on Bedrock.
- There are no citations, no tests and no answer-quality evaluation.
- A 48 MB AWS CLI installer is committed to the repo.

## Open questions
- Why did the template choose pgvector over OpenSearch Serverless?
- Why did a contributor switch the database to `db.t3.medium` (Apr 2025) and then revert it (Oct 2025)?
- Which model did I actually run?
- Does Bedrock add any fee for Retrieve calls on top of embedding tokens?
