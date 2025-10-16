-- {"query": "26007.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 791} 

WITH top_users AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    u.Reputation, 
    COUNT(DISTINCT p.Id) AS post_count,
    SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS positive_score_count,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS reputation_rank
  FROM 
    Users u
  LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
  WHERE 
    p.PostTypeId = 1
  GROUP BY 
    u.Id, u.DisplayName, u.Reputation
),
top_posts AS (
  SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount,
    LAG(p.Score, 1) OVER (ORDER BY p.Score DESC) AS prev_score,
    LEAD(p.Score, 1) OVER (ORDER BY p.Score DESC) AS next_score,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS score_rank
  FROM 
    Posts p
  WHERE 
    p.PostTypeId = 1
),
post_history_stats AS (
  SELECT 
    p.Id, 
    COUNT(DISTINCT ph.PostHistoryTypeId) AS post_history_type_count,
    MAX(ph.CreationDate) AS latest_post_history_date,
    MIN(ph.CreationDate) AS earliest_post_history_date
  FROM 
    Posts p
  LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
  GROUP BY 
    p.Id
),
user_badges AS (
  SELECT 
    u.Id, 
    COUNT(DISTINCT b.Name) AS badge_count,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badge_count,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badge_count,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badge_count
  FROM 
    Users u
  LEFT JOIN 
    Badges b ON u.Id = b.UserId
  GROUP BY 
    u.Id
)
SELECT 
  tu.Id, 
  tu.DisplayName, 
  tu.Reputation, 
  tu.post_count, 
  tu.positive_score_count,
  tu.reputation_rank,
  tp.Id AS top_post_id,
  tp.Title AS top_post_title,
  tp.Score AS top_post_score,
  tp.ViewCount AS top_post_view_count,
  tp.AnswerCount AS top_post_answer_count,
  phs.post_history_type_count,
  phs.latest_post_history_date,
  phs.earliest_post_history_date,
  ub.badge_count,
  ub.gold_badge_count,
  ub.silver_badge_count,
  ub.bronze_badge_count,
  CASE 
    WHEN tu.reputation_rank <= 10 THEN 'Top 10'
    WHEN tu.reputation_rank <= 50 THEN 'Top 50'
    ELSE 'Others'
  END AS reputation_rank_category,
  CASE 
    WHEN tp.score_rank <= 10 THEN 'Top 10'
    WHEN tp.score_rank <= 50 THEN 'Top 50'
    ELSE 'Others'
  END AS score_rank_category
FROM 
  top_users tu
LEFT JOIN 
  top_posts tp ON tu.Id = tp.Id
LEFT JOIN 
  post_history_stats phs ON tu.Id = phs.Id
LEFT JOIN 
  user_badges ub ON tu.Id = ub.Id
WHERE 
  tu.Reputation > 1000
  AND tp.Score > 0
  AND phs.post_history_type_count > 1
  AND ub.badge_count > 5
ORDER BY 
  tu.Reputation DESC, 
  tp.Score DESC;
