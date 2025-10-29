-- {"query": "7788.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1141} 
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(SUM(p.Score), 0) AS TotalScore,
    COUNT(DISTINCT p.Id) AS PostCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    STRING_AGG(DISTINCT t.TagName, ', ' ORDER BY t.TagName) AS Tags,
    AVG(p.Score) AS AvgScore,
    MAX(p.CreationDate) AS LatestPostDate,
    (
        SELECT COUNT(*) 
        FROM Posts p2 
        WHERE p2.OwnerUserId = u.Id 
        AND p2.PostTypeId = 1 
        AND p2.Score > (
            SELECT AVG(p3.Score) 
            FROM Posts p3 
            WHERE p3.OwnerUserId = u.Id 
            AND p3.PostTypeId = 1
        )
    ) AS HighScoringQuestions,
    PERCENT_RANK() OVER (ORDER BY COALESCE(SUM(p.Score), 0)) AS ScorePercentile,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 100 THEN 'High Activity'
        WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Medium Activity'
        ELSE 'Low Activity'
    END AS ActivityLevel,
    (SELECT STRING_AGG(Name, ', ') FROM Badges WHERE UserId = u.Id AND Class = 1) AS GoldBadges,
    (SELECT STRING_AGG(Name, ', ') FROM Badges WHERE UserId = u.Id AND Class = 2) AS SilverBadges,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        JOIN Posts p ON v.PostId = p.Id 
        WHERE p.OwnerUserId = u.Id 
        AND v.VoteTypeId IN (2, 3)
    ) AS VoteCount,
    (
        SELECT COUNT(*) 
        FROM Comments c 
        WHERE c.UserId = u.Id 
        AND c.PostId IN (
            SELECT Id 
            FROM Posts 
            WHERE OwnerUserId = u.Id 
            AND PostTypeId = 1
        )
    ) AS CommentCount,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph 
        WHERE ph.UserId = u.Id 
        AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
    ) AS EditCount,
    (
        SELECT AVG(DATEDIFF(day, p.CreationDate, COALESCE(p.LastEditDate, p.CreationDate)))
        FROM Posts p 
        WHERE p.OwnerUserId = u.Id 
        AND p.PostTypeId = 1
    ) AS AvgEditIntervalDays,
    (
        SELECT TOP 1 p.Title 
        FROM Posts p 
        WHERE p.OwnerUserId = u.Id 
        AND p.PostTypeId = 1 
        ORDER BY p.Score DESC
    ) AS HighestScoringQuestion,
    (
        SELECT COUNT(*)
        FROM Posts p 
        WHERE p.OwnerUserId = u.Id 
        AND p.PostTypeId = 2 
        AND EXISTS (
            SELECT 1 
            FROM Posts pa 
            WHERE pa.Id = p.ParentId 
            AND pa.AcceptedAnswerId = p.Id
        )
    ) AS AcceptedAnswersCount,
    (
        SELECT COUNT(*)
        FROM Posts p 
        WHERE p.OwnerUserId = u.Id 
        AND p.PostTypeId = 1 
        AND p.AnswerCount = 0
    ) AS UnansweredQuestions,
    (
        SELECT COUNT(*)
        FROM Posts p 
        WHERE p.OwnerUserId = u.Id 
        AND p.PostTypeId = 1 
        AND p.ClosedDate IS NOT NULL
    ) AS ClosedQuestions,
    (
        SELECT COUNT(*)
        FROM Posts p 
        WHERE p.OwnerUserId = u.Id 
        AND p.PostTypeId = 1 
        AND p.CommunityOwnedDate IS NOT NULL
    ) AS CommunityOwnedQuestions
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Tags t ON t.Id IN (
    SELECT Id 
    FROM Tags 
    WHERE TagName IN (
        SELECT UNNEST(string_to_array(p.Tags, '><'))
        FROM Posts p 
        WHERE p.OwnerUserId = u.Id 
        AND p.PostTypeId = 1
    )
)
WHERE u.Reputation > 1000 
AND u.CreationDate > '2010-01-01 00:00:00'
AND (
    u.AccountId IS NULL 
    OR u.AccountId NOT IN (
        SELECT AccountId 
        FROM Users 
        WHERE AccountId IS NOT NULL 
        GROUP BY AccountId 
        HAVING COUNT(*) > 1
    )
)
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) > 0
AND (
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
    OR COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0
)
ORDER BY COALESCE(SUM(p.Score), 0) DESC, COUNT(DISTINCT p.Id) DESC
OFFSET 0 ROWS FETCH NEXT 1000 ROWS ONLY;