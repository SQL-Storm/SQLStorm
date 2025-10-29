-- {"query": "5484.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 728}
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.AnswerCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days'
),
TopTags AS (
  SELECT
    t.TagName,
    SUM(r.Score) AS ScoreSum,
    AVG(r.ViewCount) AS AvgViews,
    COUNT(*) AS PostCount
  FROM RecentActivePosts r,
       LATERAL (
         SELECT unnest(string_to_array(substring(r.Tags, 2, length(r.Tags)-2), '><')) AS TagName
       ) t
  GROUP BY t.TagName
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
    COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
    SUM(p.ViewCount) AS TotalViews,
    SUM(p.Score) AS TotalScore,
    MIN(p.CreationDate) AS FirstPostDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  WHERE u.CreationDate <= CAST('2024-10-01 12:34:56' AS timestamp)
  GROUP BY u.Id, u.DisplayName
),
BadgeContribution AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgesEarned,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Badges b
  GROUP BY b.UserId
),
Combined AS (
  SELECT
    r.Id AS PostId,
    r.Title,
    r.CreationDate,
    r.OwnerUserId,
    r.PostTypeId,
    r.Score,
    r.ViewCount,
    r.Tags,
    r.LastActivityDate,
    r.AnswerCount,
    r.FavoriteCount,
    u.DisplayName AS OwnerDisplayName,
    hu.TotalViews AS OwnerTotalViews,
    ht.ScoreSum AS TagScore,
    hb.BadgesEarned,
    hb.GoldBadges,
    hb.SilverBadges,
    hb.BronzeBadges
  FROM RecentActivePosts r
  LEFT JOIN Users u ON u.Id = r.OwnerUserId
  LEFT JOIN UserActivity hu ON hu.UserId = u.Id
  LEFT JOIN (
    SELECT TagName, SUM(ScoreSum) AS ScoreSum
    FROM TopTags
    GROUP BY TagName
  ) ht ON true
  LEFT JOIN BadgeContribution hb ON hb.UserId = u.Id
)
SELECT
  c.PostId,
  c.Title,
  c.CreationDate,
  c.OwnerUserId,
  c.OwnerDisplayName,
  c.PostTypeId,
  c.Score,
  c.ViewCount,
  c.Tags,
  c.LastActivityDate,
  c.AnswerCount,
  c.FavoriteCount,
  c.OwnerTotalViews,
  c.TagScore,
  c.BadgesEarned,
  c.GoldBadges,
  c.SilverBadges,
  c.BronzeBadges
FROM Combined c
ORDER BY
  c.LastActivityDate DESC
LIMIT 100;