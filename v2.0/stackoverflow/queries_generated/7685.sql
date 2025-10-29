-- {"query": "7685.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2149} 
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
    COUNT(DISTINCT b.Id) AS BadgesReceived,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1 AND Score > 100) AS HighScoreQuestions,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 2 AND Score > 50) AS HighScoreAnswers,
    STRING_AGG(DISTINCT t.TagName, ', ') AS TagInterests,
    AVG(CAST(p.Score AS FLOAT)) AS AvgPostScore,
    MAX(p.CreationDate) AS LastPostDate,
    DATEDIFF(DAY, u.CreationDate, MAX(p.CreationDate)) AS DaysActive,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 100 THEN 'High Engagement'
        WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Medium Engagement'
        ELSE 'Low Engagement'
    END AS EngagementLevel,
    COALESCE(
        (SELECT TOP 1 p.Title 
         FROM Posts p 
         WHERE p.OwnerUserId = u.Id 
         AND p.PostTypeId = 1 
         AND p.Score = (SELECT MAX(Score) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1)
        ), 
        'No Questions'
    ) AS HighestRatedQuestion,
    ROW_NUMBER() OVER (ORDER BY SUM(p.Score) DESC) AS ReputationRank,
    PERCENT_RANK() OVER (ORDER BY u.Reputation) AS ReputationPercentile,
    RANK() OVER (PARTITION BY CASE WHEN u.Reputation > 10000 THEN 'High' ELSE 'Low' END ORDER BY u.Reputation) AS ReputationByTierRank,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph 
        WHERE ph.UserId = u.Id 
        AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6) 
        AND ph.CreationDate >= DATEADD(YEAR, -1, GETDATE())
    ) AS RecentEdits,
    (
        SELECT COUNT(*) 
        FROM Comments c 
        WHERE c.UserId = u.Id 
        AND c.CreationDate >= DATEADD(YEAR, -1, GETDATE())
    ) AS RecentComments,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.UserId = u.Id 
        AND v.VoteTypeId IN (2, 3) 
        AND v.CreationDate >= DATEADD(YEAR, -1, GETDATE())
    ) AS RecentVotes,
    (SELECT TOP 1 Name FROM Badges WHERE UserId = u.Id ORDER BY Date DESC) AS LatestBadge,
    (
        SELECT COUNT(*) 
        FROM PostLinks pl 
        WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) 
        AND pl.LinkTypeId = 1
    ) AS OutgoingLinks,
    (
        SELECT COUNT(*) 
        FROM PostLinks pl 
        WHERE pl.RelatedPostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) 
        AND pl.LinkTypeId = 1
    ) AS IncomingLinks,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.OwnerUserId = u.Id 
        AND p.ParentId IS NOT NULL 
        AND p.Score > 0
    ) AS HelpfulAnswers,
    (
        SELECT STRING_AGG(CAST(v.BountyAmount AS VARCHAR(10)), ', ') 
        FROM Votes v 
        WHERE v.UserId = u.Id 
        AND v.VoteTypeId = 8
    ) AS BountyHistory,
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
        AND p.AcceptedAnswerId IS NOT NULL
    ) AS QuestionsWithAcceptedAnswers,
    (
        SELECT AVG(CAST(p.Score AS FLOAT))
        FROM Posts p 
        WHERE p.OwnerUserId = u.Id 
        AND p.PostTypeId = 1
    ) AS AvgQuestionScore,
    (
        SELECT AVG(CAST(p.Score AS FLOAT))
        FROM Posts p 
        WHERE p.OwnerUserId = u.Id 
        AND p.PostTypeId = 2
    ) AS AvgAnswerScore,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.OwnerUserId = u.Id 
        AND p.PostTypeId = 1 
        AND p.ViewCount > 1000
    ) AS PopularQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.OwnerUserId = u.Id 
        AND p.PostTypeId = 2 
        AND p.ViewCount > 500
    ) AS PopularAnswers,
    (
        SELECT MAX(ph.CreationDate) 
        FROM PostHistory ph 
        WHERE ph.UserId = u.Id 
        AND ph.PostHistoryTypeId IN (10, 11, 12, 13)
    ) AS LastModerationActivity,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.OwnerUserId = u.Id 
        AND p.ParentId IS NULL 
        AND p.PostTypeId = 1 
        AND p.TagBased = 1
    ) AS TagBasedQuestions
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN (
    SELECT p.OwnerUserId, t.TagName
    FROM Posts p
    CROSS APPLY STRING_SPLIT(p.Tags, '><') AS tag_parts
    JOIN Tags t ON t.TagName = LTRIM(RTRIM(REPLACE(REPLACE(tag_parts.value, '<', ''), '>', '')))
    WHERE p.Tags IS NOT NULL AND p.Tags != ''
) AS tag_users ON u.Id = tag_users.OwnerUserId
WHERE u.Reputation > 100
    AND u.CreationDate >= DATEADD(YEAR, -2, GETDATE())
    AND u.AccountId IS NOT NULL
GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
HAVING COUNT(DISTINCT p.Id) > 0
    AND COUNT(DISTINCT b.Id) > 0
    AND MAX(p.CreationDate) >= DATEADD(MONTH, -6, GETDATE())
ORDER BY SUM(p.Score) DESC, COUNT(DISTINCT p.Id) DESC
OFFSET 100 ROWS
FETCH NEXT 100 ROWS ONLY;

-- Complex CTE structure for additional metrics calculation
WITH UserMetrics AS (
    SELECT 
        u.Id,
        u.Reputation,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        AVG(CAST(p.Score AS FLOAT)) as AvgScore,
        MAX(p.CreationDate) as LastActivity
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation
),
TopUsers AS (
    SELECT 
        Id,
        Reputation,
        PostCount,
        QuestionCount,
        AnswerCount,
        AvgScore,
        LastActivity,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC) as Rank
    FROM UserMetrics
)
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(p.Id) as TotalPosts,
    COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) as Questions,
    COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) as Answers,
    (
        SELECT TOP 1 Name FROM Badges b WHERE b.UserId = u.Id ORDER BY Date DESC
    ) as LatestBadge,
    (
        SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id and v.VoteTypeId IN (2,3)
    ) as UpvotesReceived,
    (CASE 
        WHEN COUNT(p.Id) > 1000 THEN 'Ultra Active'
        WHEN COUNT(p.Id) > 500 THEN 'Very Active'
        WHEN COUNT(p.Id) > 100 THEN 'Active'
        ELSE 'Regular'
    END) as ActivityLevel,
    (
        SELECT AVG(CAST(p2.Score AS FLOAT)) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1
    ) as AvgQuestionScore,
    (
        SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = u.Id AND p3.PostTypeId = 2 AND p3.Score > 0
    ) as HelpfulAnswers,
    (
        SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id
    ) as CommentsPosted,
    (
        SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id and ph.PostHistoryTypeId IN (1,2,3,4,5,6)
    ) as EditsMade,
    (
        SELECT STRING_AGG(t.TagName, ', ') 
        FROM (
            SELECT DISTINCT t.TagName
            FROM Posts p
            JOIN Tags t ON t.TagName IN (SELECT value FROM STRING_SPLIT(p.Tags, '><'))
            WHERE p.OwnerUserId = u.Id AND p.Tags IS NOT NULL AND p.Tags != ''
        ) t
    ) as PreferredTags
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
WHERE u.Id IN (SELECT Id FROM TopUsers WHERE Rank BETWEEN 1 AND 100)
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(p.Id) > 0
ORDER BY AVG(p.Score) DESC, COUNT(p.Id) DESC;