-- {"query": "5200.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 871} 
WITH recent_top_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ViewCount > 0
),
owner_stats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(*) AS total_questions,
    SUM(p.Score) AS total_score,
    AVG(NULLIF(p.ViewCount,0)) AS avg_views_per_question,
    MAX(p.CreationDate) AS last_question_date
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
recent_engagement AS (
  SELECT
    q.PostId,
    q.OwnerUserId,
    q.Title,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    q.Tags,
    (
      SELECT COUNT(*) FROM Comments c
      WHERE c.PostId = q.PostId
        AND c.CreationDate > q.CreationDate - INTERVAL '7 days'
    ) AS seven_day_comments,
    (
      SELECT COUNT(*) FROM Votes v
      WHERE v.PostId = q.PostId
        AND v.VoteTypeId = 2 -- UpMod
        AND v.CreationDate > q.CreationDate - INTERVAL '7 days'
    ) AS seven_day_upvotes
  FROM recent_top_questions q
  WHERE q.rn = 1
),
complex_pred AS (
  SELECT
    re.PostId,
    re.OwnerUserId,
    re.Title,
    re.CreationDate,
    re.ViewCount,
    re.Score,
    re.Tags,
    re.seven_day_comments,
    re.seven_day_upvotes,
    os.Reputation AS owner_reputation,
    os.total_questions,
    os.total_score,
    os.avg_views_per_question,
    os.last_question_date,
    CASE
      WHEN re.ViewCount > 1000 AND re.Score > 5 THEN 'high_visibility'
      WHEN re.seven_day_comments > 20 THEN 'high_engagement'
      ELSE 'normal'
    END AS category
  FROM recent_engagement re
  LEFT JOIN owner_stats os ON os.UserId = re.OwnerUserId
  LEFT JOIN Posts p ON p.Id = re.PostId
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  WHERE re.ViewCount > 0
    AND (re.OwnerUserId IS NOT NULL)
),
final_set AS (
  SELECT
    cp.PostId,
    cp.Title,
    cp.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    cp.CreationDate,
    cp.ViewCount,
    cp.Score,
    cp.Tags,
    cp.seven_day_comments,
    cp.seven_day_upvotes,
    cp.owner_reputation,
    cp.total_questions,
    cp.total_score,
    cp.avg_views_per_question,
    cp.last_question_date,
    cp.category,
    -- rank per owner by creation date
    ROW_NUMBER() OVER (PARTITION BY cp.OwnerUserId ORDER BY cp.CreationDate DESC) AS owner_rank
  FROM complex_pred cp
  LEFT JOIN Users u ON u.Id = cp.OwnerUserId
)
SELECT
  PostId,
  Title,
  OwnerUserId,
  OwnerDisplayName,
  CreationDate,
  ViewCount,
  Score,
  Tags,
  seven_day_comments,
  seven_day_upvotes,
  owner_reputation,
  total_questions,
  total_score,
  avg_views_per_question,
  last_question_date,
  category,
  owner_rank
FROM final_set
WHERE owner_rank = 1
  AND category IN ('high_visibility','high_engagement')
ORDER BY CreationDate DESC
LIMIT 50;