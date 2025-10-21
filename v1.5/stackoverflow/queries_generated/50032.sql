-- {"query": "50032.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1604} 

WITH UserPostStats AS (
    -- Aggregate post-related metrics for each user to measure contribution and engagement
    SELECT
        p.OwnerUserId,
        SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.ViewCount, 0) ELSE 0 END) AS TotalQuestionViews,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        COUNT(CASE WHEN p.PostTypeId = 2 AND q.AcceptedAnswerId = p.Id THEN 1 END) AS AcceptedAnswersCount,
        MIN(p.CreationDate) AS FirstPostDate,
        MAX(p.LastActivityDate) AS LastPostActivityDate
    FROM Posts AS p
    -- A post 'p' of type Answer (2) is joined with a post 'q' if 'q' has accepted 'p' as the answer
    LEFT JOIN Posts AS q ON p.Id = q.AcceptedAnswerId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserBadgeStats AS (
    -- Aggregate badge counts by class (Gold, Silver, Bronze) for each user
    SELECT
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
UserInteractionStats AS (
    -- Consolidate user's last interaction date from votes and comments
    SELECT
        UserId,
        MAX(CreationDate) as LastInteractionDate
    FROM (
        SELECT UserId, CreationDate FROM Votes WHERE UserId IS NOT NULL
        UNION ALL
        SELECT UserId, CreationDate FROM Comments WHERE UserId IS NOT NULL
    ) AS AllInteractions
    GROUP BY UserId
),
RankedUsers AS (
    -- Combine all statistics, calculate a composite 'InfluenceScore', and rank users within their location
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        ps.TotalQuestionViews,
        ps.TotalAnswerScore,
        ps.AcceptedAnswersCount,
        bs.GoldBadges,
        bs.SilverBadges,
        bs.BronzeBadges,
        GREATEST(u.LastAccessDate, ps.LastPostActivityDate, uis.LastInteractionDate) as LastSeenDate,
        -- Calculate a weighted influence score based on multiple user metrics
        (
            (u.Reputation * 0.1) +
            (COALESCE(ps.TotalAnswerScore, 0) * 0.25) +
            (COALESCE(ps.AcceptedAnswersCount, 0) * 20) +
            (COALESCE(ps.TotalQuestionViews, 0) * 0.05) +
            (COALESCE(bs.GoldBadges, 0) * 100) +
            (COALESCE(bs.SilverBadges, 0) * 50) +
            (COALESCE(bs.BronzeBadges, 0) * 25) +
            (u.UpVotes * 0.1) - (u.DownVotes * 0.2)
        ) AS InfluenceScore,
        -- Use a window function to rank users within their location by the calculated score
        DENSE_RANK() OVER (PARTITION BY u.Location ORDER BY (
            (u.Reputation * 0.1) +
            (COALESCE(ps.TotalAnswerScore, 0) * 0.25) +
            (COALESCE(ps.AcceptedAnswersCount, 0) * 20) +
            (COALESCE(ps.TotalQuestionViews, 0) * 0.05) +
            (COALESCE(bs.GoldBadges, 0) * 100) +
            (COALESCE(bs.SilverBadges, 0) * 50) +
            (COALESCE(bs.BronzeBadges, 0) * 25) +
            (u.UpVotes * 0.1) - (u.DownVotes * 0.2)
        ) DESC) AS LocationRank
    FROM Users AS u
    JOIN UserPostStats AS ps ON u.Id = ps.OwnerUserId
    LEFT JOIN UserBadgeStats AS bs ON u.Id = bs.UserId
    LEFT JOIN UserInteractionStats AS uis ON u.Id = uis.UserId
    -- Filter for active, established users in defined locations to ensure meaningful data
    WHERE
        u.Reputation > 10000 AND
        u.CreationDate BETWEEN '2015-01-01' AND '2023-01-01' AND
        u.Location IS NOT NULL AND u.Location != '' AND
        ps.TotalAnswerScore > 100
)
-- Final selection: Retrieve top users per location, find their most answered tag, and get stats for that tag
SELECT
    ru.UserId,
    ru.DisplayName,
    ru.Location,
    ru.Reputation,
    CAST(ru.InfluenceScore AS BIGINT) AS InfluenceScore,
    ru.LocationRank,
    TopAnsweredTag.tag AS MostFrequentAnswerTag,
    TagInfo.QuestionCount AS QuestionsWithTag,
    CAST(TagInfo.AverageScore AS DECIMAL(10, 2)) AS AvgScoreForTag
FROM RankedUsers AS ru
-- This LATERAL join is computationally expensive: for each ranked user, it calculates their most frequent tag
CROSS JOIN LATERAL (
    SELECT
        t.tag
    FROM (
        -- Unnest the tag string from all questions the user has answered
        SELECT unnest(string_to_array(substring(p_question.Tags, 2, length(p_question.Tags) - 2), '><')) AS tag
        FROM Posts AS p_answer
        JOIN Posts AS p_question ON p_answer.ParentId = p_question.Id
        WHERE p_answer.OwnerUserId = ru.UserId
          AND p_answer.PostTypeId = 2 -- It's an answer
          AND p_question.Tags IS NOT NULL
    ) AS t
    WHERE t.tag IS NOT NULL AND t.tag <> ''
    GROUP BY t.tag
    ORDER BY COUNT(*) DESC, t.tag
    LIMIT 1
) AS TopAnsweredTag
-- This second LATERAL join gets aggregate stats for the tag identified above
LEFT JOIN LATERAL (
    SELECT
        COUNT(*) AS QuestionCount,
        AVG(Score) AS AverageScore
    FROM Posts
    WHERE PostTypeId = 1 AND Tags LIKE '%' || TopAnsweredTag.tag || '%'
) AS TagInfo ON true
WHERE
    ru.LocationRank <= 5 -- Only select the top 5 users per location
ORDER BY
    ru.Location,
    ru.LocationRank,
    ru.InfluenceScore DESC
LIMIT 200;
