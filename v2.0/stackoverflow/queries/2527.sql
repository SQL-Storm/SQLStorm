-- {"query": "2527.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1119}
WITH RECURSIVE RecursivePostHierarchy AS (
    SELECT p.Id, p.PostTypeId, p.ParentId, p.AcceptedAnswerId, p.CreationDate, p.Score, p.ViewCount,
           p.OwnerUserId, p.Title, p.Tags, 0 AS Depth
    FROM Posts p
    WHERE p.PostTypeId = 1
    UNION ALL
    SELECT c.Id, c.PostTypeId, c.ParentId, c.AcceptedAnswerId, c.CreationDate, c.Score, c.ViewCount,
           c.OwnerUserId, c.Title, c.Tags, r.Depth + 1
    FROM Posts c
    JOIN RecursivePostHierarchy r ON c.ParentId = r.Id
), UserBadgeStats AS (
    SELECT b.UserId,
           COUNT(*) AS TotalBadges,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
           COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
           COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
           MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
), PostScoreWindow AS (
    SELECT p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.ViewCount,
           ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByScore,
           AVG(p.Score) OVER (PARTITION BY p.PostTypeId) AS AvgScore,
           SUM(p.ViewCount) OVER () AS TotalViewsAllPosts
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
), LatestUserActivity AS (
    SELECT u.Id AS UserId, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.WebsiteUrl,
           MAX(ph.CreationDate) AS LastPostEdit,
           MAX(c.CreationDate) AS LastCommentDate
    FROM Users u
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.WebsiteUrl
), DuplicateLinks AS (
    SELECT pl.PostId, pl.RelatedPostId, pl.CreationDate
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE lt.Name = 'Duplicate'
), TopTagsByPostCount AS (
    SELECT t.TagName, t.Count,
           DENSE_RANK() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.Count IS NOT NULL
)
SELECT 
    rp.Depth,
    rp.Id AS PostId,
    rp.PostTypeId,
    rp.Title,
    COALESCE(u.DisplayName, CAST(rp.OwnerUserId AS VARCHAR), 'Anonymous') AS OwnerName,
    u.Reputation,
    us.TotalBadges, us.GoldBadges, us.SilverBadges, us.BronzeBadges,
    rp.Score,
    rp.ViewCount,
    psw.RankByScore,
    psw.AvgScore,
    psw.TotalViewsAllPosts,
    la.LastPostEdit,
    la.LastCommentDate,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM DuplicateLinks dl WHERE dl.PostId = rp.Id
        ) THEN 'HasDuplicates' ELSE 'NoDuplicates' END AS DuplicateStatus,
    STRING_AGG(DISTINCT tt.TagName, ', ') AS Top5Tags,
    CASE 
        WHEN rp.Tags IS NULL OR LENGTH(rp.Tags) = 0 THEN 'NoTags'
        ELSE
            UPPER(
                REPLACE(
                    SUBSTRING(rp.Tags FROM 2 FOR LENGTH(rp.Tags) - 2),
                    '><', ', '
                )
            )
    END AS CleanedTags,
    (
      SELECT COUNT(*) 
      FROM PostHistory ph2 
      WHERE ph2.PostId = rp.Id AND ph2.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY)
    ) AS RecentEditCount,
    ROW_NUMBER() OVER (
        PARTITION BY rp.OwnerUserId
        ORDER BY rp.Score DESC NULLS LAST, rp.ViewCount DESC NULLS LAST
    ) AS UserPostRank
FROM RecursivePostHierarchy rp
LEFT JOIN Users u ON u.Id = rp.OwnerUserId
LEFT JOIN UserBadgeStats us ON us.UserId = u.Id
LEFT JOIN PostScoreWindow psw ON psw.Id = rp.Id
LEFT JOIN LatestUserActivity la ON la.UserId = u.Id
LEFT JOIN Tags tt ON tt.TagName IN (
    -- split tags expressed like '<tag1><tag2>' into individual tag names
    SELECT TRIM(x) FROM (
        SELECT UNNEST(string_to_array(SUBSTRING(rp.Tags FROM 2 FOR GREATEST(LENGTH(rp.Tags) - 2,0)), '><')) AS x
    )
)
WHERE rp.Depth <= 3
  AND (rp.Score > COALESCE(
      (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.PostTypeId = rp.PostTypeId), 0))
  AND (u.Reputation IS NULL OR u.Reputation > 1000)
GROUP BY
    rp.Depth, rp.Id, rp.PostTypeId, rp.Title, rp.OwnerUserId, u.DisplayName, u.Reputation,
    us.TotalBadges, us.GoldBadges, us.SilverBadges, us.BronzeBadges,
    rp.Score, rp.ViewCount, psw.RankByScore, psw.AvgScore, psw.TotalViewsAllPosts,
    la.LastPostEdit, la.LastCommentDate, rp.Tags
ORDER BY rp.Depth, rp.Score DESC, rp.ViewCount DESC
LIMIT 100;