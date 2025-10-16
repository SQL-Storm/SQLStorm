WITH
ActivePosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.Body,
    p.ContentLicense,
    p.OwnerDisplayName
  FROM Posts p
  WHERE p.PostTypeId IN (1,2)
),
UserStats AS (
  SELECT
    u.Id,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.DisplayName,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.WebsiteUrl,
    u.ProfileImageUrl,
    u.AccountId,
    COUNT(b.Id) AS BadgesCount,
    MAX(b.Date) AS LatestBadgeDate,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY
    u.Id, u.Reputation, u.CreationDate, u.LastAccessDate, u.DisplayName,
    u.Views, u.UpVotes, u.DownVotes, u.Location, u.WebsiteUrl, u.ProfileImageUrl,
    u.AccountId
),
TagUsage AS (
  SELECT
    t.TagName,
    t.Count AS TagCount,
    t.ExcerptPostId,
    t.WikiPostId,
    t.IsModeratorOnly,
    t.IsRequired
  FROM Tags t
),
RecentComments AS (
  SELECT
    c.PostId,
    AVG(CASE WHEN c.Score IS NULL THEN 0 ELSE c.Score END) AS AvgCommentScore,
    COUNT(*) AS CommentCount,
    MAX(c.CreationDate) AS LastCommentDate
  FROM Comments c
  GROUP BY c.PostId
),
LinkRank AS (
  SELECT
    pl.PostId,
    COUNT(*) AS LinkedCount,
    SUM(CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateCount
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  GROUP BY pl.PostId
),
VoteActivity AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId IN (2,14,16) THEN 1 ELSE 0 END) AS PositiveVotes,
    SUM(CASE WHEN v.VoteTypeId IN (3,10,11,12) THEN 1 ELSE 0 END) AS NegativeVotes,
    MAX(v.CreationDate) AS LastVoteDate,
    SUM(CASE WHEN v.BountyAmount IS NOT NULL THEN v.BountyAmount ELSE 0 END) AS BountySum
  FROM Votes v
  GROUP BY v.PostId
),
Combined AS (
  SELECT
    a.Id AS PostId,
    a.PostTypeId,
    a.OwnerUserId,
    a.Title,
    a.Tags,
    a.Score,
    a.ViewCount,
    a.CreationDate,
    a.LastActivityDate,
    a.CommentCount,
    a.AnswerCount,
    a.FavoriteCount,
    a.ParentId,
    a.AcceptedAnswerId,
    a.LastEditorUserId,
    a.LastEditDate,
    a.Body,
    a.ContentLicense,
    a.OwnerDisplayName,
    up.Reputation AS OwnerReputation,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.LatestBadgeDate,
    rc.AvgCommentScore,
    rc.CommentCount AS CommentTotal,
    rc.LastCommentDate,
    lk.LinkedCount,
    lk.DuplicateCount,
    va.PositiveVotes,
    va.NegativeVotes,
    va.LastVoteDate,
    va.BountySum
  FROM ActivePosts a
  LEFT JOIN UserStats ub ON ub.Id = a.OwnerUserId
  LEFT JOIN RecentComments rc ON rc.PostId = a.Id
  LEFT JOIN LinkRank lk ON lk.PostId = a.Id
  LEFT JOIN VoteActivity va ON va.PostId = a.Id
  LEFT JOIN Users up ON up.Id = a.OwnerUserId
)
SELECT
  PostId,
  PostTypeId,
  COALESCE(OwnerUserId, -1) AS OwnerUserId,
  Title,
  Tags,
  Score,
  ViewCount,
  CreationDate,
  LastActivityDate,
  CommentCount,
  COALESCE(AnswerCount, 0) AS AnswerCount,
  COALESCE(FavoriteCount, 0) AS FavoriteCount,
  COALESCE(ParentId, 0) AS ParentId,
  COALESCE(AcceptedAnswerId, 0) AS AcceptedAnswerId,
  COALESCE(LastEditorUserId, -1) AS LastEditorUserId,
  LastEditDate,
  Body,
  ContentLicense,
  OwnerDisplayName,
  OwnerReputation,
  GoldBadges,
  SilverBadges,
  BronzeBadges,
  LatestBadgeDate,
  AvgCommentScore,
  CommentTotal,
  LastCommentDate,
  LinkedCount,
  DuplicateCount,
  PositiveVotes,
  NegativeVotes,
  LastVoteDate,
  BountySum
FROM Combined
ORDER BY LastActivityDate DESC
LIMIT 200;