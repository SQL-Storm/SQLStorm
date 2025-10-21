-- {"query": "321.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 31657} 
WITH
ActiveUsers AS (
  SELECT
    u.Id AS UserId,
    INITCAP(COALESCE(u.DisplayName, '')) AS DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    COALESCE(ps.PostsCount, 0) AS PostsCount,
    COALESCE(ps.TotalPostScore, 0) AS TotalPostScore,
    COALESCE(gb.GoldBadges, 0) AS GoldBadges,
    COALESCE(sb.SilverBadges, 0) AS SilverBadges,
    COALESCE(bb.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(tt.DistinctTagsUsed, 0) AS DistinctTagsUsed,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS UserCommentCount
  FROM Users u
  LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) AS PostsCount, COALESCE(SUM(Score), 0) AS TotalPostScore
    FROM Posts
    GROUP BY OwnerUserId
  ) ps ON ps.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS GoldBadges
    FROM Badges
    WHERE Class = 1
    GROUP BY UserId
  ) gb ON gb.UserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS SilverBadges
    FROM Badges
    WHERE Class = 2
    GROUP BY UserId
  ) sb ON sb.UserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS BronzeBadges
    FROM Badges
    WHERE Class = 3
    GROUP BY UserId
  ) bb ON bb.UserId = u.Id
  LEFT JOIN (
    SELECT p.OwnerUserId AS UserId,
           COUNT(DISTINCT t.TagName) AS DistinctTagsUsed
    FROM Posts p
    LEFT JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS t(TagName) ON true
    GROUP BY p.OwnerUserId
  ) tt ON tt.UserId = u.Id
  WHERE u.LastAccessDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
),
AllUsers AS (
  SELECT
    u.Id AS UserId,
    INITCAP(COALESCE(u.DisplayName, '')) AS DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    COALESCE(ps.PostsCount, 0) AS PostsCount,
    COALESCE(ps.TotalPostScore, 0) AS TotalPostScore,
    COALESCE(gb.GoldBadges, 0) AS GoldBadges,
    COALESCE(sb.SilverBadges, 0) AS SilverBadges,
    COALESCE(bb.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(tt.DistinctTagsUsed, 0) AS DistinctTagsUsed,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS UserCommentCount
  FROM Users u
  LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) AS PostsCount, COALESCE(SUM(Score), 0) AS TotalPostScore
    FROM Posts
    GROUP BY OwnerUserId
  ) ps ON ps.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS GoldBadges
    FROM Badges
    WHERE Class = 1
    GROUP BY UserId
  ) gb ON gb.UserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS SilverBadges
    FROM Badges
    WHERE Class = 2
    GROUP BY UserId
  ) sb ON sb.UserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS BronzeBadges
    FROM Badges
    WHERE Class = 3
    GROUP BY UserId
  ) bb ON bb.UserId = u.Id
  LEFT JOIN (
    SELECT p.OwnerUserId AS UserId,
           COUNT(DISTINCT t.TagName) AS DistinctTagsUsed
    FROM Posts p
    LEFT JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS t(TagName) ON true
    GROUP BY p.OwnerUserId
  ) tt ON tt.UserId = u.Id
)
SELECT
  m.UserId,
  m.DisplayName,
  m.Reputation,
  m.CreationDate,
  m.LastAccessDate,
  m.PostsCount,
  m.GoldBadges,
  m.SilverBadges,
  m.BronzeBadges,
  m.DistinctTagsUsed,
  m.TotalPostScore,
  m.UserCommentCount,
  (m.TotalPostScore + m.Reputation + m.DistinctTagsUsed * 5.0) AS Score,
  CASE
    WHEN m.Reputation > 5000 OR m.TotalPostScore > 10000 THEN 'Elite'
    WHEN m.DistinctTagsUsed > 30 THEN 'Tag Master'
    ELSE 'Standard'
  END AS Status,
  ROW_NUMBER() OVER (ORDER BY (m.TotalPostScore + m.Reputation + m.DistinctTagsUsed * 5.0) DESC) AS Rank
FROM (
  SELECT * FROM ActiveUsers
  UNION ALL
  SELECT * FROM AllUsers
  WHERE LastAccessDate <= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
) AS m
ORDER BY Rank
LIMIT 200;