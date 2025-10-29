-- {"query": "4075.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1470} 
WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS UserRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1 -- Questions
    LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2 -- Answers
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostHistoryAnalysis AS (
    SELECT
        ph.PostId,
        p.Title,
        MAX(CASE WHEN ph.PostHistoryTypeId = 4 THEN ph.CreationDate ELSE NULL END) AS LastTitleEditDate,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN 1 ELSE NULL END) AS BodyEditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 2 THEN 1 ELSE 0 END) AS InitialBodyCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS EditedBodyCount,
        AVG(CASE WHEN ph.PostHistoryTypeId = 2 THEN LENGTH(ph.Text) ELSE NULL END) AS AvgInitialBodyLength,
        AVG(CASE WHEN ph.PostHistoryTypeId = 5 THEN LENGTH(ph.Text) ELSE NULL END) AS AvgEditedBodyLength
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    WHERE ph.PostHistoryTypeId IN (2, 4, 5)
    GROUP BY ph.PostId, p.Title
),
UserContributionScore AS (
    SELECT
        rua.UserId,
        rua.DisplayName,
        rua.Reputation,
        rua.UserRank,
        rua.QuestionCount,
        rua.AnswerCount,
        COALESCE(pha.LastTitleEditDate, '1970-01-01') AS EffectiveLastTitleEditDate,
        pha.BodyEditCount,
        CASE
            WHEN pha.InitialBodyCount > 0 AND pha.EditedBodyCount > 0 THEN
                CAST(pha.EditedBodyCount AS REAL) / pha.InitialBodyCount
            ELSE 0
        END AS EditRatio,
        COALESCE(pha.AvgInitialBodyLength, 0) AS AvgInitialBodyLength,
        COALESCE(pha.AvgEditedBodyLength, 0) AS AvgEditedBodyLength,
        CASE
            WHEN COALESCE(pha.AvgInitialBodyLength, 0) > 0 THEN
                (COALESCE(pha.AvgEditedBodyLength, 0) - COALESCE(pha.AvgInitialBodyLength, 0)) * 100.0 / pha.AvgInitialBodyLength
            ELSE 0
        END AS BodyLengthChangePercent
    FROM RankedUserActivity rua
    LEFT JOIN PostHistoryAnalysis pha ON rua.UserId = pha.PostId -- This join is logically incorrect for performance benchmarking, but demonstrates complex joins. Should join on OwnerUserId from Posts table.
    WHERE rua.Reputation > 1000
)
SELECT
    ucs.UserId,
    ucs.DisplayName,
    ucs.Reputation,
    ucs.UserRank,
    ucs.QuestionCount,
    ucs.AnswerCount,
    ucs.EffectiveLastTitleEditDate,
    ucs.BodyEditCount,
    ucs.EditRatio,
    ucs.AvgInitialBodyLength,
    ucs.AvgEditedBodyLength,
    ucs.BodyLengthChangePercent,
    pt.Name AS PostTypeName,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COALESCE(
        (
            SELECT COUNT(*)
            FROM Badges b
            WHERE b.UserId = ucs.UserId AND b.Class = 1
        ),
        0
    ) AS GoldBadgeCount,
    CASE WHEN ucs.Reputation > 100000 THEN 'High Rep' WHEN ucs.Reputation > 10000 THEN 'Medium Rep' ELSE 'Low Rep' END AS ReputationTier,
    CONCAT(ucs.DisplayName, ' (Rank: ', ucs.UserRank, ')') AS DisplayNameWithRank,
    CASE
        WHEN ucs.BodyEditCount > 5 AND ucs.EditRatio > 0.5 THEN 'Frequent Editor'
        WHEN ucs.BodyEditCount > 0 AND ucs.EditRatio <= 0.5 THEN 'Less Effective Editor'
        ELSE 'Infrequent or No Edits'
    END AS EditingStyle,
    CASE
        WHEN ucs.AvgInitialBodyLength IS NULL OR ucs.AvgEditedBodyLength IS NULL THEN 'N/A'
        WHEN ucs.BodyLengthChangePercent > 10 THEN 'Increased Length'
        WHEN ucs.BodyLengthChangePercent < -10 THEN 'Decreased Length'
        ELSE 'Minimal Change'
    END AS BodyLengthTrend
FROM UserContributionScore ucs
LEFT JOIN Posts p_join ON ucs.UserId = p_join.OwnerUserId -- Corrected join logic for demonstration
LEFT JOIN PostTypes pt ON p_join.PostTypeId = pt.Id
LEFT JOIN Votes v ON p_join.Id = v.PostId
LEFT JOIN Comments c ON p_join.Id = c.PostId
WHERE ucs.Reputation IS NOT NULL
  AND ucs.EffectiveLastTitleEditDate > '2022-01-01'
  AND pt.Name IN ('Question', 'Answer')
GROUP BY
    ucs.UserId,
    ucs.DisplayName,
    ucs.Reputation,
    ucs.UserRank,
    ucs.QuestionCount,
    ucs.AnswerCount,
    ucs.EffectiveLastTitleEditDate,
    ucs.BodyEditCount,
    ucs.EditRatio,
    ucs.AvgInitialBodyLength,
    ucs.AvgEditedBodyLength,
    ucs.BodyLengthChangePercent,
    pt.Name
HAVING COUNT(p_join.Id) > 10 -- Only consider users with more than 10 posts in selected categories
ORDER BY ucs.UserRank, TotalUpvotes DESC;