-- {"query": "5453.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1003} 
WITH top_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.ViewCount DESC NULLS LAST) AS rn
  FROM Users u
  WHERE u.Reputation > 1000
),
tag_pop AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagCount,
    AVG(p.Score) AS AvgPostScore
  FROM Tags tg
  JOIN Posts p ON p.Id = tg.ExcerptPostId
  JOIN (VALUES ('python'), ('sql'), ('c#'), ('java'), ('javascript')) AS v(TagName) ON v.TagName = tg.TagName
  GROUP BY t.TagName
),
recent_activities AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    ARRAY_AGG(DISTINCT v.VoteTypeId) AS VoteTypes
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.LastActivityDate > NOW() - INTERVAL '30 days'
  GROUP BY p.Id, p.Title, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.LastActivityDate, p.Score
),
complex_calc AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    CASE
      WHEN p.Tags LIKE '%<python>%'
        THEN 1
      WHEN p.Tags LIKE '%<sql>%'
        THEN 2
      ELSE 0
    END AS TagAffinity,
    p.LastActivityDate,
    (COALESCE(p.Score,0) * 1.15) + COALESCE(p.ViewCount,0) AS ScoreWeight
  FROM Posts p
  WHERE p.PostTypeId IN (1,2) -- questions and answers
    AND p.LastActivityDate IS NOT NULL
)
SELECT
  -- user profile snapshot
  t.UserId,
  t.DisplayName AS UserDisplayName,
  t.Reputation,
  t.CreationDate AS UserCreationDate,
  t.LastAccessDate,
  t.Location,
  t.Views,
  t.UpVotes,
  t.DownVotes,
  t.AccountId,
  -- top posts by user with weighting
  ARRAY_AGG(
    DISTINCT jsonb_build_object(
      'PostId', r.PostId,
      'Title', COALESCE(r.Title, ''),
      'PostTypeId', r.PostTypeId,
      'CreationDate', r.CreationDate,
      'LastActivityDate', r.LastActivityDate,
      'Score', r.ScoreWeight
    )
    ORDER BY r.ScoreWeight DESC
    LIMIT 5
  ) AS TopPosts,
  -- tag popularity insight
  (SELECT jsonb_object_agg(TagName, TagCount) FROM (
     SELECT t.TagName, t.TagCount
     FROM tag_pop t
     ORDER BY t.TagCount DESC
     LIMIT 5
  ) s) AS TopTags,
  -- recent activities per post
  (SELECT jsonb_agg(jsonb_build_object(
      'PostId', ra.PostId,
      'Title', ra.Title,
      'PostTypeId', ra.PostTypeId,
      'CreationDate', ra.CreationDate,
      'LastActivityDate', ra.LastActivityDate,
      'Score', ra.Score
    ))
   FROM recent_activities ra
   WHERE ra.OwnerUserId = t.UserId
     AND ra.Score IS NOT NULL
  ) AS RecentActivity
FROM top_users t
LEFT JOIN (
  SELECT
    p.OwnerUserId,
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    (COALESCE(p.Score,0) * 1.15) + COALESCE(p.ViewCount,0) AS ScoreWeight
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
) r ON r.OwnerUserId = t.UserId
GROUP BY
  t.UserId,
  t.DisplayName,
  t.Reputation,
  t.CreationDate,
  t.LastAccessDate,
  t.Location,
  t.Views,
  t.UpVotes,
  t.DownVotes,
  t.AccountId
ORDER BY t.Reputation DESC
LIMIT 100;