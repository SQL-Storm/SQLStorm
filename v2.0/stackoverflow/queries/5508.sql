-- {"query": "5508.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 930}
WITH recent_top_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate DESC) AS rn
  FROM Users u
  WHERE u.AccountId IS NOT NULL
),
tag_issue AS (
  SELECT
    t.TagName,
    t.Count,
    p.Id AS PostId,
    p.CreationDate AS PostDate,
    p.Score,
    p.ViewCount,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount
  FROM Tags t
  JOIN Posts p ON p.Id = t.ExcerptPostId
  WHERE COALESCE(t.IsModeratorOnly, FALSE) = FALSE
),
corr AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.LastActivityDate,
    p.CreationDate,
    p.Title,
    p.Tags,
    p.AcceptedAnswerId,
    p.ParentId,
    p.PostTypeId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.ContentLicense,
    COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
    -- preserve has_upvotes if needed as a column
    (SELECT MAX(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)
     FROM Votes v
     WHERE v.PostId = p.Id) AS has_upvotes
  FROM Posts p
),
pivoted AS (
  SELECT
    c.PostId,
    c.Title,
    c.Tags,
    c.OwnerUserId,
    c.Score,
    c.ViewCount,
    c.CommentCount,
    c.LastActivityDate,
    c.CreationDate,
    (SELECT pt.Name FROM PostTypes pt WHERE pt.Id = c.PostTypeId) AS PostType,
    (SELECT STRING_AGG(tt.Name, ',' ORDER BY tt.Name) FROM Votes vv
       JOIN VoteTypes tt ON tt.Id = vv.VoteTypeId
       WHERE vv.PostId = c.PostId
         AND tt.Name IN ('UpMod', 'DownMod')
    ) AS VoteSummary,
    (SELECT COUNT(*) FROM Comments co WHERE co.PostId = c.PostId) AS CommentTotal
  FROM corr c
),
full_posts AS (
  SELECT
    p.PostId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.LastActivityDate,
    p.CreationDate,
    p.PostType,
    p.VoteSummary,
    p.CommentTotal,
    u.Reputation AS OwnerReputation,
    u.DisplayName AS OwnerDisplayName,
    u.Location AS OwnerLocation,
    u.AccountId AS OwnerAccount
  FROM pivoted p
  JOIN (
    SELECT Id, Reputation, DisplayName, Location, AccountId
    FROM Users
  ) u ON u.Id = p.OwnerUserId
),
windows AS (
  SELECT
    f.PostId,
    f.Title,
    f.Tags,
    f.OwnerUserId,
    f.Score,
    f.ViewCount,
    f.CommentCount,
    f.LastActivityDate,
    f.CreationDate,
    f.PostType,
    f.VoteSummary,
    f.CommentTotal,
    f.OwnerReputation,
    f.OwnerDisplayName,
    f.OwnerLocation,
    f.OwnerAccount,
    SUM(CASE WHEN f.PostType = 'Question' THEN 1 ELSE 0 END) OVER (
      ORDER BY f.CreationDate
      ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
    ) AS PostsLastYear,
    ROW_NUMBER() OVER (PARTITION BY f.OwnerUserId ORDER BY f.CreationDate DESC) AS UserRecencyRank
  FROM full_posts f
)
SELECT
  w.PostId,
  w.Title,
  w.Tags,
  w.OwnerUserId,
  w.Score,
  w.ViewCount,
  w.CommentCount,
  w.LastActivityDate,
  w.CreationDate,
  w.PostType,
  w.VoteSummary,
  w.CommentTotal,
  w.OwnerReputation,
  w.OwnerDisplayName,
  w.OwnerLocation,
  w.OwnerAccount,
  w.PostsLastYear,
  w.UserRecencyRank
FROM windows w
LEFT JOIN PostLinks pl ON pl.PostId = w.PostId
LEFT JOIN Posts rp ON rp.Id = pl.RelatedPostId
WHERE w.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '7' DAY)
  AND w.OwnerReputation > 100
  AND (w.Tags LIKE '%<c%>' OR w.Tags LIKE '%<java>%')
GROUP BY
  w.PostId,
  w.Title,
  w.Tags,
  w.OwnerUserId,
  w.Score,
  w.ViewCount,
  w.CommentCount,
  w.LastActivityDate,
  w.CreationDate,
  w.PostType,
  w.VoteSummary,
  w.CommentTotal,
  w.OwnerReputation,
  w.OwnerDisplayName,
  w.OwnerLocation,
  w.OwnerAccount,
  w.PostsLastYear,
  w.UserRecencyRank,
  pl.PostId,
  rp.Id
ORDER BY w.LastActivityDate DESC, w.Score DESC
LIMIT 100;