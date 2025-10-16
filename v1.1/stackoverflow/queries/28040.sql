-- {"query": "28040.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1238} 
WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS EditActions
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId = 2
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.CreationDate BETWEEN cast('2024-10-01' as date) - INTERVAL '1 year' AND cast('2024-10-01' as date)
    WHERE u.Reputation > (SELECT AVG(Reputation) FROM Users WHERE CreationDate > '2015-01-01')
    GROUP BY u.Id
    HAVING COUNT(p.Id) > 5 OR COUNT(c.Id) > 10
),
BadgeRanking AS (
    SELECT 
        UserId,
        Name AS TopBadge,
        RANK() OVER (PARTITION BY UserId ORDER BY Class, Date DESC) AS BadgeRank
    FROM Badges
    WHERE Class IN (1,2)
)
SELECT 
    u.DisplayName,
    COALESCE(u.Location, 'Unknown') || ' - ' || EXTRACT(YEAR FROM u.CreationDate) AS UserInfo,
    ua.PostCount,
    ua.CommentCount,
    ua.VoteCount,
    ROUND(ua.AvgQuestionScore, 2) AS AvgQScore,
    (ua.EditActions * 1.0) / NULLIF(ua.PostCount, 0) AS EditsPerPost,
    br.TopBadge,
    DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS GlobalRepRank,
    CASE 
        WHEN ua.PostCount > 100 THEN 'High Activity' 
        WHEN ua.PostCount BETWEEN 20 AND 100 THEN 'Medium Activity' 
        ELSE 'Low Activity' 
    END AS ActivityLevel,
    STRING_AGG(DISTINCT p.Tags, ';') FILTER (WHERE p.PostTypeId = 1) AS FrequentTags
FROM Users u
INNER JOIN UserActivity ua ON u.Id = ua.UserId
LEFT JOIN BadgeRanking br ON u.Id = br.UserId AND br.BadgeRank = 1
LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
WHERE u.Id IN (
    SELECT UserId FROM Badges WHERE Class = 1
    UNION
    SELECT OwnerUserId FROM Posts WHERE AnswerCount > 5 AND ClosedDate IS NULL
)
AND EXISTS (
    SELECT 1 FROM PostHistory ph 
    WHERE ph.UserId = u.Id 
    AND ph.PostHistoryTypeId IN (5,6) 
    AND ph.CreationDate > cast('2024-10-01' as date) - INTERVAL '6 months'
)
GROUP BY u.Id, u.DisplayName, u.Location, u.CreationDate, u.Reputation, ua.PostCount, ua.CommentCount, 
         ua.VoteCount, ua.AvgQuestionScore, ua.EditActions, br.TopBadge
ORDER BY GlobalRepRank, ActivityLevel DESC
LIMIT 100 OFFSET 0;