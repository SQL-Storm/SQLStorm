-- {"query": "20050.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1431} 

WITH HighValueQuestions AS (
    -- Identify questions that are highly-voted, viewed, have answers, and are not closed.
    SELECT
        p.Id,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.CreationDate,
        p.Score,
        p.Tags,
        p.AnswerCount
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Questions
      AND p.ClosedDate IS NULL
      AND p.AnswerCount > 1
      AND p.Score > (SELECT percentile_cont(0.75) WITHIN GROUP (ORDER BY Score) FROM Posts WHERE PostTypeId = 1)
      AND p.ViewCount > (SELECT percentile_cont(0.75) WITHIN GROUP (ORDER BY ViewCount) FROM Posts WHERE PostTypeId = 1)
),
UserContributions AS (
    -- Correlate users to their answers on high-value questions and calculate individual answer metrics.
    SELECT
        a.Id AS AnswerId,
        a.OwnerUserId,
        a.ParentId AS QuestionId,
        a.CreationDate AS AnswerDate,
        a.Score AS AnswerScore,
        q.AcceptedAnswerId,
        q.CreationDate AS QuestionDate,
        -- Calculate time to answer in hours
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)) / 3600.0 AS HoursToAnswer,
        -- Window function to rank answers by the same user to different questions
        ROW_NUMBER() OVER(PARTITION BY a.OwnerUserId ORDER BY a.CreationDate DESC) AS UserAnswerRank
    FROM Posts a
    JOIN HighValueQuestions q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2 -- Answers
      AND a.OwnerUserId IS NOT NULL
),
AggregatedUserStats AS (
    -- Aggregate statistics for each user based on their answers to high-value questions.
    SELECT
        uc.OwnerUserId,
        COUNT(uc.AnswerId) AS NumHighValueAnswers,
        AVG(uc.AnswerScore) AS AvgAnswerScore,
        AVG(uc.HoursToAnswer) AS AvgHoursToAnswer,
        SUM(CASE WHEN uc.AnswerId = uc.AcceptedAnswerId THEN 1 ELSE 0 END)::decimal / COUNT(uc.AnswerId) AS AcceptanceRate,
        -- Find the user's last post of any type
        (SELECT MAX(p.CreationDate) FROM Posts p WHERE p.OwnerUserId = uc.OwnerUserId) AS LastPostDate
    FROM UserContributions uc
    GROUP BY uc.OwnerUserId
    HAVING COUNT(uc.AnswerId) > 2
),
UserBadgeAndTag AS (
    -- Combine user data with their badges and expertise in specific tags, using UNION to also include question askers.
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.UpVotes,
        u.DownVotes,
        b.Name AS BadgeName,
        b.Date AS BadgeDate,
        'Answerer' AS ContributionType
    FROM Users u
    JOIN AggregatedUserStats aus ON u.Id = aus.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1 -- Gold badges only
    WHERE u.Reputation > 5000

    UNION ALL

    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.UpVotes,
        u.DownVotes,
        NULL AS BadgeName,
        NULL AS BadgeDate,
        'Asker' AS ContributionType
    FROM Users u
    JOIN HighValueQuestions hvq ON u.Id = hvq.OwnerUserId
    WHERE
        -- Find users who asked a highly-valued question but are not in the 'Answerer' set above
        u.Id NOT IN (SELECT OwnerUserId FROM AggregatedUserStats)
        AND u.Reputation > 1000
)
-- Final complex query to rank users based on a composite score.
SELECT
    ubt.DisplayName,
    ubt.Reputation,
    aus.NumHighValueAnswers,
    aus.AcceptanceRate,
    ubt.Location,
    -- Construct a user summary string
    CONCAT(
        'User since ',
        TO_CHAR(ubt.CreationDate, 'YYYY-MM'),
        '. Voted ',
        ubt.UpVotes,
        ' up, ',
        ubt.DownVotes,
        ' down.'
    ) AS UserSummary,
    -- Calculate a final composite score with complex logic and NULL handling
    (
        LOG(ubt.Reputation) * 2
        + COALESCE(aus.NumHighValueAnswers, 0) * 1.5
        + COALESCE(aus.AcceptanceRate, 0) * 100
        - COALESCE(aus.AvgHoursToAnswer / 24, 100)
        + CASE WHEN ubt.BadgeName IS NOT NULL THEN 50 ELSE 0 END
    ) AS CompositeScore,
    -- Use a window function to create quartiles based on reputation
    NTILE(4) OVER (ORDER BY ubt.Reputation DESC) AS ReputationQuartile,
    -- Check if the user has ever edited a post they didn't own
    EXISTS (
        SELECT 1
        FROM PostHistory ph
        WHERE ph.UserId = ubt.Id
          AND ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, or Tags
          AND ph.PostId IN (SELECT Id FROM Posts p WHERE p.OwnerUserId != ubt.Id)
    ) AS HasEditedOthersPosts
FROM UserBadgeAndTag ubt
LEFT JOIN AggregatedUserStats aus ON ubt.Id = aus.OwnerUserId
WHERE
    ubt.ContributionType = 'Answerer'
    AND (ubt.Location LIKE '%California%' OR ubt.Reputation > 100000)
    AND COALESCE(aus.AvgAnswerScore, 0) > 5
ORDER BY
    CompositeScore DESC,
    ubt.Reputation DESC
LIMIT 200;
