-- {"query": "20085.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1677} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        EXTRACT(YEAR FROM AGE(NOW(), u.CreationDate)) AS AccountAgeYears,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAsked,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersProvided,
        COUNT(c.Id) AS CommentsMade,
        SUM(p.Score) AS TotalPostScore,
        SUM(p.FavoriteCount) FILTER (WHERE p.PostTypeId = 1) AS TotalFavoriteCount,
        MAX(p.LastActivityDate) AS LastActivity
    FROM
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.Reputation > 15000 AND u.Id > 0 -- Filter for active, non-community users
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
AnswerPerformance AS (
    SELECT
        p.OwnerUserId,
        AVG(p.Score) AS AvgAnswerScore,
        SUM(CASE WHEN q.AcceptedAnswerId = p.Id THEN 1 ELSE 0 END) AS AcceptedAnswers,
        CAST(SUM(CASE WHEN q.AcceptedAnswerId = p.Id THEN 1 ELSE 0 END) AS REAL) / NULLIF(COUNT(p.Id), 0) AS AcceptanceRate,
        AVG(p.Score - AvgScoreByQuestion) AS AvgScoreDelta,
        SUM(CASE WHEN p.Score > AvgScoreByQuestion THEN 1 ELSE 0 END) AS AboveAverageAnswers
    FROM
        Posts p
    JOIN Posts q ON p.ParentId = q.Id
    JOIN (
        SELECT ParentId, AVG(Score) AS AvgScoreByQuestion
        FROM Posts
        WHERE ParentId IS NOT NULL
        GROUP BY ParentId
    ) AS QuestionAvg ON p.ParentId = QuestionAvg.ParentId
    WHERE
        p.PostTypeId = 2 AND p.OwnerUserId IS NOT NULL
    GROUP BY
        p.OwnerUserId
),
UserTimeline AS (
    SELECT
        UserId,
        ActivityDate,
        LAG(ActivityDate, 1) OVER (PARTITION BY UserId ORDER BY ActivityDate) AS PreviousActivityDate
    FROM (
        SELECT OwnerUserId AS UserId, CreationDate AS ActivityDate FROM Posts WHERE OwnerUserId IS NOT NULL
        UNION ALL
        SELECT UserId, CreationDate AS ActivityDate FROM Comments WHERE UserId IS NOT NULL
        UNION ALL
        SELECT UserId, CreationDate AS ActivityDate FROM Votes WHERE VoteTypeId IN (2, 3) AND UserId IS NOT NULL
    ) AS CombinedActivities
),
TagSpecialization AS (
    SELECT
        OwnerUserId,
        (array_agg(Tag ORDER BY TagCount DESC))[1] AS PrimaryTag,
        MAX(TagCount) AS PrimaryTagCount,
        COUNT(DISTINCT Tag) AS DistinctTagsUsed
    FROM (
        SELECT
            p.OwnerUserId,
            unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag,
            COUNT(*) AS TagCount
        FROM
            Posts p
        WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL AND p.Tags IS NOT NULL AND p.Tags != ''
        GROUP BY p.OwnerUserId, Tag
    ) AS UserTags
    GROUP BY OwnerUserId
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.AccountAgeYears,
    uas.QuestionsAsked,
    uas.AnswersProvided,
    uas.CommentsMade,
    COALESCE(uas.TotalPostScore, 0) AS TotalPostScore,
    COALESCE(uas.TotalFavoriteCount, 0) AS TotalFavoriteCount,
    COALESCE(ap.AcceptedAnswers, 0) AS AcceptedAnswers,
    COALESCE(ap.AcceptanceRate, 0.0) AS AcceptanceRate,
    COALESCE(ap.AboveAverageAnswers, 0) AS AboveAverageAnswers,
    ts.PrimaryTag,
    ts.DistinctTagsUsed,
    bg.GoldBadges,
    bg.SilverBadges,
    bg.BronzeBadges,
    EXTRACT(DAY FROM AVG(ut.ActivityDate - ut.PreviousActivityDate)) AS AvgDaysBetweenActivity,
    (
        SELECT crt.Name
        FROM PostHistory ph
        JOIN Posts p_closed ON ph.PostId = p_closed.Id
        JOIN CloseReasonTypes crt ON CAST(ph.Comment AS SMALLINT) = crt.Id
        WHERE ph.PostHistoryTypeId = 10 -- Post Closed
          AND p_closed.OwnerUserId = uas.UserId
        ORDER BY ph.CreationDate DESC
        LIMIT 1
    ) AS LastCloseReason,
    CONCAT(
        'Profile: ',
        LOWER(REPLACE(uas.DisplayName, ' ', '-')),
        ' | Location: ',
        COALESCE(NULLIF(u.Location, ''), 'Unknown')
    ) AS UserIdentifier,
    -- Complex scoring metric
    (uas.Reputation / 1000.0)
    + (COALESCE(ap.AcceptanceRate, 0) * 20)
    + (COALESCE(bg.GoldBadges, 0) * 10)
    + (LN(GREATEST(uas.AnswersProvided, 1)) * 2)
    - (uas.AccountAgeYears) AS CalculatedInfluenceScore
FROM
    UserActivitySummary uas
JOIN Users u ON uas.UserId = u.Id
LEFT JOIN AnswerPerformance ap ON uas.UserId = ap.OwnerUserId
LEFT JOIN TagSpecialization ts ON uas.UserId = ts.OwnerUserId
LEFT JOIN (
    SELECT
        UserId,
        COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
) AS bg ON uas.UserId = bg.UserId
LEFT JOIN UserTimeline ut ON uas.UserId = ut.UserId AND ut.PreviousActivityDate IS NOT NULL
WHERE
    (uas.AnswersProvided > uas.QuestionsAsked OR uas.AnswersProvided > 50)
    AND COALESCE(ap.AcceptanceRate, 0.0) > 0.15
    AND ts.DistinctTagsUsed > 10
    AND uas.LastActivity > (NOW() - INTERVAL '2 year')
GROUP BY
    uas.UserId, uas.DisplayName, uas.Reputation, uas.AccountAgeYears,
    uas.QuestionsAsked, uas.AnswersProvided, uas.CommentsMade, uas.TotalPostScore,
    uas.TotalFavoriteCount, ap.AcceptedAnswers, ap.AcceptanceRate, ap.AboveAverageAnswers,
    ts.PrimaryTag, ts.DistinctTagsUsed, bg.GoldBadges, bg.SilverBadges, bg.BronzeBadges,
    u.Location
ORDER BY
    CalculatedInfluenceScore DESC,
    uas.Reputation DESC
LIMIT 100;

