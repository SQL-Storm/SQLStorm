-- {"query": "27.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 943} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Question
    AND p.CreationDate >= CURRENT_DATE - INTERVAL '180 days'
),
tag_stats AS (
  SELECT
    t.TagName,
    COUNT(*) FILTER (WHERE rp.PostId IS NOT NULL) AS linked_post_count,
    AVG(p.Score) AS avg_score,
    SUM(p.ViewCount) AS total_views,
    MAX(p.CreationDate) AS last_created
  FROM Tags t
  LEFT JOIN (
    SELECT DISTINCT Unnest := unnest(string_to_array(p.Tags, '><')) AS TagNameAlias, p.Id, p.Score, p.ViewCount, p.CreationDate
    FROM Posts p
    WHERE p.PostTypeId = 1
  ) AS rp ON rp.TagNameAlias = t.TagName
  GROUP BY t.TagName
),
active_users AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    COALESCE(bg.badge_count, 0) AS badge_count
  FROM Users u
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS badge_count
    FROM Badges
    GROUP BY UserId
  ) AS bg ON bg.UserId = u.Id
  WHERE u.LastAccessDate >= CURRENT_DATE - INTERVAL '365 days'
),
complex_posts AS (
  SELECT
    pp.PostId,
    pp.Title,
    pp.Views AS v1,
    pp.Score AS s1,
    pp.OwnerUserId,
    pc.Score AS s2,
    pc.ViewCount AS v2,
    pc.LastActivityDate,
    pc.AskCount,
    CASE
      WHEN pc.OwnerUserId IS NULL THEN NULL
      ELSE (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = pc.PostId AND v.VoteTypeId = 8)
    END AS avg_bounty
  FROM recent_questions rp
  LEFT JOIN LATERAL (
    SELECT p.Title, p.ViewCount, p.Score, p.LastActivityDate, p.AnswerCount AS AskCount
    FROM Posts p
    WHERE p.Id = rp.Id
  ) AS pc ON true
  LEFT JOIN (
    SELECT p.ParentId AS PostId, SUM(p.ViewCount) AS Views, SUM(p.Score) AS Score
    FROM Posts p
    WHERE p.ParentId IS NOT NULL
    GROUP BY p.ParentId
  ) AS pp ON pp.PostId = rp.Id
)
SELECT
  q.PostId,
  q.Title,
  q.Tags,
  q.CreationDate,
  q.ViewCount,
  q.Score,
  u.DisplayName AS Owner,
  u.Reputation AS OwnerReputation,
  q.LastActivityDate,
  q.CommentCount,
  q.AnswerCount,
  a.badge_count AS OwnerBadges,
  tp.TagName,
  tp.linked_post_count,
  tp.avg_score AS TagAvgScore,
  tp.total_views AS TagTotalViews,
  acs.avg_bounty AS AvgBountyOnPost
FROM recent_questions q
JOIN active_users u ON u.Id = q.OwnerUserId
LEFT JOIN (
  SELECT
    unnest(string_to_array(q.Tags, '><')) AS TagName
  FROM Posts q
  WHERE q.Id = q.PostId
) AS t ON true
LEFT JOIN tag_stats tp ON tp.TagName = t.TagName
LEFT JOIN (
  SELECT OwnerUserId, SUM(1) AS AskCount
  FROM Posts
  GROUP BY OwnerUserId
) AS ac ON ac.OwnerUserId = q.OwnerUserId
LEFT JOIN (
  SELECT PostId, AVG(BountyAmount) AS avg_bounty
  FROM Votes
  WHERE VoteTypeId = 8
  GROUP BY PostId
) AS acs ON acs.PostId = q.PostId
WHERE q.rn = 1
ORDER BY q.CreationDate DESC
LIMIT 100;