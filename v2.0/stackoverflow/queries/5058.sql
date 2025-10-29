-- {"query": "5058.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 813}
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId
  FROM Posts p
  WHERE p.LastActivityDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
),
TopAuthors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC) AS rn
  FROM Users u
  WHERE u.Reputation > 1000
),
TagStatistics AS (
  -- Split tags stored like '<tag1><tag2>' into rows in a portable way
  SELECT
    TRIM(BOTH '<>' FROM regexp_part) AS TagName,
    SUM(p.Score) AS ScoreSum,
    AVG(p.Score) AS AvgScore,
    COUNT(*) AS PostCount
  FROM Posts p,
  LATERAL (
    SELECT regexp_split_to_table(p.Tags, '><') AS regexp_part
  ) split
  WHERE p.PostTypeId = 1
  GROUP BY TRIM(BOTH '<>' FROM regexp_part)
),
ActivityWindow AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.LastActivityDate,
    LAG(p.LastActivityDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate) AS PrevActivity,
    LEAD(p.LastActivityDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate) AS NextActivity,
    CASE
      WHEN p.LastActivityDate IS NULL THEN NULL
      ELSE CAST(EXTRACT(EPOCH FROM (p.LastActivityDate - COALESCE(LAG(p.LastActivityDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate), p.CreationDate))) AS BIGINT)
    END AS SecondsSinceLastActivity
  FROM Posts p
  WHERE p.LastActivityDate IS NOT NULL
),
CorrelatedComments AS (
  SELECT
    c.Id AS CommentId,
    c.PostId,
    c.UserId,
    c.Text,
    c.CreationDate,
    c.Score
  FROM Comments c
  WHERE c.Text LIKE '%benchmark%' OR c.Text LIKE '%performance%'
),
Combined AS (
  SELECT
    r.Id AS PostId,
    r.OwnerUserId,
    r.LastActivityDate,
    t.TagName,
    t.ScoreSum,
    t.AvgScore,
    t.PostCount,
    a.PrevActivity,
    a.NextActivity,
    a.SecondsSinceLastActivity,
    cc.CommentId,
    cc.UserId AS CommentUserId,
    cc.Text AS CommentText,
    cc.CreationDate AS CommentDate,
    v.VoteTypeId,
    v.BountyAmount
  FROM RecentActivePosts r
  LEFT JOIN TopAuthors ta ON r.OwnerUserId = ta.UserId
  LEFT JOIN TagStatistics t ON 1=1
  LEFT JOIN ActivityWindow a ON r.Id = a.PostId
  LEFT JOIN CorrelatedComments cc ON r.Id = cc.PostId
  LEFT JOIN Votes v ON r.Id = v.PostId AND v.VoteTypeId = 2
)
SELECT
  c.PostId,
  c.OwnerUserId,
  c.LastActivityDate,
  c.TagName,
  c.ScoreSum,
  c.AvgScore,
  c.PostCount,
  c.PrevActivity,
  c.NextActivity,
  c.SecondsSinceLastActivity,
  c.CommentId,
  c.CommentUserId,
  c.CommentText,
  c.CommentDate,
  c.VoteTypeId,
  c.BountyAmount
FROM Combined c
ORDER BY c.LastActivityDate DESC
LIMIT 100;