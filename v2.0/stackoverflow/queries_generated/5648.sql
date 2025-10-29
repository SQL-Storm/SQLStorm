-- {"query": "5648.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 828} 
WITH
RecentPopularQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.OwnerDisplayName,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_by_user
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= CURRENT_DATE - INTERVAL '180 days'
),
TagPopularity AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews
  FROM Posts p
  JOIN unnest(string_to_array(p.Tags, '>')) AS t1(tag) ON true
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
UserBadges AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
    COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
    COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
    MAX(b.Date) AS LastBadgeDate
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
TopActivity AS (
  SELECT
    p.PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM RecentPopularQuestions p
  LEFT JOIN Votes v ON v.PostId = p.PostId
  GROUP BY p.PostId, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount
)
SELECT
  t.PostId,
  t.Title AS QuestionTitle,
  t.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  t.CreationDate AS QuestionCreationDate,
  t.Score AS QuestionScore,
  t.ViewCount AS QuestionViews,
  COALESCE(vp.UpvoteCount, 0) AS Upvotes,
  COALESCE(vp.DownvoteCount, 0) AS Downvotes,
  pc.LastBadgeDate,
  ba.GoldBadges,
  ba.SilverBadges,
  ba.BronzeBadges,
  tg.TagName AS TopTag,
  tg.TagCount,
  tg.AvgScore AS TagAvgScore,
  tg.TotalViews AS TagTotalViews,
  CASE
    WHEN t.rn_by_user = 1 THEN 'First of user'
    ELSE 'Subsequent'
  END AS UserActivityTier
FROM TopActivity t
JOIN Users u ON u.Id = t.OwnerUserId
LEFT JOIN (
  SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
         SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount
  FROM Votes
  GROUP BY PostId
) vp ON vp.PostId = t.PostId
LEFT JOIN UserBadges ba ON ba.UserId = t.OwnerUserId
LEFT JOIN (
  SELECT
    unnest(string_to_array(LOWER(p.Tags), '>')) AS TagName,
    COUNT(*) AS TagCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews
  FROM Posts p
  WHERE p.PostTypeId = 1
  GROUP BY TagName
  ORDER BY TagCount DESC
  LIMIT 1
) tg ON true
ORDER BY t.Score DESC, t.ViewCount DESC
LIMIT 100;