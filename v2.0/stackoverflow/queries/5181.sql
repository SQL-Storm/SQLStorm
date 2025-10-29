-- {"query": "5181.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 899}
WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Body,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.PostTypeId,
    u.Reputation,
    u.DisplayName,
    u.Location,
    u.WebsiteUrl,
    u.AccountId,
    u.CreationDate AS UserCreationDate,
    b.Name AS BadgeName,
    b.Date AS BadgeDate,
    b.Class AS BadgeClass,
    ht.Name AS HistoryTypeName,
    pt.Name AS PostTypeName,
    lt.Name AS LinkTypeName,
    ROW_NUMBER() OVER (
      PARTITION BY p.Id
      ORDER BY p.LastActivityDate DESC NULLS LAST, p.CreationDate DESC
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  LEFT JOIN PostHistoryTypes ht ON ph.PostHistoryTypeId = ht.Id
  LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE
    p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
    AND (p.ViewCount IS NULL OR p.ViewCount > 0)
    AND (p.Score IS NULL OR p.Score > 0)
),
Agg AS (
  SELECT
    PostId,
    MAX(Score) AS MaxScore,
    SUM(ViewCount) AS TotalViews,
    COUNT(*) AS PostCount,
    COUNT(DISTINCT OwnerUserId) AS DistinctOwners,
    MAX(rn) AS MaxRownum
  FROM RankedPosts
  GROUP BY PostId
),
Windowed AS (
  SELECT
    r.PostId,
    r.Title,
    r.Body,
    r.CreationDate,
    r.ViewCount,
    r.Score,
    r.OwnerUserId,
    r.Tags,
    r.LastActivityDate,
    r.CommentCount,
    r.AnswerCount,
    r.FavoriteCount,
    r.PostTypeId,
    r.Reputation,
    r.DisplayName,
    r.Location,
    r.WebsiteUrl,
    r.AccountId,
    r.UserCreationDate,
    r.BadgeName,
    r.BadgeDate,
    r.BadgeClass,
    r.HistoryTypeName,
    r.PostTypeName,
    r.LinkTypeName,
    r.rn,
    a.TotalViews,
    a.PostCount,
    a.DistinctOwners,
    a.MaxScore,
    a.MaxRownum
  FROM RankedPosts r
  JOIN Agg a ON r.PostId = a.PostId
  WHERE r.rn = 1
),
FinalAgg AS (
  SELECT
    w.PostTypeId,
    w.PostTypeName,
    w.PostId,
    w.Title,
    w.Tags,
    w.ViewCount,
    w.Score,
    w.CreationDate,
    w.LastActivityDate,
    w.OwnerUserId,
    w.DisplayName AS OwnerDisplayName,
    w.Reputation,
    w.Location,
    w.WebsiteUrl,
    w.AnswerCount,
    w.CommentCount,
    w.FavoriteCount,
    ARRAY_AGG(DISTINCT w.BadgeName) FILTER (WHERE w.BadgeName IS NOT NULL) AS BadgeNames,
    MAX(CASE WHEN w.BadgeClass = 1 THEN w.BadgeDate END) AS GoldBadgeDate,
    MAX(CASE WHEN w.BadgeClass = 2 THEN w.BadgeDate END) AS SilverBadgeDate,
    MAX(CASE WHEN w.BadgeClass = 3 THEN w.BadgeDate END) AS BronzeBadgeDate,
    MAX(w.HistoryTypeName) AS LastHistoryTypeName
  FROM Windowed w
  LEFT JOIN Badges b ON b.UserId = w.OwnerUserId  -- include badges to aggregate across user if desired
  LEFT JOIN PostHistory ph ON ph.PostId = w.PostId
  LEFT JOIN PostHistoryTypes ht ON ph.PostHistoryTypeId = ht.Id
  GROUP BY
    w.PostTypeId, w.PostTypeName, w.PostId, w.Title, w.Tags, w.ViewCount, w.Score, w.CreationDate,
    w.LastActivityDate, w.OwnerUserId, w.DisplayName, w.Reputation, w.Location, w.WebsiteUrl,
    w.AnswerCount, w.CommentCount, w.FavoriteCount
)
SELECT
  PostId,
  PostTypeName,
  Title,
  Tags,
  CreationDate,
  LastActivityDate,
  OwnerDisplayName,
  Reputation,
  Location,
  WebsiteUrl,
  ViewCount,
  Score,
  AnswerCount,
  CommentCount,
  FavoriteCount,
  BadgeNames,
  GoldBadgeDate,
  SilverBadgeDate,
  BronzeBadgeDate,
  LastHistoryTypeName
FROM FinalAgg
ORDER BY LastActivityDate DESC
LIMIT 100;