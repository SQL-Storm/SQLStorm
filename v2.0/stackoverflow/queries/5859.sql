-- {"query": "5859.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 935} 
WITH top_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS rn
  FROM Users u
  WHERE u.AccountId IS NOT NULL
),
recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '180 days')
),
high_activity_tags AS (
  SELECT
    t.TagName,
    COUNT(*) AS post_count,
    AVG(p.Score) AS avg_score,
    MAX(p.LastActivityDate) AS last_activity
  FROM Posts p
  JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  ) t ON TRUE
  GROUP BY t.TagName
  ORDER BY post_count DESC
  LIMIT 5
),
recent_votes AS (
  SELECT
    v.Id AS VoteId,
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount
  FROM Votes v
  WHERE v.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '60 days')
),
correlated_comments AS (
  SELECT
    c.Id AS CommentId,
    c.PostId,
    c.UserId,
    c.Score,
    c.CreationDate,
    c.Text,
    p.OwnerUserId AS PostOwner
  FROM Comments c
  JOIN Posts p ON p.Id = c.PostId
  WHERE c.Score > 0
),
complex_metrics AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS questions_asked,
    COUNT(DISTINCT v.PostId) FILTER (WHERE v.VoteTypeId = 2) AS upvotes_received,
    COUNT(DISTINCT v.PostId) FILTER (WHERE v.VoteTypeId = 3) AS downvotes_received,
    SUM(p.ViewCount) AS total_views,
    MAX(p.LastActivityDate) AS last_activity
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1
  GROUP BY u.Id, u.DisplayName
),
outer_join_example AS (
  SELECT
    tu.UserId,
    tu.DisplayName,
    rq.PostId AS QuestionPostId,
    rq.Title AS QuestionTitle,
    COALESCE(hat.post_count, 0) AS related_tag_count,
    rat.avg_score AS related_tag_avg_score
  FROM top_users tu
  LEFT JOIN recent_questions rq ON rq.OwnerUserId = tu.UserId
  LEFT JOIN high_activity_tags hat ON true
  LEFT JOIN (
    SELECT t.TagName, AVG(p.Score) AS avg_score
    FROM Posts p
    JOIN LATERAL (
      SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    ) t ON TRUE
    GROUP BY t.TagName
  ) rat ON TRUE
)
SELECT
  ou.UserId,
  ou.DisplayName,
  ou.QuestionPostId,
  ou.QuestionTitle,
  ou.related_tag_count,
  ou.related_tag_avg_score,
  cm.questions_asked,
  cm.upvotes_received,
  cm.downvotes_received,
  cm.total_views,
  cm.last_activity,
  rv.VoteId AS recent_vote_id,
  rv.PostId AS voted_post_id,
  rv.VoteTypeId AS vote_type_id,
  rv.CreationDate AS vote_creation_date,
  cc.CommentId,
  cc.PostId AS comment_post_id,
  cc.UserId AS comment_user_id,
  cc.Score AS comment_score,
  cc.CreationDate AS comment_creation_date
FROM outer_join_example ou
LEFT JOIN complex_metrics cm ON cm.UserId = ou.UserId
LEFT JOIN recent_votes rv ON rv.PostId = ou.QuestionPostId
LEFT JOIN correlated_comments cc ON cc.PostId = ou.QuestionPostId
ORDER BY ou.UserId
LIMIT 100;