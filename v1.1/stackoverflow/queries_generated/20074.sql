-- {"query": "20074.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1130} 

WITH QuestionStats AS (
    -- Step 1: Aggregate question data and rank questions for each user
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.CreationDate,
        p.AcceptedAnswerId,
        p.AnswerCount,
        -- Rank questions by a composite score for each user
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.FavoriteCount DESC, p.ViewCount DESC) as rn
    FROM Posts p
    WHERE
        p.PostTypeId = 1 -- Questions only
        AND p.DeletionDate IS NULL
        AND p.ClosedDate IS NULL
        AND p.AnswerCount > 0
),
UserBadgeCounts AS (
    -- Step 2: Pre-aggregate badge counts per user to avoid multiple subqueries
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
UserActivityUnion AS (
    -- Step 3: Combine different user activities using a set operator
    SELECT UserId, CreationDate, 'Answer' AS ActivityType FROM Posts WHERE PostTypeId = 2 AND UserId IS NOT NULL
    UNION ALL
    SELECT UserId, CreationDate, 'Comment' AS ActivityType FROM Comments WHERE UserId IS NOT NULL
)
-- Main Query: Analyze users, their top questions, and the accepted answers
SELECT
    u.DisplayName AS UserName,
    u.Reputation,
    qs.Title AS TopQuestionTitle,
    qs.Score AS QuestionScore,
    REPLACE(SUBSTRING(qs.Tags, 2, LENGTH(qs.Tags) - 2), '><', ', ') AS FormattedTags,
    -- Complex calculation for engagement ratio
    CAST(qs.FavoriteCount AS DECIMAL) / NULLIF(qs.ViewCount, 0) * 1000 AS EngagementRatio,
    -- Information about the accepted answer and its author
    ans.Score AS AcceptedAnswerScore,
    COALESCE(ans_u.DisplayName, 'Deleted User') AS AnswererDisplayName,
    COALESCE(ans_u.Reputation, -1) AS AnswererReputation,
    -- Time difference calculation
    EXTRACT(EPOCH FROM (ans.CreationDate - qs.CreationDate)) / 3600.0 AS HoursToAcceptedAnswer,
    -- Correlated subquery to find the user's next activity after posting the question
    (SELECT MIN(CreationDate) FROM UserActivityUnion uau WHERE uau.UserId = u.Id AND uau.CreationDate > qs.CreationDate) AS NextActivityDate,
    -- Window function to rank users based on the score of their top question within their reputation bracket
    DENSE_RANK() OVER (PARTITION BY
        CASE
            WHEN u.Reputation > 100000 THEN 'Elite'
            WHEN u.Reputation > 20000 THEN 'Veteran'
            WHEN u.Reputation > 5000 THEN 'Established'
            ELSE 'Member'
        END
    ORDER BY qs.Score DESC) AS RankInReputationBracket,
    -- String manipulation and NULL logic for badge display
    CONCAT('G:', COALESCE(ubc.GoldBadges, 0), ' S:', COALESCE(ubc.SilverBadges, 0), ' B:', COALESCE(ubc.BronzeBadges, 0)) AS UserBadges
FROM Users u
JOIN QuestionStats qs ON u.Id = qs.OwnerUserId
-- Use LEFT JOINs to handle cases where an accepted answer or its author might be missing
LEFT JOIN Posts ans ON qs.AcceptedAnswerId = ans.Id
LEFT JOIN Users ans_u ON ans.OwnerUserId = ans_u.Id
LEFT JOIN UserBadgeCounts ubc ON u.Id = ubc.UserId
WHERE
    qs.rn = 1 -- We only want each user's single top-ranked question
    AND u.Reputation > 1000 -- Filter for reasonably established users
    AND u.UpVotes > (u.DownVotes * 1.5) -- User has a positive voting record
    AND qs.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND DeletionDate IS NULL) -- Top question must be above average score
    AND ans.Id IS NOT NULL -- Ensure there is an accepted answer to analyze
    AND ans.OwnerUserId != qs.OwnerUserId -- Exclude self-answers
    AND qs.Title LIKE '%SQL%' -- Filter for questions related to a specific topic using a string predicate
ORDER BY
    u.Reputation DESC,
    qs.Score DESC
LIMIT 500;
