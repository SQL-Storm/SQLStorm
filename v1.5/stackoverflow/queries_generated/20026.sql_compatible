WITH UserQuestionDetails AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.FavoriteCount,
        p.AcceptedAnswerId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS QuestionRank,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS UserAvgQuestionScore,
        LAG(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousQuestionDate,
        CASE
            WHEN p.Tags IS NOT NULL AND p.Tags <> '' THEN
                SPLIT_PART(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><', 1)
            ELSE
                'untagged'
        END AS PrimaryTag
    FROM Posts p
    WHERE p.PostTypeId = 1
),
GlobalTagStats AS (
    SELECT
        uqd.PrimaryTag,
        AVG(uqd.Score) AS AvgGlobalScore,
        AVG(uqd.ViewCount) AS AvgGlobalViewCount,
        COUNT(*) AS TotalQuestionsWithTag
    FROM UserQuestionDetails uqd
    GROUP BY uqd.PrimaryTag
    HAVING COUNT(*) > 50
),
ActiveOrVeteranUsers AS (
    SELECT Id, DisplayName, Reputation, Location
    FROM Users
    WHERE LastAccessDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year') AND Reputation > 10000
    UNION
    SELECT Id, DisplayName, Reputation, Location
    FROM Users
    WHERE CreationDate < '2012-01-01' AND Reputation > 50000
)
SELECT
    u.DisplayName AS UserName,
    u.Reputation,
    DENSE_RANK() OVER (PARTITION BY COALESCE(u.Location, 'N/A') ORDER BY u.Reputation DESC) AS LocationRank,
    uqd.Title AS LastQuestionTitle,
    uqd.Score AS LastQuestionScore,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = uqd.Id AND ph.PostHistoryTypeId = 10) AS CloseVotes,
    gts.AvgGlobalScore AS TagAvgScore,
    (uqd.Score - gts.AvgGlobalScore) / NULLIF(uqd.UserAvgQuestionScore, 0) AS RelativePerformance,
    CASE
        WHEN uqd.Score > gts.AvgGlobalScore THEN 'Above Average'
        WHEN uqd.Score < gts.AvgGlobalScore THEN 'Below Average'
        ELSE 'Average'
    END AS PerformanceCategory,
    CONCAT('Asked on: ', CAST(uqd.CreationDate AS VARCHAR), '. Days since previous: ',
        CAST(EXTRACT(DAY FROM (uqd.CreationDate - COALESCE(uqd.PreviousQuestionDate, uqd.CreationDate))) AS VARCHAR)
    ) AS QuestionTiming,
    aa.Body AS AcceptedAnswerBodySample,
    COALESCE(ans_user.DisplayName, 'No Accepted Answer') AS Answerer,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ans_user.Id AND b.Class = 1) AS AnswererGoldBadges
FROM ActiveOrVeteranUsers AS u
JOIN UserQuestionDetails AS uqd ON u.Id = uqd.OwnerUserId
LEFT JOIN GlobalTagStats AS gts ON uqd.PrimaryTag = gts.PrimaryTag
LEFT JOIN Posts AS aa ON uqd.AcceptedAnswerId = aa.Id
LEFT JOIN Users AS ans_user ON aa.OwnerUserId = ans_user.Id
WHERE uqd.QuestionRank = 1
  AND u.Location IS NOT NULL
  AND u.Location <> ''
  AND uqd.FavoriteCount > (SELECT AVG(FavoriteCount) FROM Posts WHERE PostTypeId = 1 AND FavoriteCount > 0)
ORDER BY u.Location, LocationRank, u.Reputation DESC
LIMIT 500;