WITH
TotalPostActivity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ClosedDate,
    p.ContentLicense,
    CASE WHEN p.OwnerUserId IS NULL THEN 1 ELSE 0 END AS IsAnonymousOwner,
    CASE WHEN p.Score IS NULL THEN NULL ELSE GREATEST(0, p.Score) END AS NonNegativeScore
  FROM Posts p
),
RecentBadgeHolders AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    b.Class,
    b.Date,
    b.TagBased,
    b.Name AS BadgeName
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  WHERE u.Reputation > 1000
    AND b.Date >= CAST('2024-10-01' AS DATE) - INTERVAL '180 days'
),
ActiveVotes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount,
    ot.Name AS VoteTypeName
  FROM Votes v
  JOIN VoteTypes ot ON ot.Id = v.VoteTypeId
  WHERE v.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '180 days'
),
LinkedPosts AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName,
    lt.Id AS LinkTypeId
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  WHERE pl.LinkTypeId IN (1, 3)
),
TagWikiSummary AS (
  SELECT
    t.TagName,
    t.Count,
    t.IsModeratorOnly,
    t.IsRequired,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.Count > 0
),
ComplexFilters AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY t.Count DESC) AS rn
  FROM TagWikiSummary t
  WHERE t.Count > 10
)
SELECT
  av.UserId AS top_contributor_id,
  ru.DisplayName AS top_contributor_name,
  ru.Reputation AS top_contributor_reputation,
  COUNT(*) AS total_posts,
  SUM(CASE WHEN tw.Named = 1 THEN 1 ELSE 0 END) AS tag_wiki_posts
FROM ActiveVotes av
JOIN Users ru ON ru.Id = av.UserId
LEFT JOIN Posts p ON p.Id = av.PostId
LEFT JOIN Posts parent_post ON parent_post.Id = p.ParentId
LEFT JOIN (SELECT 1 AS Named) AS tw ON 1 = 1
GROUP BY av.UserId, ru.DisplayName, ru.Reputation
ORDER BY total_posts DESC
LIMIT 100;