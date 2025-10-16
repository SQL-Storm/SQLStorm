-- {"query": "6077.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1137} 
WITH RankedPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.Tags,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Body,
    p.ParentId,
    p.AcceptedAnswerId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.LastEditorDisplayName,
    p.OwnerDisplayName,
    p.ContentLicense,
    -- window functions for ranking posts by activity within day and type
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId
                       ORDER BY p.LastActivityDate DESC, p.Score DESC) AS rn_type
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
),
Filtered AS (
  SELECT
    r.*,
    -- correlated subquery: count of comments per post
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = r.Id) AS CommentTotal,
    -- approximate engagement score combining views, score, and comments
    (r.ViewCount * 1.0 + r.Score * 2.0 + (SELECT COUNT(*) FROM Comments c2 WHERE c2.PostId = r.Id) * 3.0) AS EngagementScore
  FROM RankedPosts r
  WHERE r.PostTypeId IN (1, 2) -- Questions and Answers
    AND (r.LastActivityDate IS NOT NULL)
),
Joined AS (
  SELECT
    f.Id,
    f.Title,
    f.Tags,
    f.PostTypeId,
    f.OwnerUserId,
    f.CreationDate,
    f.LastActivityDate,
    f.Score,
    f.ViewCount,
    f.CommentCount,
    f.AnswerCount,
    f.FavoriteCount,
    f.Body,
    f.ParentId,
    f.AcceptedAnswerId,
    f.LastEditorUserId,
    f.LastEditDate,
    f.LastEditorDisplayName,
    f.OwnerDisplayName,
    f.ContentLicense,
    f.rn_type,
    f.CommentTotal,
    f.EngagementScore,
    -- string expressions: total length of Title and Tags
    LENGTH(TRIM(f.Title)) AS TitleLen,
    LENGTH(TRIM(f.Tags)) AS TagsLen
  FROM Filtered f
),
Agg AS (
  SELECT
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND CreationDate >= NOW() - INTERVAL '7 days') AS Questions7d,
    (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) AS AvgQuestionScore,
    (SELECT SUM(EngagementScore) FROM Joined) AS TotalEngagement
  FROM Joined
)
SELECT
  j.Id,
  j.Title,
  j.Tags,
  j.PostTypeId,
  j.OwnerUserId,
  j.OwnerDisplayName,
  j.CreationDate,
  j.LastActivityDate,
  j.Score,
  j.ViewCount,
  j.CommentCount,
  j.AnswerCount,
  j.FavoriteCount,
  j.Body,
  j.ParentId,
  j.AcceptedAnswerId,
  j.LastEditorUserId,
  j.LastEditDate,
  j.LastEditorDisplayName,
  j.ContentLicense,
  j.rn_type,
  j.CommentTotal,
  j.EngagementScore,
  j.TitleLen,
  j.TagsLen,
  a.Questions7d,
  a.AvgQuestionScore,
  a.TotalEngagement
FROM Joined j
CROSS JOIN Agg a
WHERE
  j.rn_type = 1
  -- complicated predicate: include posts that are either highly engaged or recently created
  AND (j.EngagementScore > 100 OR j.CreationDate >= NOW() - INTERVAL '14 days')
  -- optional NULL logic: if there is no LastEditor, fall back to Owner
  AND (j.LastEditorUserId IS NOT NULL OR j.OwnerUserId IS NOT NULL)
  -- set operator: union with a synthetic set of posts matching a different criterion
  UNION ALL
  SELECT
    p.Id,
    p.Title,
    p.Tags,
    p.PostTypeId,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Body,
    p.ParentId,
    p.AcceptedAnswerId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.LastEditorDisplayName,
    p.ContentLicense,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_type,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentTotal,
    (p.ViewCount * 0.5 + p.Score * 1.5) AS EngagementScore,
    LENGTH(TRIM(p.Title)) AS TitleLen,
    LENGTH(TRIM(p.Tags)) AS TagsLen,
    NULL AS Questions7d,
    NULL AS AvgQuestionScore,
    NULL AS TotalEngagement
  FROM Posts p
  WHERE p.PostTypeId = 1
  AND p.CreationDate >= NOW() - INTERVAL '30 days'
ORDER BY TotalEngagement DESC NULLS LAST
LIMIT 100;