-- {"query": "5595.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1067} 
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
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '30 days'
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count AS TagPopularity,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.Count > 1000
),
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.Location,
    u.EmailHash,
    u.AccountId,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) AS PostCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS CommentCount
  FROM Users u
),
BadgeSummary AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgeCount,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Badges b
  GROUP BY b.UserId
),
ActivityRank AS (
  SELECT
    up.UserId,
    up.DisplayName,
    up.Reputation,
    up.PostCount,
    up.CommentCount,
    bs.BadgeCount,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    ROW_NUMBER() OVER (
      PARTITION BY up.UserId
      ORDER BY
        up.Reputation DESC,
        up.PostCount DESC,
        bs.BadgeCount DESC,
        up.LastAccessDate DESC
    ) AS rn
  FROM UserStats up
  LEFT JOIN BadgeSummary bs ON bs.UserId = up.UserId
),
ComplexDerived AS (
  SELECT
    ar.*,
    -- compute a composite activity score with NULL-safe logic and some string expressions
    (COALESCE(ar.Reputation,0) * 0.6
     + COALESCE(ar.PostCount,0) * 2.0
     + COALESCE(ar.CommentCount,0) * 1.5
     + COALESCE(ar.BadgeCount,0) * 5.0) AS ActivityScore,
    -- windowed rank over ActivityScore within the last 90 days of posts
    SUM(CASE WHEN p.CreationDate >= NOW() - INTERVAL '90 days' THEN 1 ELSE 0 END) OVER (
      ORDER BY
        (COALESCE(ar.Reputation,0) * 0.6
         + COALESCE(ar.PostCount,0) * 2.0
         + COALESCE(ar.CommentCount,0) * 1.5
         + COALESCE(ar.BadgeCount,0) * 5.0) DESC
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS Running90dPulse
  FROM ActivityRank ar
  LEFT JOIN RecentActivePosts p ON p.OwnerUserId = ar.UserId
)
SELECT
  u.UserId,
  u.DisplayName,
  u.Reputation,
  u.UserCreationDate,
  u.LastAccessDate,
  u.Views,
  u.UpVotes,
  u.DownVotes,
  u.Location,
  u.EmailHash,
  u.AccountId,
  a.ActivityScore,
  a.Running90dPulse,
  CONCAT('[', STRING_AGG(DISTINCT t.TagName, ', '), ']') AS TopTagsSnapshot,
  -- nested cross-join style detail: gather recent post titles with correlated subquery
  (SELECT STRING_AGG(p.Title, ' | ')
     FROM Posts p
     WHERE p.OwnerUserId = u.UserId
       AND p.CreationDate >= NOW() - INTERVAL '7 days'
  ) AS RecentPostTitles,
  -- NULL-safe calculation: average views-per-post with null handling
  CASE WHEN NULLIF(u.Views, NULL) IS NULL OR (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.UserId) = 0
       THEN NULL
       ELSE u.Views / NULLIF((SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.UserId), 0)
  END AS AvgViewsPerPost
FROM ComplexDerived a
JOIN Users u ON u.Id = a.UserId
ORDER BY a.ActivityScore DESC
LIMIT 100;