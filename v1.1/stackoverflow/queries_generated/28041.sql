-- {"query": "28041.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1377} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (5,6) THEN 1 ELSE 0 END) AS EditActions
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2,3,8)
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.UserId = u.Id
    GROUP BY u.Id
),
BadgeSummary AS (
    SELECT 
        UserId,
        MAX(Name) KEEP (DENSE_RANK LAST ORDER BY Date) AS LastBadge,
        COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges
    FROM Badges
    GROUP BY UserId
)
SELECT 
    u.DisplayName || ' (' || COALESCE(u.Location, 'Unknown') || ')' AS UserLabel,
    EXTRACT(YEAR FROM u.CreationDate) AS JoinYear,
    u.Reputation,
    RANK() OVER (PARTITION BY COALESCE(u.Location, 'Unknown') ORDER BY u.Reputation DESC) AS LocationRank,
    bs.LastBadge,
    ua.PostCount,
    ua.CommentCount,
    ua.VoteCount,
    ua.AvgQuestionScore,
    ua.EditActions,
    (SELECT COUNT(*) FROM Posts p2 
     WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 2 
     AND p2.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2)) AS HighQualityAnswers,
    ARRAY_TO_STRING(ARRAY(
        SELECT DISTINCT t.TagName 
        FROM Posts p3 
        JOIN unnest(string_to_array(regexp_replace(p3.Tags, '<|>', '', 'g'), ' ')) AS tag
        ON tag = t.TagName
        WHERE p3.OwnerUserId = u.Id AND p3.PostTypeId = 1
    ), ', ') AS TopTags
FROM Users u
JOIN UserActivity ua ON u.Id = ua.UserId
LEFT JOIN BadgeSummary bs ON u.Id = bs.UserId
WHERE u.Reputation > 1000
    AND EXISTS (
        SELECT 1 FROM Posts p4 
        WHERE p4.OwnerUserId = u.Id 
        AND p4.ClosedDate IS NOT NULL 
        AND p4.Score < 0
    )
    AND u.Id IN (
        SELECT UserId FROM Badges WHERE Class = 1
        INTERSECT
        SELECT UserId FROM Badges WHERE Name LIKE '%Moderator%'
    )
ORDER BY 
    LocationRank,
    u.Reputation DESC
LIMIT 100;
