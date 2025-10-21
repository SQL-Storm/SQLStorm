WITH GoldBadgeUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id) AS GoldBadgeCount,
        STRING_AGG(b.Name, ', ') AS GoldBadges
    FROM Users u
    INNER JOIN Badges b ON u.Id = b.UserId
    WHERE CAST(b.Class AS INTEGER) = 1 AND CAST(b.TagBased AS INTEGER) = 1
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(b.Id) >= 2
),
TopQuestions AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.ViewCount,
        p.Score,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC) AS ViewRank,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgScore
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ViewCount > 1000
),
UserActivity AS (
    SELECT 
        gbu.UserId,
        gbu.DisplayName,
        gbu.Reputation,
        gbu.GoldBadgeCount,
        gbu.GoldBadges,
        tq.PostId,
        tq.Title,
        tq.ViewCount,
        tq.Score,
        tq.AvgScore,
        (SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = tq.PostId AND c.Score > 0) AS PositiveComments,
        COALESCE((SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = tq.PostId AND v.VoteTypeId = 2), tq.CreationDate) AS LastUpvoteDate
    FROM GoldBadgeUsers gbu
    LEFT OUTER JOIN TopQuestions tq ON gbu.UserId = tq.OwnerUserId AND tq.ViewRank <= 3
    WHERE gbu.Reputation > 10000 OR tq.PostId IS NULL
),
TagAnalysis AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalFavorites
    FROM Tags t
    LEFT OUTER JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.Id, t.TagName
    HAVING SUM(COALESCE(p.FavoriteCount, 0)) > 500
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.GoldBadgeCount,
    ua.GoldBadges,
    ua.PostId,
    ua.Title,
    ua.ViewCount,
    ua.Score,
    ua.AvgScore,
    ua.PositiveComments,
    ua.LastUpvoteDate,
    CASE 
        WHEN ua.ViewCount IS NULL THEN 'No Top Questions'
        WHEN ua.ViewCount > 10000 THEN UPPER(ua.Title) || ' (High Views)'
        ELSE LOWER(ua.Title) || ' (Moderate Views)'
    END AS ProcessedTitle,
    (SELECT COUNT(ph.Id) FROM PostHistory ph WHERE ph.PostId = ua.PostId AND ph.PostHistoryTypeId IN (4,5,6) AND ph.CreationDate > ua.LastUpvoteDate) AS EditsAfterUpvote
FROM UserActivity ua
UNION ALL
SELECT 
    NULL AS UserId,
    'Tag Summary' AS DisplayName,
    NULL AS Reputation,
    NULL AS GoldBadgeCount,
    NULL AS GoldBadges,
    NULL AS PostId,
    ta.TagName AS Title,
    ta.QuestionCount AS ViewCount,
    ta.TotalFavorites AS Score,
    NULL AS AvgScore,
    NULL AS PositiveComments,
    NULL AS LastUpvoteDate,
    ta.TagName || ' (Summary)' AS ProcessedTitle,
    (SELECT COUNT(pl.Id) FROM PostLinks pl WHERE pl.RelatedPostId IN (SELECT p.Id FROM Posts p WHERE p.Tags LIKE '%' || ta.TagName || '%') AND pl.LinkTypeId = 3) AS DuplicateLinks
FROM TagAnalysis ta
ORDER BY Reputation DESC NULLS LAST, ViewCount DESC NULLS LAST;