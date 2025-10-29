WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationRank,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.DisplayName IS NOT NULL
      AND u.AboutMe IS NOT NULL
      AND LENGTH(u.AboutMe) > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostScoreDistribution AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate AS PostCreationDate,
        p.AnswerCount,
        CASE
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score BETWEEN 10 AND 100 THEN 'Medium'
            WHEN p.Score > 0 AND p.Score < 10 THEN 'Low'
            ELSE 'Zero or Negative'
        END AS ScoreCategory,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
        (p.Score - LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate)) AS ScoreDifference
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
      AND p.CreationDate > DATE '2020-01-01'
),
UserAnswerQuality AS (
    SELECT
        rua.UserId,
        rua.DisplayName,
        rua.Reputation,
        AVG(CASE WHEN psd.Score > 0 THEN psd.Score ELSE NULL END) AS AveragePositiveAnswerScore,
        COUNT(CASE WHEN psd.Score > 10 THEN psd.PostId ELSE NULL END) AS HighScoringAnswers,
        SUM(CASE WHEN psd.ScoreDifference > 5 AND psd.ScoreCategory = 'Medium' THEN 1 ELSE 0 END) AS SignificantScoreGains
    FROM RankedUserActivity rua
    JOIN PostScoreDistribution psd ON rua.UserId = psd.OwnerUserId
    WHERE psd.ScoreCategory IN ('Medium', 'High')
    GROUP BY rua.UserId, rua.DisplayName, rua.Reputation
),
LatestPostEdits AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.LastEditDate,
        ph.CreationDate AS HistoryEditDate,
        ph.Comment AS EditComment,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY ph.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE ph.PostHistoryTypeId IN (4, 5) -- Edit Title, Edit Body
      AND p.LastEditDate IS NOT NULL
      AND ph.CreationDate >= (p.LastEditDate - INTERVAL '1 day')
)
SELECT
    rua.DisplayName AS UserDisplayName,
    rua.Reputation,
    rua.ReputationRank,
    rua.PostCount,
    rua.QuestionCount,
    rua.AnswerCount,
    uaq.AveragePositiveAnswerScore,
    uaq.HighScoringAnswers,
    uaq.SignificantScoreGains,
    lpe.Title AS LatestEditedPostTitle,
    lpe.EditComment AS LatestEditComment,
    COALESCE(CAST(uaq.AveragePositiveAnswerScore AS VARCHAR), 'N/A') AS FormattedAvgScore,
    CASE WHEN uaq.HighScoringAnswers > 0 THEN 'Yes' ELSE 'No' END AS HasHighScoringAnswers,
    CASE WHEN rua.UserCreationDate < DATE '2015-01-01' AND rua.Reputation > 10000 THEN 'Veteran High Rep' ELSE 'Other' END AS UserTier
FROM RankedUserActivity rua
LEFT JOIN UserAnswerQuality uaq ON rua.UserId = uaq.UserId
LEFT JOIN LatestPostEdits lpe ON rua.UserId = lpe.OwnerUserId AND lpe.rn = 1
WHERE uaq.AveragePositiveAnswerScore IS NOT NULL
   OR uaq.HighScoringAnswers > 0
ORDER BY rua.ReputationRank, uaq.SignificantScoreGains DESC
LIMIT 100;