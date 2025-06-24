
WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
        SUM(COALESCE(p.Score, 0)) AS TotalScore,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        AVG(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.AnswerCount, 0) ELSE NULL END) AS AvgAnswersPerQuestion
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON p.Id = c.PostId
    GROUP BY u.Id, u.DisplayName
),
PopularTags AS (
    SELECT 
        SUBSTRING_INDEX(SUBSTRING_INDEX(p.Tags, '><', n.n), '><', -1) AS TagName,
        COUNT(p.Id) AS TagCount
    FROM Posts p
    JOIN (SELECT 1 AS n UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION
          SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9 UNION SELECT 10) n
    ON CHAR_LENGTH(p.Tags) - CHAR_LENGTH(REPLACE(p.Tags, '><', '')) >= n.n - 1
    WHERE p.Tags IS NOT NULL
    GROUP BY TagName
    ORDER BY TagCount DESC
    LIMIT 10
),
RankedUsers AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.TotalViews,
        ua.TotalScore,
        ua.TotalPosts,
        ua.TotalComments,
        ua.AvgAnswersPerQuestion,
        @rank := @rank + 1 AS UserRank
    FROM UserActivity ua, (SELECT @rank := 0) r
    ORDER BY ua.TotalScore DESC
)

SELECT 
    ru.DisplayName, 
    ru.TotalPosts, 
    ru.TotalViews, 
    ru.TotalComments, 
    COALESCE(pt.TagName, 'No Tags') AS TopTag, 
    ru.UserRank,
    CASE 
        WHEN ru.TotalScore IS NULL THEN 'No Score'
        ELSE CASE 
            WHEN ru.TotalScore > 100 THEN 'High Performer'
            WHEN ru.TotalScore BETWEEN 50 AND 100 THEN 'Medium Performer'
            ELSE 'Low Performer'
        END 
    END AS PerformanceCategory
FROM RankedUsers ru
LEFT JOIN PopularTags pt ON pt.TagCount = (SELECT MAX(TagCount) FROM PopularTags)
WHERE ru.UserRank <= 15
ORDER BY ru.UserRank;
