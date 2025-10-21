-- {"query": "20028.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1390} 

WITH UserAnswerStats AS (
    -- Calculate detailed statistics for each user's answers, including average score and accepted answer count.
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalAnswers,
        AVG(p.Score) AS AvgAnswerScore,
        SUM(CASE WHEN q.AcceptedAnswerId = p.Id THEN 1 ELSE 0 END) AS AcceptedAnswersCount
    FROM Posts p
    JOIN Posts q ON p.ParentId = q.Id
    WHERE p.PostTypeId = 2 AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserQuestionStats AS (
    -- Calculate statistics for user's questions, including tag analysis using string functions.
    SELECT
        OwnerUserId,
        COUNT(*) AS TotalQuestions,
        AVG(Score) AS AvgQuestionScore,
        SUM(COALESCE(AnswerCount, 0)) AS TotalAnswersOnQuestions,
        AVG(array_length(string_to_array(substring(Tags, 2, length(Tags)-2), '><'), 1)) as AvgTagsPerQuestion
    FROM Posts
    WHERE PostTypeId = 1 AND OwnerUserId IS NOT NULL AND Tags IS NOT NULL
    GROUP BY OwnerUserId
),
UserActivityTimeline AS (
    -- Create a unified timeline of significant user activities (answers, high-score comments, badges) using a set operator.
    SELECT
        UserId,
        CreationDate AS ActivityDate,
        'Posted Answer' AS ActivityType,
        Score::varchar(255) AS ActivityDetail
    FROM Posts
    WHERE PostTypeId = 2 AND UserId IS NOT NULL

    UNION ALL

    SELECT
        UserId,
        CreationDate AS ActivityDate,
        'Posted High-Score Comment' AS ActivityType,
        Score::varchar(255) AS ActivityDetail
    FROM Comments
    WHERE Score > 10 AND UserId IS NOT NULL

    UNION ALL

    SELECT
        UserId,
        Date AS ActivityDate,
        'Earned Badge' AS ActivityType,
        Name AS ActivityDetail
    FROM Badges
    WHERE UserId IS NOT NULL
),
RankedUserMetrics AS (
    -- Use window functions to analyze the activity timeline, calculating time between significant events.
    SELECT
        UserId,
        MAX(ActivityDate) AS LastActivityDate,
        AVG(EXTRACT(EPOCH FROM (ActivityDate - PreviousActivityDate))) AS AvgSecondsBetweenActivities
    FROM (
        SELECT
            UserId,
            ActivityDate,
            LAG(ActivityDate, 1) OVER (PARTITION BY UserId ORDER BY ActivityDate) AS PreviousActivityDate
        FROM UserActivityTimeline
    ) AS UserActivityWithLag
    WHERE PreviousActivityDate IS NOT NULL
    GROUP BY UserId
)
-- Final SELECT to combine all metrics, calculate a composite score, rank users, and filter for a specific cohort.
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    COALESCE(qs.TotalQuestions, 0) AS TotalQuestions,
    COALESCE(ans.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(ans.AvgAnswerScore, 0.0) AS AvgAnswerScore,
    COALESCE(ans.AcceptedAnswersCount, 0) AS AcceptedAnswers,
    rm.LastActivityDate,
    rm.AvgSecondsBetweenActivities,
    -- Complicated expression for a composite 'InfluenceScore'
    (u.Reputation * 0.15) + (COALESCE(ans.AvgAnswerScore, 0) * 25) + (COALESCE(ans.AcceptedAnswersCount, 0) * 15) + (u.UpVotes * 1.2) - (u.DownVotes * 1.5) AS InfluenceScore,
    -- CASE statement to categorize users into tiers based on their activity and reputation.
    CASE
        WHEN (u.Reputation > 100000 AND COALESCE(ans.AcceptedAnswersCount, 0) > 100) THEN 'Diamond Contributor'
        WHEN (u.Reputation > 25000 AND COALESCE(ans.AvgAnswerScore, 0) > 10) THEN 'Platinum Contributor'
        WHEN (u.Reputation > 5000) THEN 'Gold Contributor'
        ELSE 'Contributor'
    END AS UserTier,
    -- Correlated subquery to find the number of non-tag-based Gold badges.
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1 AND b.TagBased = 'f') AS GoldBadges,
    -- Window function in the final SELECT to rank users globally by their calculated score.
    DENSE_RANK() OVER (ORDER BY (u.Reputation * 0.15) + (COALESCE(ans.AvgAnswerScore, 0) * 25) + (COALESCE(ans.AcceptedAnswersCount, 0) * 15) + (u.UpVotes * 1.2) - (u.DownVotes * 1.5) DESC) AS InfluenceRank
FROM
    Users u
LEFT JOIN
    UserQuestionStats qs ON u.Id = qs.OwnerUserId
LEFT JOIN
    UserAnswerStats ans ON u.Id = ans.OwnerUserId
LEFT JOIN
    RankedUserMetrics rm ON u.Id = rm.UserId
-- Complex predicate including date logic, NULL checks, string matching, and a correlated subquery against an aggregate.
WHERE
    u.CreationDate < (CURRENT_TIMESTAMP - INTERVAL '5 year')
    AND u.Reputation > (SELECT AVG(Reputation) FROM Users)
    AND (u.AboutMe IS NOT NULL AND u.AboutMe <> '')
    AND COALESCE(ans.TotalAnswers, 0) > 5
    AND u.Id IN (
        -- Subquery to select users who have participated in closing posts.
        SELECT DISTINCT UserId
        FROM PostHistory
        WHERE PostHistoryTypeId = 10 AND UserId IS NOT NULL
    )
ORDER BY
    InfluenceRank, u.Id
LIMIT 200;

