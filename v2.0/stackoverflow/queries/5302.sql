-- {"query": "5302.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 696}
WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days'
),
TopUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC) AS rn
  FROM Users u
),
UserBadges AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgeCount,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges
  FROM Badges b
  GROUP BY b.UserId
),
PostHistorySummary AS (
  SELECT
    ph.PostId,
    ph.PostHistoryTypeId,
    MAX(ph.CreationDate) AS LastHistoryDate,
    STRING_AGG(CAST(ph.PostHistoryTypeId AS varchar), ',' ORDER BY ph.CreationDate) AS HistoryTypes
  FROM PostHistory ph
  GROUP BY ph.PostId, ph.PostHistoryTypeId
),
LinkedPosts AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
),
TaggedTrend AS (
  SELECT
    t.Id AS TagId,
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    (SELECT p.CreationDate FROM Posts p WHERE p.Id = t.ExcerptPostId) AS ExcerptCreated
  FROM Tags t
  WHERE t.Count > 100
)
SELECT
  rp.PostId,
  rp.PostTypeId,
  pt.Name AS PostTypeName,
  rp.CreationDate AS PostCreationDate,
  rp.LastActivityDate,
  rp.Title,
  rp.Tags,
  rp.Score,
  rp.ViewCount,
  ru.UserId AS OwnerUserId,
  ru.DisplayName AS OwnerDisplayName,
  ru.Reputation AS OwnerReputation,
  ub.BadgeCount,
  ub.GoldBadges,
  hts.HistoryTypes,
  gh.RelatedPostId AS LinkedToPost,
  hts.LastHistoryDate,
  wb.TagName AS TopTag
FROM RecentActivePosts rp
LEFT JOIN TopUsers ru ON rp.OwnerUserId = ru.UserId
LEFT JOIN UserBadges ub ON ru.UserId = ub.UserId
LEFT JOIN PostHistorySummary hts ON rp.PostId = hts.PostId
LEFT JOIN LinkedPosts gh ON rp.PostId = gh.PostId
LEFT JOIN TaggedTrend wb ON rp.Tags LIKE '%' || wb.TagName || '%'
LEFT JOIN PostTypes pt ON rp.PostTypeId = pt.Id
ORDER BY rp.LastActivityDate DESC, rp.Score DESC
LIMIT 200;