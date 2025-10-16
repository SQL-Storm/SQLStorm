WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        AVG(p.Score) AS AvgPostScore,
        MIN(p.CreationDate) AS LatestPostDate,
        -- LatestPostTitle obtained via DISTINCT ON in a subquery join for compatibility
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.ViewCount) AS MedianViewCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE p.PostTypeId = 1 AND u.Reputation > 100
    GROUP BY u.Id, u.DisplayName
),
UserLatestPostTitle AS (
    SELECT DISTINCT ON (p.OwnerUserId)
        p.OwnerUserId AS UserId,
        p.Title AS LatestPostTitle,
        p.CreationDate
    FROM Posts p
    WHERE p.PostTypeId = 1
    ORDER BY p.OwnerUserId, p.CreationDate DESC
),
TagPopularity AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS TagPostCount,
        CASE 
            WHEN COUNT(p.Id) > 1000 THEN 'Extremely Popular'
            WHEN COUNT(p.Id) > 500 THEN 'Very Popular'
            WHEN COUNT(p.Id) > 100 THEN 'Popular'
            ELSE 'Niche'
        END AS PopularityCategory
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    GROUP BY t.TagName
)
SELECT 
    uas.UserId,
    uas.DisplayName,
    uas.PostCount,
    uas.VoteCount,
    uas.AvgPostScore,
    COALESCE(ult.LatestPostTitle, '') AS LatestPostTitle,
    -- PostCountRank computed via window over the aggregated results
    RANK() OVER (ORDER BY uas.PostCount DESC) AS PostCountRank,
    uas.MedianViewCount,
    (SELECT STRING_AGG(tp.TagName || '(' || tp.PopularityCategory || ')', ', ')
     FROM TagPopularity tp
     JOIN Posts p ON p.Tags LIKE '%' || tp.TagName || '%'
     WHERE p.OwnerUserId = uas.UserId
     LIMIT 5) AS TopTags,
    COALESCE(
        (SELECT SUM(v.BountyAmount) 
         FROM Votes v 
         WHERE v.UserId = uas.UserId AND v.VoteTypeId = 8), 
        0
    ) AS TotalBountyStarted
FROM UserActivityStats uas
LEFT JOIN UserLatestPostTitle ult ON ult.UserId = uas.UserId
WHERE uas.PostCount > 10
ORDER BY uas.PostCount DESC, uas.AvgPostScore DESC
FETCH FIRST 100 ROWS ONLY;