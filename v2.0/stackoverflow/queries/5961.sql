-- {"query": "5961.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1175}
WITH
TopUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
  WHERE u.Reputation > 1000
),
UserPosts AS (
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
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId,
    p.Body,
    pg.Name AS PostHistoryTypeName,
    vh.CreationDate AS VoteDate,
    vt.Name AS VoteTypeName,
    u.DisplayName AS OwnerDisplayName
  FROM Posts p
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  LEFT JOIN PostHistoryTypes pg ON ph.PostHistoryTypeId = pg.Id
  LEFT JOIN Votes vh ON vh.PostId = p.Id
  LEFT JOIN VoteTypes vt ON vh.VoteTypeId = vt.Id
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  WHERE p.OwnerUserId IN (SELECT UserId FROM TopUsers)
    AND p.CreationDate >= TIMESTAMP '2020-01-01'
),
UserStats AS (
  SELECT
    up.OwnerUserId,
    up.OwnerDisplayName,
    up.PostTypeId,
    up.Title,
    up.Tags,
    up.CreationDate,
    up.LastActivityDate,
    up.Score,
    up.ViewCount,
    up.CommentCount,
    up.AnswerCount,
    up.FavoriteCount,
    (SELECT COUNT(*) FROM Posts pt
     WHERE pt.OwnerUserId = up.OwnerUserId
       AND pt.CreationDate < up.CreationDate) AS PriorPostCount,
    (CASE
       WHEN up.Tags IS NOT NULL THEN
         (LENGTH(up.Tags) - LENGTH(REPLACE(up.Tags, '><', ''))) / 4
       ELSE 0
     END) AS TagDensity,
    EXTRACT(EPOCH FROM (up.LastActivityDate - COALESCE((SELECT MAX(LastEditDate) FROM Posts WHERE Id = up.PostId), up.CreationDate))) AS ActivitySpanSecs,
    up.PostId
  FROM UserPosts up
),
UserBadges AS (
  SELECT
    us.OwnerUserId,
    b.Name AS BadgeName,
    b.Class,
    b.Date,
    b.TagBased,
    ROW_NUMBER() OVER (PARTITION BY us.OwnerUserId ORDER BY b.Date DESC) AS rn
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN UserStats us ON us.OwnerUserId = u.Id
  WHERE u.Id IS NOT NULL
),
Final AS (
  SELECT
    t.UserId,
    t.DisplayName,
    t.Reputation,
    t.rn AS SeedRank,
    s.PostId,
    s.PostTypeId,
    s.Title,
    s.Tags,
    s.CreationDate,
    s.LastActivityDate,
    s.Score,
    s.ViewCount,
    s.CommentCount,
    s.AnswerCount,
    s.FavoriteCount,
    s.PriorPostCount,
    s.TagDensity,
    s.ActivitySpanSecs,
    b.BadgeName,
    b.Class,
    b.Date AS BadgeDate,
    b.TagBased,
    CASE
      WHEN b.BadgeName IS NOT NULL THEN
        CASE WHEN s.CreationDate > b.Date THEN TRUE ELSE FALSE END
      ELSE NULL
    END AS PostAfterBadge
  FROM TopUsers t
  LEFT JOIN UserStats s ON s.OwnerUserId = t.UserId
  LEFT JOIN UserBadges b ON b.OwnerUserId = t.UserId
  WHERE t.rn <= 100
    AND EXISTS (
      SELECT 1
      FROM Comments c
      WHERE c.PostId = s.PostId
        AND c.UserId IS NULL
    )
    AND (
      (s.PostTypeId = 1 AND s.Score > 5)
      OR
      (s.PostTypeId = 2 AND s.ViewCount > 100)
    )
  ORDER BY t.Reputation DESC, s.LastActivityDate DESC
)
SELECT
  UserId,
  DisplayName,
  Reputation,
  SeedRank,
  PostId,
  PostTypeId,
  Title,
  Tags,
  CreationDate,
  LastActivityDate,
  Score,
  ViewCount,
  CommentCount,
  AnswerCount,
  FavoriteCount,
  PriorPostCount,
  TagDensity,
  ActivitySpanSecs,
  BadgeName,
  Class,
  BadgeDate,
  TagBased,
  PostAfterBadge
FROM Final
ORDER BY Reputation DESC, SeedRank ASC, LastActivityDate DESC
LIMIT 500;