WITH enriched AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastEditDate,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.Location,
    u.ProfileImageUrl,
    u.AccountId,
    COALESCE(b.Name, 'None') AS BadgeName,
    b.Class,
    b.Date AS BadgeDate,
    COALESCE(w.Name, 'None') AS WikiOrName,
    v.VoteTypeId,
    v.CreationDate AS VoteDate,
    vt.Name AS VoteTypeName,
    pt.Name AS PostTypeName,
    t.TagName
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id AND b.Date = (
      SELECT MAX(b2.Date) FROM Badges b2 WHERE b2.UserId = u.Id
  )
  LEFT JOIN (SELECT Id, Name FROM PostHistoryTypes) w ON w.Id = 16
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
  LEFT JOIN LATERAL (
      SELECT unnest(string_to_array(
        SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')
      ) AS TagName
  ) t ON true
),
agg AS (
  SELECT
    e.PostId,
    e.PostTypeId,
    e.PostTypeName,
    e.OwnerUserId,
    e.OwnerDisplayName,
    e.CreationDate,
    MAX(CASE WHEN e.VoteTypeName = 'UpMod' THEN 1 ELSE 0 END) AS HasUpvote,
    SUM(COALESCE(v.BountyAmount,0)) AS TotalBounty,
    SUM(CASE WHEN v.VoteTypeId IN (2,14,15,16) THEN 1 ELSE 0 END) AS PositiveVotes,
    COUNT(DISTINCT e.TagName) AS TagCount
  FROM enriched e
  LEFT JOIN (SELECT Id, PostId, VoteTypeId, BountyAmount, CreationDate FROM Votes) v ON e.PostId = v.PostId
  GROUP BY e.PostId, e.PostTypeId, e.PostTypeName, e.OwnerUserId, e.OwnerDisplayName, e.CreationDate
)
SELECT
  a.PostId,
  a.PostTypeName,
  e.Title,
  a.TagCount,
  a.CreationDate,
  a.TotalBounty,
  a.PositiveVotes,
  a.OwnerDisplayName,
  e.Reputation,
  e.Location,
  e.TagName,
  e.ViewCount,
  e.Score,
  e.CommentCount,
  e.AnswerCount,
  e.FavoriteCount,
  e.ContentLicense,
  a.HasUpvote
FROM agg a
LEFT JOIN enriched e ON a.PostId = e.PostId
WHERE
  a.PostTypeName IN ('Question', 'TagWiki', 'TagWikiExcerpt')
  AND a.TotalBounty > 0
  AND a.PositiveVotes > 5
GROUP BY
  a.PostId,
  a.PostTypeName,
  e.Title,
  a.TagCount,
  a.CreationDate,
  a.TotalBounty,
  a.PositiveVotes,
  a.OwnerDisplayName,
  e.Reputation,
  e.Location,
  e.TagName,
  e.ViewCount,
  e.Score,
  e.CommentCount,
  e.AnswerCount,
  e.FavoriteCount,
  e.ContentLicense,
  a.HasUpvote
ORDER BY a.CreationDate DESC, a.TotalBounty DESC
LIMIT 100;