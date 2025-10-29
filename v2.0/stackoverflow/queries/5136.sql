-- {"query": "5136.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1292}
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    u.DisplayName AS OwnerName,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days'
),
tag_population AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagQuestionCount,
    AVG(t.Score) AS AvgQuestionScore,
    SUM(t.ViewCount) AS TotalViews
  FROM (
    SELECT
      unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
      p.Id,
      p.Score,
      p.ViewCount
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days'
  ) t
  GROUP BY t.TagName
),
top_tags AS (
  SELECT
    TagName,
    TagQuestionCount,
    AvgQuestionScore,
    TotalViews,
    ROW_NUMBER() OVER (ORDER BY TotalViews DESC, AvgQuestionScore DESC) AS rn
  FROM tag_population
  WHERE TagQuestionCount > 20
),
most_active_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(*) AS PostCount,
    SUM(p.Score) AS ScoreSum,
    SUM(p.ViewCount) AS ViewSum
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '365 days'
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
correlated_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName AS OwnerName,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
    AVG(v.BountyAmount) FILTER (WHERE v.BountyAmount IS NOT NULL) AS AvgBounty
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId IN (1,2)
  GROUP BY p.Id, p.Title, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate, u.DisplayName
),
filtered AS (
  SELECT
    sub.PostId,
    sub.Title,
    sub.OwnerName,
    sub.CreationDate,
    sub.Score,
    sub.ViewCount,
    sub.LinkedTo,
    sub.LinkedTitle,
    sub.LinkedOwnerName,
    sub.LinkedCreationDate,
    sub.LinkedScore
  FROM (
    SELECT
      rq.PostId,
      rq.Title,
      rq.OwnerName,
      rq.CreationDate,
      rq.Score,
      rq.ViewCount,
      cr.Id AS LinkedTo,
      cr.Title AS LinkedTitle,
      cr.OwnerUserId,
      cr.CreationDate AS LinkedCreationDate,
      cr.Score AS LinkedScore,
      u2.DisplayName AS LinkedOwnerName,
      ROW_NUMBER() OVER (PARTITION BY rq.PostId ORDER BY cr.CreationDate DESC) AS rn
    FROM recent_questions rq
    LEFT JOIN PostLinks pl ON pl.PostId = rq.PostId
    LEFT JOIN Posts cr ON pl.RelatedPostId = cr.Id
    LEFT JOIN Users u2 ON cr.OwnerUserId = u2.Id
    WHERE cr.Id IS NOT NULL
  ) sub
  WHERE sub.rn = 1
)
SELECT
  f.PostId,
  f.Title AS PostTitle,
  f.OwnerName,
  f.CreationDate,
  f.Score AS PostScore,
  f.ViewCount AS PostViews,
  ARRAY_AGG(DISTINCT tt.TagName) FILTER (WHERE tt.TagName IS NOT NULL) AS TopTags,
  m.UserId AS MostActiveUserId,
  m.DisplayName AS MostActiveUserName,
  m.PostCount,
  m.ScoreSum,
  m.ViewSum,
  corr.Id AS CorrelatedPostId,
  corr.Title AS CorrelatedTitle,
  corr.OwnerName AS CorrelatedOwner,
  corr.Score AS CorrelatedScore,
  corr.UpVotes,
  corr.DownVotes,
  corr.AvgBounty
FROM filtered f
LEFT JOIN (
  SELECT
    mu.UserId,
    mu.DisplayName,
    mu.PostCount,
    mu.ScoreSum,
    mu.ViewSum
  FROM most_active_users mu
  ORDER BY mu.ScoreSum DESC
  LIMIT 1
) m ON TRUE
LEFT JOIN (
  SELECT
    p.Id,
    p.Title,
    u.DisplayName AS OwnerName,
    p.Score,
    p.ViewCount,
    AVG(v.BountyAmount) AS AvgBounty,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY p.Id, p.Title, u.DisplayName, p.Score, p.ViewCount
  ORDER BY p.Score DESC
  LIMIT 5
) corr ON corr.Id = f.PostId
LEFT JOIN (
  SELECT p.Id AS PostId, unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  FROM Posts p
  WHERE p.PostTypeId = 1
) tt ON tt.PostId = f.PostId
GROUP BY
  f.PostId, f.Title, f.OwnerName, f.CreationDate, f.Score, f.ViewCount,
  m.UserId, m.DisplayName, m.PostCount, m.ScoreSum, m.ViewSum,
  corr.Id, corr.Title, corr.OwnerName, corr.Score, corr.UpVotes, corr.DownVotes, corr.AvgBounty
ORDER BY f.CreationDate DESC
LIMIT 100;