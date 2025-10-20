-- {"query": "20040.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1507} 

WITH UserActivitySummary AS (
    -- CTE 1: Aggregate user-level statistics and initial filtering for active, high-rep users.
    -- This includes correlated subqueries to get badge counts, adding to the load.
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.AboutMe,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(DISTINCT p.Id) FROM Posts p WHERE p.OwnerUserId = u.Id) AS TotalPosts,
        (SELECT COUNT(DISTINCT c.Id) FROM Comments c WHERE c.UserId = u.Id) AS TotalComments
    FROM
        Users u
    WHERE
        u.Reputation > 15000
        AND u.CreationDate < (CURRENT_DATE - INTERVAL '5 year')
        AND u.AboutMe IS NOT NULL
),
RankedAnswers AS (
    -- CTE 2: Analyze user answers, using window functions to rank them and calculate response times.
    SELECT
        a.Id AS AnswerId,
        a.OwnerUserId,
        a.Score AS AnswerScore,
        q.Title AS QuestionTitle,
        q.Tags AS QuestionTags,
        q.ViewCount AS QuestionViewCount,
        a.CreationDate AS AnswerCreationDate,
        (a.CreationDate - q.CreationDate) AS ResponseTime,
        ROW_NUMBER() OVER(PARTITION BY a.OwnerUserId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank,
        AVG(a.Score) OVER(PARTITION BY a.OwnerUserId) AS AvgUserAnswerScore,
        MAX(a.Score) OVER(PARTITION BY a.OwnerUserId) AS MaxUserAnswerScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY a.Id) AS UpvotesOnAnswer
    FROM
        Posts a
    JOIN
        Posts q ON a.ParentId = q.Id
    LEFT JOIN
        Votes v ON a.Id = v.PostId
    WHERE
        a.PostTypeId = 2 -- Answers
        AND a.OwnerUserId IS NOT NULL
),
RecentActions AS (
    -- CTE 3: Use set operators to combine different types of recent user actions into a single timeline.
    SELECT UserId, CreationDate, 'Post' AS ActionType FROM Posts WHERE CreationDate > (CURRENT_TIMESTAMP - INTERVAL '1 year')
    UNION ALL
    SELECT UserId, CreationDate, 'Comment' AS ActionType FROM Comments WHERE CreationDate > (CURRENT_TIMESTAMP - INTERVAL '1 year')
    UNION ALL
    SELECT UserId, CreationDate, 'Vote' AS ActionType FROM Votes WHERE VoteTypeId IN (2, 3, 5) AND CreationDate > (CURRENT_TIMESTAMP - INTERVAL '1 year')
)
SELECT
    uas.DisplayName,
    uas.Reputation,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.TotalPosts,
    ra.AnswerScore AS TopAnswerScore,
    ra.AvgUserAnswerScore,
    -- Complicated CASE statement for user categorization
    CASE
        WHEN uas.Reputation > 200000 AND uas.GoldBadges > 15 AND ra.AvgUserAnswerScore > 20 THEN 'Community Pillar'
        WHEN uas.Reputation > 100000 OR uas.GoldBadges > 10 THEN 'Esteemed Contributor'
        WHEN uas.TotalPosts > 1000 AND ra.AvgUserAnswerScore > 5 THEN 'Power User'
        ELSE 'Regular High-Rep User'
    END AS UserTier,
    -- Complex scoring formula involving logs, COALESCE for NULL handling, and multiple metrics
    (LOG(1 + uas.Reputation) * 10) + (uas.GoldBadges * 25) + (uas.SilverBadges * 10) + COALESCE(ra.AvgUserAnswerScore, 0) * 1.5 - (EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - uas.CreationDate)) / 31536000) AS EngagementScore,
    -- String manipulation and NULL logic
    COALESCE(NULLIF(SUBSTRING(uas.Location FROM '([a-zA-Z\s]+)$'), ''), 'Location Undefined') AS ParsedLocation,
    ra.QuestionTags AS TopAnswerQuestionTags,
    -- Window functions in the final select
    DENSE_RANK() OVER (ORDER BY (LOG(1 + uas.Reputation) * 10) + (uas.GoldBadges * 25) + (uas.SilverBadges * 10) + COALESCE(ra.AvgUserAnswerScore, 0) * 1.5 - (EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - uas.CreationDate)) / 31536000) DESC) AS UserRank,
    LAG(uas.DisplayName, 1, 'N/A') OVER (ORDER BY (LOG(1 + uas.Reputation) * 10) + (uas.GoldBadges * 25) + (uas.SilverBadges * 10) + COALESCE(ra.AvgUserAnswerScore, 0) * 1.5 - (EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - uas.CreationDate)) / 31536000) DESC) AS PreviousRankedUser
FROM
    UserActivitySummary uas
LEFT JOIN
    -- Outer join to include users who might not have answers
    RankedAnswers ra ON uas.Id = ra.OwnerUserId AND ra.AnswerRank = 1
WHERE
    -- Complicated predicate combining different data points
    uas.TotalComments > uas.TotalPosts
    AND LENGTH(uas.AboutMe) > 150
    AND (ra.QuestionTags LIKE '%<sql>%' OR ra.QuestionTags LIKE '%<performance>%')
    -- Correlated subquery to check for recent activity from the third CTE
    AND EXISTS (
        SELECT 1
        FROM RecentActions r_act
        WHERE r_act.UserId = uas.Id
          AND r_act.CreationDate > (CURRENT_TIMESTAMP - INTERVAL '6 months')
    )
ORDER BY
    UserRank ASC,
    uas.Reputation DESC
LIMIT 100;

