WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
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
    p.ContentLicense,
    p.Body,
    p.ParentId,
    p.AcceptedAnswerId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.OwnerDisplayName
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '60' DAY
),
TagUniverse AS (
  SELECT
    t.TagName,
    t.Count,
    r.PostId
  FROM Tags t
  JOIN LATERAL (
    SELECT t2.Id AS PostId
    FROM Posts t2
    WHERE t2.Id = t.ExcerptPostId
  ) r ON TRUE
),
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.WebsiteUrl,
    u.AboutMe,
    u.ProfileImageUrl,
    u.AccountId,
    COUNT(DISTINCT v.PostId) AS VotesCast
  FROM Users u
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    u.Views, u.UpVotes, u.DownVotes, u.Location, u.WebsiteUrl,
    u.AboutMe, u.ProfileImageUrl, u.AccountId
),
BadgeAgg AS (
  SELECT
    b.UserId,
    COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
    COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
    COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
  FROM Badges b
  GROUP BY b.UserId
),
Combined AS (
  SELECT
    rap.PostId,
    rap.PostTypeId,
    rap.Title,
    rap.Tags,
    rap.CreationDate,
    rap.LastActivityDate,
    rap.Score,
    rap.ViewCount,
    rap.AnswerCount,
    rap.CommentCount,
    rap.FavoriteCount,
    rap.ContentLicense,
    rap.Body,
    rap.ParentId,
    rap.AcceptedAnswerId,
    rap.OwnerUserId,
    COALESCE(us.DisplayName, rap.OwnerDisplayName) AS DisplayName,
    COALESCE(us.Reputation, 0) AS Reputation,
    COALESCE(usn.GoldBadges, 0) AS GoldBadges,
    COALESCE(usn.SilverBadges, 0) AS SilverBadges,
    COALESCE(usn.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(vs.VotesCast, 0) AS VotesCast
  FROM RecentActivePosts rap
  LEFT JOIN UserStats us ON us.UserId = rap.OwnerUserId
  LEFT JOIN BadgeAgg usn ON usn.UserId = rap.OwnerUserId
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS VotesCast
    FROM Votes
    GROUP BY PostId
  ) vs ON vs.PostId = rap.PostId
)
SELECT
  c.PostId,
  c.PostTypeId,
  pt.Name AS PostTypeName,
  c.Title,
  c.Tags,
  c.CreationDate,
  c.LastActivityDate,
  c.Score,
  c.ViewCount,
  c.AnswerCount,
  c.CommentCount,
  c.FavoriteCount,
  c.ContentLicense,
  c.Body,
  c.ParentId,
  c.AcceptedAnswerId,
  c.OwnerUserId,
  c.DisplayName,
  c.Reputation,
  c.GoldBadges,
  c.SilverBadges,
  c.BronzeBadges,
  c.VotesCast,
  ROW_NUMBER() OVER (
    PARTITION BY CAST(c.CreationDate AS DATE)
    ORDER BY c.Score DESC NULLS LAST, c.ViewCount DESC NULLS LAST
  ) AS RankForDay,
  (
    SELECT SUM(cc.Score)
    FROM Comments cc
    WHERE cc.PostId = c.PostId
  ) AS TotalCommentScore,
  NULL AS PlaceholderForSetOp
FROM Combined c
JOIN PostTypes pt ON pt.Id = c.PostTypeId
GROUP BY
  c.PostId,
  c.PostTypeId,
  pt.Name,
  c.Title,
  c.Tags,
  c.CreationDate,
  c.LastActivityDate,
  c.Score,
  c.ViewCount,
  c.AnswerCount,
  c.CommentCount,
  c.FavoriteCount,
  c.ContentLicense,
  c.Body,
  c.ParentId,
  c.AcceptedAnswerId,
  c.OwnerUserId,
  c.DisplayName,
  c.Reputation,
  c.GoldBadges,
  c.SilverBadges,
  c.BronzeBadges,
  c.VotesCast,
  CAST(c.CreationDate AS DATE)
ORDER BY c.CreationDate DESC, c.Score DESC NULLS LAST;