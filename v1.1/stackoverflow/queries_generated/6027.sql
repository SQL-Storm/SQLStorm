-- {"query": "6027.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 807} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.PostTypeId,
    p.Tags,
    p.LastActivityDate,
    p.CommentCount,
    p.FavoriteCount,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.DeletionDate IS NULL OR p.DeletionDate IS NULL -- placeholder to ensure syntax validity if column existed
),
TopQuestions AS (
  SELECT
    rap.Id,
    rap.Title,
    rap.OwnerUserId,
    rap.CreationDate,
    rap.ViewCount,
    rap.Score,
    rap.Tags,
    rap.LastActivityDate,
    rap.CommentCount,
    rap.FavoriteCount
  FROM RecentActivePosts rap
  JOIN PostTypes pt ON pt.Id = rap.PostTypeId
  WHERE rap.PostTypeId = 1
    AND rap.rn <= 100
),
UserStatistics AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
PostLinkActivity AS (
  SELECT
    pl.PostId,
    COUNT(*) AS LinkCount,
    MAX(pl.CreationDate) AS LastLinkDate
  FROM PostLinks pl
  GROUP BY pl.PostId
),
TagUsage AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagUsageCount
  FROM Tags t
  GROUP BY t.TagName
),
Combined AS (
  SELECT
    q.Id AS QuestionId,
    q.Title,
    q.OwnerUserId,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    q.Tags,
    q.LastActivityDate,
    q.CommentCount,
    q.FavoriteCount,
    us.UserId,
    us.DisplayName AS UserDisplayName,
    us.Reputation,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    COALESCE(pla.LinkCount, 0) AS LinkCount,
    COALESCE(ta.TagUsageCount, 0) AS RelatedTagCount
  FROM TopQuestions q
  LEFT JOIN UserStatistics us ON us.UserId = q.OwnerUserId
  LEFT JOIN PostLinkActivity pla ON pla.PostId = q.Id
  LEFT JOIN Tags t ON t.Id LIKE '%' || '' || '%' -- placeholder to engage tag handling
  LEFT JOIN TagUsage ta ON ta.TagName = (SELECT unnest(string_to_array(replace(q.Tags, '><', ','), ',') LIMIT 1))
)
SELECT
  QuestionId,
  Title,
  UserDisplayName,
  Reputation,
  CreationDate,
  LastActivityDate,
  ViewCount,
  Score,
  Tags,
  CommentCount,
  FavoriteCount,
  LinkCount,
  RelatedTagCount,
  GoldBadges,
  SilverBadges,
  BronzeBadges
FROM Combined
ORDER BY LastActivityDate DESC
LIMIT 200;