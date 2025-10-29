-- {"query": "14056.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 534}
WITH cte AS (
  SELECT p.Id, p.PostTypeId, p.CreationDate, p.Score, p.OwnerUserId, u.Reputation, u.DownVotes, u.UpVotes, u.Views, u.DisplayName, u.AccountId
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
),
agg_cte AS (
  SELECT 
    CASE 
      WHEN PostTypeId = 1 THEN 'Question'
      WHEN PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS post_type,
    DATE_TRUNC('month', CreationDate) AS creation_month,
    COUNT(*) AS total_posts,
    SUM(Score) AS total_score,
    AVG(Reputation) AS avg_rep,
    SUM(UpVotes) AS total_upvotes,
    SUM(DownVotes) AS total_downvotes,
    SUM(Views) AS total_views,
    COUNT(DISTINCT OwnerUserId) AS distinct_users,
    COUNT(DISTINCT AccountId) AS distinct_accounts
  FROM cte
  GROUP BY post_type, DATE_TRUNC('month', CreationDate)
),
rank_cte AS (
  SELECT
    creation_month,
    post_type,
    total_posts,
    total_score,
    avg_rep,
    total_upvotes,
    total_downvotes,
    total_views,
    distinct_users,
    distinct_accounts,
    RANK() OVER (PARTITION BY creation_month ORDER BY total_posts DESC) AS post_type_rank
  FROM agg_cte
)
SELECT 
  creation_month,
  post_type,
  total_posts,
  total_score,
  avg_rep,
  total_upvotes,
  total_downvotes,
  total_views,
  distinct_users,
  distinct_accounts,
  post_type_rank
FROM rank_cte
WHERE post_type_rank <= 3
ORDER BY creation_month, post_type_rank;
