-- {"query": "28094.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1405} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
        AVG(v.BountyAmount) FILTER (WHERE v.VoteTypeId IN (8,9)) AS AvgBounty
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY u.Id
),
RankedUsers AS (
    SELECT 
        *,
        NTILE(4) OVER (ORDER BY Reputation DESC) AS ReputationQuartile,
        RANK() OVER (PARTITION BY NTILE(4) OVER (ORDER BY Reputation DESC) ORDER BY (QuestionCount + AnswerCount) DESC) AS ActivityRank
    FROM UserStats
)
SELECT 
    ru.*,
    (SELECT COUNT(*) 
     FROM PostHistory ph 
     JOIN Posts p ON ph.PostId = p.Id 
     WHERE p.OwnerUserId = ru.Id 
        AND ph.PostHistoryTypeId = 10 
        AND ph.Comment::INT IN (SELECT Id FROM CloseReasonTypes WHERE Name LIKE '%Duplicate%')
    ) AS DuplicateCloseActions,
    COALESCE(STRING_AGG(DISTINCT SUBSTRING(t.TagName, 1, 15), '; '), 'No Tags') AS CommonTags,
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM Posts p 
            WHERE p.OwnerUserId = ru.Id 
                AND p.AcceptedAnswerId IS NOT NULL 
                AND p.Score > 100
        ) THEN 'High Impact' 
        ELSE 'Regular' 
    END AS ImpactCategory
FROM RankedUsers ru
LEFT JOIN Posts p ON ru.Id = p.OwnerUserId
LEFT JOIN (
    SELECT Id, UNNEST(STRING_TO_ARRAY(SUBSTRING(Tags, 2, LENGTH(Tags)-2), '><')) AS TagName 
    FROM Posts 
    WHERE PostTypeId = 1
) t ON p.Id = t.Id
WHERE ru.Reputation > 1000
    OR (ru.UpvotesReceived > ru.DownvotesReceived * 2 AND ru.CommentCount > 10)
    OR ru.AvgBounty > 50
GROUP BY ru.Id, ru.Reputation, ru.CreationDate, ru.BadgeCount, ru.QuestionCount, 
    ru.AnswerCount, ru.CommentCount, ru.UpvotesReceived, ru.DownvotesReceived, 
    ru.AvgBounty, ru.ReputationQuartile, ru.ActivityRank
HAVING COUNT(DISTINCT t.TagName) BETWEEN 3 AND 10
    OR MAX(p.Score) > 500
ORDER BY 
    ReputationQuartile, 
    ActivityRank, 
    (UpvotesReceived - DownvotesReceived) DESC NULLS LAST
LIMIT 200;
