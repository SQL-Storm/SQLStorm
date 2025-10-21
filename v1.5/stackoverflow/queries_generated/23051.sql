-- {"query": "23051.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 1143} 
WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        MAX(p.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS RankInLocation
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Location
    HAVING COUNT(DISTINCT p.Id) > 10
),
TagAnalysis AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        COUNT(p.Id) AS TaggedPosts,
        STRING_AGG(COALESCE(p.Title, 'Untitled'), '; ') AS ConcatTitles,
        SUM(CASE WHEN p.Score IS NULL THEN 0 ELSE p.Score END) AS TotalScore
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE t.Count > 500
    GROUP BY t.Id, t.TagName
),
CorrelatedSubquery AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        (SELECT COUNT(v.Id) 
         FROM Votes v 
         INNER JOIN Posts pv ON v.PostId = pv.Id 
         WHERE pv.OwnerUserId = ua.UserId 
         AND v.VoteTypeId IN (2, 3) 
         AND v.CreationDate > ua.LastPostDate - INTERVAL '1 YEAR') AS RecentVotes
    FROM UserActivity ua
),
BadgeSummary AS (
    SELECT 
        b.UserId,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 3 WHEN b.Class = 2 THEN 2 ELSE 1 END) AS WeightedBadgeScore,
        MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
CombinedData AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.PostCount,
        ua.AvgPostScore,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.RankInLocation,
        COALESCE(bs.BadgeCount, 0) AS BadgeCount,
        COALESCE(bs.WeightedBadgeScore, 0) AS WeightedBadgeScore,
        cs.RecentVotes,
        ta.TagName AS MostFrequentTag,
        ta.TotalScore AS TagTotalScore
    FROM UserActivity ua
    LEFT OUTER JOIN BadgeSummary bs ON ua.UserId = bs.UserId
    INNER JOIN CorrelatedSubquery cs ON ua.UserId = cs.UserId
    LEFT OUTER JOIN (
        SELECT 
            p.OwnerUserId,
            t.TagName,
            COUNT(*) AS TagFreq,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC) AS rn
        FROM Posts p
        CROSS JOIN LATERAL STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><') AS tag_array(tag)
        INNER JOIN Tags t ON t.TagName = tag_array.tag
        WHERE p.PostTypeId = 1
        GROUP BY p.OwnerUserId, t.TagName
    ) AS user_tags ON ua.UserId = user_tags.OwnerUserId AND user_tags.rn = 1
    LEFT OUTER JOIN TagAnalysis ta ON user_tags.TagName = ta.TagName
    WHERE ua.RankInLocation <= 5
       OR (ua.QuestionCount > ua.AnswerCount AND ua.AvgPostScore > 5)
),
SetOperation AS (
    SELECT UserId, DisplayName, Reputation, 'High Rep' AS Category
    FROM CombinedData
    WHERE Reputation > 10000
    UNION ALL
    SELECT UserId, DisplayName, Reputation, 'High Badges' AS Category
    FROM CombinedData
    WHERE BadgeCount > 50
    INTERSECT
    SELECT UserId, DisplayName, Reputation, 'Active Voters' AS Category
    FROM CombinedData
    WHERE RecentVotes > 100
)
SELECT 
    so.UserId,
    so.DisplayName,
    so.Reputation,
    so.Category,
    LAG(so.Reputation) OVER (ORDER BY so.Reputation DESC) AS PrevReputation,
    LEAD(so.Reputation) OVER (ORDER BY so.Reputation DESC) AS NextReputation,
    SUM(so.Reputation) OVER (PARTITION BY so.Category) AS TotalRepInCategory,
    AVG(cd.AvgPostScore) OVER () AS GlobalAvgScore,
    CASE 
        WHEN cd.MostFrequentTag IS NULL THEN 'No Tag'
        ELSE UPPER(cd.MostFrequentTag) || ' (' || cd.TagTotalScore || ')'
    END AS TagInfo,
    COALESCE(cd.WeightedBadgeScore * 1.5 + cd.RecentVotes / NULLIF(cd.PostCount, 0), 0) AS ComplexScore
FROM SetOperation so
INNER JOIN CombinedData cd ON so.UserId = cd.UserId
WHERE cd.ComplexScore > 10
ORDER BY cd.ComplexScore DESC
LIMIT 100;