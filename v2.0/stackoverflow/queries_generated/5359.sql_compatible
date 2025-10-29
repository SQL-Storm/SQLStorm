WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.PostTypeId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.LastEditorUserId,
    p.LastEditDate,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.Location,
    u.AccountId,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_type_desc,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS UpVotesForPost,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS DownVotesForPost,
    COUNT(*) OVER (PARTITION BY p.Id) AS LinkCount
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN Tags t ON t.WikiPostId = p.Id OR t.ExcerptPostId = p.Id
  WHERE p.PostTypeId IN (1,2)
),
CorrelatedStats AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.Tags,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerUserId,
    rp.LastActivityDate,
    rp.PostTypeId,
    rp.ParentId,
    rp.AcceptedAnswerId,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.Body,
    rp.LastEditorUserId,
    rp.LastEditDate,
    rp.ContentLicense,
    rp.Reputation,
    rp.OwnerDisplayName,
    rp.Location,
    rp.AccountId,
    rp.rn_type_desc,
    rp.UpVotesForPost,
    rp.DownVotesForPost,
    rp.LinkCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId) AS CommentCountForPost,
    (SELECT MAX(CASE WHEN pv.VoteTypeId = 2 THEN pv.CreationDate END)
       FROM Votes pv WHERE pv.PostId = rp.PostId) AS LastUpvoteDate,
    (SELECT STRING_AGG(CONCAT('=', pv.VoteTypeId, ':', pv.UserId), ',')
       FROM Votes pv WHERE pv.PostId = rp.PostId) AS VoteSummary
  FROM RankedPosts rp
),
OuterJoinsBenchmark AS (
  SELECT
    cs.PostId,
    cs.Title,
    cs.OwnerDisplayName,
    cs.Reputation,
    cs.CommentCountForPost,
    cs.UpVotesForPost,
    cs.DownVotesForPost,
    cs.ViewCount,
    cs.Score,
    cs.LastActivityDate,
    cs.CreationDate,
    cs.LinkCount,
    cs.rn_type_desc,
    cs.LastUpvoteDate,
    cs.VoteSummary,
    COALESCE(NULLIF(cs.Title, ''), 'Untitled') AS TitleOrDefault,
    CONCAT('[', cs.OwnerDisplayName, '] (Rep:', cs.Reputation, ')') AS OwnerBrief,
    CASE
      WHEN cs.Score >= 10 THEN 'HighScore'
      WHEN cs.Score >= 0 THEN 'Positive'
      ELSE 'Negative'
    END AS ScoreCategory,
    CASE
      WHEN cs.LinkCount IS NULL THEN 0
      ELSE cs.LinkCount * 1
    END AS LinkFactor,
    cs.Tags,
    cs.OwnerUserId,
    cs.ParentId,
    cs.AcceptedAnswerId,
    cs.CommentCount,
    cs.FavoriteCount,
    cs.Body,
    cs.LastEditorUserId,
    cs.LastEditDate,
    cs.ContentLicense,
    cs.Location,
    cs.AccountId
  FROM CorrelatedStats cs
  LEFT JOIN Votes v2 ON v2.PostId = cs.PostId
  LEFT JOIN PostLinks pl2 ON pl2.PostId = cs.PostId
  LEFT JOIN Users u2 ON cs.OwnerUserId = u2.Id
  WHERE cs.rn_type_desc <= 50
)
SELECT
  *
FROM OuterJoinsBenchmark
WHERE
  LastActivityDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30' DAY)
  AND (CommentCountForPost IS NULL OR CommentCountForPost < 100)
ORDER BY LastActivityDate DESC
LIMIT 100;