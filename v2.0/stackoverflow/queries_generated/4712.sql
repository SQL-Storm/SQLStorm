-- {"query": "4712.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1040} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.Title IS NOT NULL AND LENGTH(p.Title) > 10
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) AS CommentCount,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.Views > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) > 50
),
PostWithMeta AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.ClosedDate,
        pt.Name AS PostTypeName,
        COALESCE(p.ViewCount, 0) AS ViewCount,
        CASE WHEN p.FavoriteCount > 100 THEN 'Popular' WHEN p.Score > 50 THEN 'Highly Rated' ELSE 'Standard' END AS PostStatus,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score < 0) AS NegativeCommentCount
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.PostTypeId IN (1, 2)
),
AggregatedPostStats AS (
    SELECT
        p.PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.PostTypeName,
        COALESCE(ua.CommentCount, 0) AS UserComments,
        COALESCE(ua.PostCount, 0) AS UserPosts,
        p.Score * (p.ViewCount + 1) AS WeightedScore,
        DATEDIFF(day, p.CreationDate, p.ClosedDate) AS DaysToClose
    FROM PostWithMeta p
    LEFT JOIN UserActivity ua ON p.OwnerUserId = ua.UserId
    WHERE p.Score > 0 AND p.AnswerCount IS NOT NULL
)
SELECT
    aps.Title,
    aps.PostTypeName,
    aps.Score,
    aps.ViewCount,
    aps.UserComments,
    aps.UserPosts,
    aps.WeightedScore,
    CASE
        WHEN aps.DaysToClose < 7 THEN 'Fast Closure'
        WHEN aps.DaysToClose > 365 THEN 'Slow Closure'
        ELSE 'Average Closure'
    END AS ClosureSpeed,
    COALESCE(p.TagName, 'N/A') AS PrimaryTag,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = aps.PostId AND pl.LinkTypeId = 1) AS LinkedPostsCount,
    CASE
        WHEN ua.DisplayName LIKE '%a%' OR ua.DisplayName LIKE '%e%' OR ua.DisplayName LIKE '%i%' OR ua.DisplayName LIKE '%o%' OR ua.DisplayName LIKE '%u%' THEN 'Voweled Name'
        ELSE 'Consonantal Name'
    END AS UserNameVowelType
FROM AggregatedPostStats aps
LEFT JOIN Posts p ON aps.PostId = p.Id
LEFT JOIN Users ua ON aps.OwnerUserId = ua.Id
WHERE aps.WeightedScore > (SELECT AVG(WeightedScore) FROM AggregatedPostStats)
UNION ALL
SELECT
    rp.Title,
    rp.PostTypeName,
    NULL AS Score,
    NULL AS ViewCount,
    NULL AS UserComments,
    NULL AS UserPosts,
    NULL AS WeightedScore,
    'Newest Post' AS ClosureSpeed,
    NULL AS PrimaryTag,
    NULL AS LinkedPostsCount,
    'Unknown' AS UserNameVowelType
FROM RankedPosts rp
WHERE rp.rn <= 5;
