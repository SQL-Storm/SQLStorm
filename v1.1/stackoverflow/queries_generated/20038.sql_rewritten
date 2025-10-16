-- {"query": "20038.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1184} 
WITH TaggedQuestionStats AS (
    SELECT
        p.OwnerUserId,
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.AnswerCount,
        p.CreationDate AS QuestionDate,
        a.Id AS AcceptedAnswerId,
        a.CreationDate AS AcceptedAnswerDate,
        EXTRACT(EPOCH FROM (a.CreationDate - p.CreationDate)) / 3600.0 AS HoursToAcceptedAnswer,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) as QuestionRankByScore
    FROM Posts p
    LEFT JOIN Posts a ON p.AcceptedAnswerId = a.Id
    WHERE p.PostTypeId = 1 -- Questions
      AND p.OwnerUserId IS NOT NULL
      AND p.ClosedDate IS NULL
      AND (p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<performance>%' OR p.Tags LIKE '%<database-design>%')
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        u.Location,
        COUNT(DISTINCT q.Id) AS TotalQuestions,
        COUNT(DISTINCT ans.Id) AS TotalAnswers,
        SUM(ans.Score) AS TotalAnswerScore,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS TotalComments,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpvotesGiven,
        (SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.UserId = u.Id) AS LastEditDate,
        LAG(u.CreationDate, 1, u.CreationDate) OVER (ORDER BY u.CreationDate) as PreviousUserCreationDate
    FROM Users u
    LEFT JOIN Posts q ON u.Id = q.OwnerUserId AND q.PostTypeId = 1
    LEFT JOIN Posts ans ON u.Id = ans.OwnerUserId AND ans.PostTypeId = 2
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation, u.CreationDate, u.DisplayName, u.Location
),
GoldBadgeVsBountyUsers AS (
    -- Users who have received a gold badge for a specific tag
    SELECT UserId, Name as BadgeName, 'Gold Badge' AS UserGroup FROM Badges WHERE Class = 1 AND TagBased = '1'
    UNION ALL
    -- Users who have offered a bounty of over 300
    SELECT UserId, CAST(BountyAmount AS VARCHAR) AS Detail, 'High Bounty' AS UserGroup FROM Votes WHERE VoteTypeId = 8 AND BountyAmount > 300 AND UserId IS NOT NULL
)
SELECT
    uas.DisplayName,
    uas.Reputation,
    tqs.Title AS TopQuestionTitle,
    tqs.Score AS TopQuestionScore,
    tqs.HoursToAcceptedAnswer,
    (SELECT AVG(Reputation) FROM Users) AS GlobalAvgReputation,
    uas.Reputation - (SELECT AVG(Reputation) FROM Users) AS ReputationDelta,
    CASE
        WHEN uas.TotalAnswerScore > (uas.TotalQuestions * 10) THEN 'Primarily an Answerer'
        WHEN uas.TotalQuestions > (uas.TotalAnswers * 2) THEN 'Primarily an Asker'
        ELSE 'Balanced Contributor'
    END AS ContributionType,
    gbu.UserGroup AS EliteGroup,
    RANK() OVER (PARTITION BY gbu.UserGroup ORDER BY uas.Reputation DESC) AS RankWithinEliteGroup,
    CONCAT(uas.DisplayName, ' from ', COALESCE(NULLIF(uas.Location, ''), 'Unknown Location')) AS UserLocationInfo,
    (
        SELECT STRING_AGG(b.Name, ', ')
        FROM (
            SELECT Name FROM Badges b
            WHERE b.UserId = uas.UserId AND b.Class = 1
            ORDER BY b.Date DESC LIMIT 3
        ) b
    ) AS RecentGoldBadges
FROM UserActivitySummary uas
JOIN TaggedQuestionStats tqs ON uas.UserId = tqs.OwnerUserId AND tqs.QuestionRankByScore <= 2
LEFT JOIN GoldBadgeVsBountyUsers gbu ON uas.UserId = gbu.UserId
WHERE
    uas.TotalAnswers > uas.TotalQuestions
    AND uas.Reputation > (SELECT percentile_cont(0.90) WITHIN GROUP (ORDER BY Reputation) FROM Users)
    AND uas.UserId NOT IN (
        -- Exclude users whose last edit was on a post that was eventually deleted
        SELECT ph.UserId FROM PostHistory ph
        JOIN Posts p ON ph.PostId = p.Id
        WHERE ph.PostHistoryTypeId IN (5, 8) -- Edit Body, Rollback Body
          AND p.ClosedDate IS NOT NULL AND p.Id IS NULL -- Simulating a complex, possibly inefficient exclusion
    )
ORDER BY
    RankWithinEliteGroup,
    ReputationDelta DESC
LIMIT 100;