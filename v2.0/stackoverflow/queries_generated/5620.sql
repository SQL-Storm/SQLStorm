-- {"query": "5620.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 710} 
WITH RankedQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    p.LastActivityDate,
    p.AcceptedAnswerId,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY
        p.Score DESC,
        p.ViewCount DESC,
        p.LastActivityDate DESC
    ) AS rn
  FROM
    Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE
    p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
  FROM
    Tags t
  WHERE
    t.IsModeratorOnly = 0
),
RecentActivity AS (
  SELECT
    ph.Id,
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.CreationDate,
    ph.UserId,
    ph.UserDisplayName,
    ph.Comment,
    ph.Text
  FROM
    PostHistory ph
  WHERE
    ph.PostHistoryTypeId IN (10,11,12,16,66) -- major state changes and community bump
),
JoinedActivity AS (
  SELECT
    q.PostId,
    q.Title,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.OwnerUserId,
    q.OwnerDisplayName,
    q.LastActivityDate,
    q.AcceptedAnswerId,
    q.AnswerCount,
    q.CommentCount,
    q.FavoriteCount,
    a.PostHistoryTypeId AS ActivityType,
    ra.CreationDate AS ActivityDate,
    ra.UserDisplayName AS ActivityUser
  FROM RankedQuestions q
  LEFT JOIN RecentActivity ra ON ra.PostId = q.PostId
  ORDER BY q.rn
),
CrossFiltered AS (
  SELECT
    j.*
  FROM JoinedActivity j
  LEFT JOIN TopTags tt ON j.Title ILIKE '%' || tt.TagName || '%'
  WHERE
    j.LastActivityDate > j.CreationDate - INTERVAL '180 days'
    OR j.ActivityDate IS NOT NULL
)
SELECT
  cf.PostId,
  cf.Title,
  cf.CreationDate,
  cf.Score,
  cf.ViewCount,
  cf.OwnerDisplayName,
  cf.LastActivityDate,
  cf.AcceptedAnswerId,
  cf.AnswerCount,
  cf.CommentCount,
  cf.FavoriteCount,
  cf.ActivityType,
  cf.ActivityDate,
  cf.ActivityUser,
  STRING_AGG(DISTINCT tt.TagName, ',') OVER (PARTITION BY cf.PostId) AS TagList,
  (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = cf.PostId AND v.VoteTypeId = 8) AS AverageBounty
FROM
  CrossFiltered cf
  LEFT JOIN TopTags tt ON cf.Title ILIKE '%' || tt.TagName || '%'
ORDER BY
  cf.LastActivityDate DESC NULLS LAST
LIMIT 1000;