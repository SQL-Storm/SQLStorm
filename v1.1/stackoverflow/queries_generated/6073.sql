-- {"query": "6073.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1037} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= NOW() - INTERVAL '30 days'
),
tag_roots AS (
  SELECT
    t.Id,
    t.TagName,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
question_tag_expansion AS (
  SELECT
    r.PostId,
    r.Title,
    r.Tags,
    a.TagName AS ExpandedTag
  FROM recent_questions r
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substr(r.Tags, 2, length(r.Tags)-2), '><')) AS TagName
  ) a ON true
),
popular_tags AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount
  FROM Tags t
  JOIN Posts p ON p.Id = t.ExcerptPostId
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
  HAVING COUNT(*) > 5
),
badge_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    b.Name AS BadgeName,
    b.Date AS EarnedDate
  FROM Users u
  JOIN Badges b ON b.UserId = u.Id
  WHERE b.Class IN (1,2,3)
    AND b.TagBased = 0
),
recent_votes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount
  FROM Votes v
  WHERE v.CreationDate >= NOW() - INTERVAL '14 days'
),
complex_metrics AS (
  SELECT
    q.PostId,
    q.Title,
    q.CreatedDate,
    q.ViewCount,
    q.Score,
    vc.UpVotes AS UpMod,
    vc.DownVotes AS DownMod,
    COALESCE(vc.UpMod - vc.DownMod, 0) AS NetScore
  FROM recent_questions q
  LEFT JOIN (
    SELECT
      PostId,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpMod,
      SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownMod
    FROM Votes
    GROUP BY PostId
  ) vc ON vc.PostId = q.Id
),
activity_summary AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.ViewCount,
    p.Score
  FROM Posts p
  WHERE p.PostTypeId = 1
)
SELECT
  q.PostId,
  q.Title,
  q.Tags,
  q.CreationDate AS CreationDate,
  q.Score,
  q.ViewCount,
  q.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  q.LastActivityDate,
  ca.CommentCount,
  ca.AnswerCount,
  ca.ViewCount AS PostViewCount,
  ca.Score AS PostScore,
  bp.BadgeName,
  ba.EarnedDate AS BadgeEarnedDate,
  rt.ExpandedTag AS ExpandedTagName,
  pt.TagName AS TagNameFromRelation,
  pv.UpMod AS UpVotesFromVotes,
  pv.DownMod AS DownVotesFromVotes,
  cs.NetScore AS NetScoreFromMetrics
FROM recent_questions q
LEFT JOIN Users u ON u.Id = q.OwnerUserId
LEFT JOIN (SELECT UserId, MAX(Date) AS EarnedDate, Name AS BadgeName
           FROM Badges
           GROUP BY UserId, Name) ba ON ba.UserId = q.OwnerUserId
LEFT JOIN badge_activity ba2 ON ba2.UserId = q.OwnerUserId
LEFT JOIN activity_summary ca ON ca.PostId = q.Id
LEFT JOIN LATERAL (
  SELECT unnest(string_to_array(substr(q.Tags, 2, length(q.Tags)-2), '><')) AS TagName
) pt ON true
LEFT JOIN popular_tags ptg ON pt.TagName = ptg.TagName
LEFT JOIN complex_metrics cs ON cs.PostId = q.Id
LEFT JOIN (
  SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpMod,
         SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownMod
  FROM Votes
  GROUP BY PostId
) pv ON pv.PostId = q.Id
ORDER BY q.LastActivityDate DESC
LIMIT 100;