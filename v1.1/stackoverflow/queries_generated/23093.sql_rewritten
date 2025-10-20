-- {"query": "23093.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 685} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COALESCE(COUNT(DISTINCT p.Id), 0) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS QuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS AnswerScore,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS LocationRank,
        LAG(u.Reputation) OVER (ORDER BY u.CreationDate) AS PrevReputation
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.Location, u.CreationDate
),
TagAnalysis AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        COUNT(p.Id) AS TaggedPosts,
        AVG(p.Score) AS AvgScore,
        STRING_AGG(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') AS CombinedTags
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE p.CreationDate > '2020-01-01'
    GROUP BY t.Id, t.TagName
    HAVING COUNT(p.Id) > 10
),
TopUsers AS (
    SELECT UserId, Reputation, PostCount, QuestionScore + AnswerScore AS TotalScore
    FROM UserStats
    WHERE Reputation > 1000
    UNION
    SELECT u.Id, u.Reputation, 0, 0
    FROM Users u
    LEFT OUTER JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    WHERE b.Id IS NULL AND u.Reputation > 500
)
SELECT 
    tu.UserId,
    tu.Reputation,
    tu.TotalScore,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = tu.UserId) AND v.VoteTypeId = 2) AS UpvotesReceived,
    COALESCE(us.LocationRank, 1) AS AdjustedRank,
    CASE 
        WHEN tu.TotalScore > 10000 THEN 'High Performer'
        WHEN tu.TotalScore BETWEEN 1000 AND 10000 THEN 'Medium Performer'
        ELSE 'Low Performer' 
    END AS PerformanceCategory,
    UPPER(COALESCE(u.DisplayName, 'Anonymous')) AS UserName,
    EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = tu.UserId) AND ph.PostHistoryTypeId = 10) AS HasClosedPosts
FROM TopUsers tu
LEFT OUTER JOIN UserStats us ON tu.UserId = us.UserId
LEFT OUTER JOIN Users u ON tu.UserId = u.Id
LEFT OUTER JOIN (
    SELECT UserId, COUNT(*) AS GoldBadges
    FROM Badges
    WHERE Class = 1
    GROUP BY UserId
) gb ON tu.UserId = gb.UserId
WHERE tu.TotalScore > (SELECT AVG(TotalScore) FROM TopUsers) OR gb.GoldBadges IS NOT NULL
ORDER BY tu.TotalScore DESC;