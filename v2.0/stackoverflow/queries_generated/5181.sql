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
      ORDER BY p.LastActivityDate DESC_NULLS_LAST, p.CreationDate DESC
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
    p.CreationDate >= NOW() - INTERVAL '90 days'
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
    r.*,
    a.TotalViews,
    a.PostCount,
    a.DistinctOwners,
    a.MaxScore,
    a.MaxRownum
  FROM RankedPosts r
  JOIN Agg a ON r.PostId = a.PostId
  WHERE r.rn = 1
),
Final AS (
  SELECT
    p.PostTypeId,
    pt.Name AS PostTypeName,
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.Location,
    u.WebsiteUrl,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    ARRAY_AGG(DISTINCT CASE WHEN b.Name IS NOT NULL THEN b.Name END) FILTER (WHERE b.Name IS NOT NULL) AS BadgeNames,
    MAX(CASE WHEN b.Class = 1 THEN b.Date END) AS GoldBadgeDate,
    MAX(CASE WHEN b.Class = 2 THEN b.Date END) AS SilverBadgeDate,
    MAX(CASE WHEN b.Class = 3 THEN b.Date END) AS BronzeBadgeDate,
    MAX(CASE WHEN ht.Name IS NOT NULL THEN ht.Name END) AS LastHistoryTypeName
  FROM Final
  GROUP BY
    p.PostTypeId, pt.Name, p.Id, p.Title, p.Tags, p.ViewCount, p.Score, p.CreationDate,
    p.LastActivityDate, p.OwnerUserId, u.DisplayName, u.Reputation, u.Location, u.WebsiteUrl,
    p.AnswerCount, p.CommentCount, p.FavoriteCount
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
FROM Final
ORDER BY LastActivityDate DESC
LIMIT 100;