-- {"query": "20007.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1498} 

WITH PowerUsers AS (
    -- Section 1: Identify influential users based on reputation and high-value badges.
    -- This CTE establishes our primary cohort of 'experts'.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        EXTRACT(YEAR FROM AGE(NOW(), u.CreationDate)) AS AccountAgeYears
    FROM
        Users u
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    WHERE
        u.Reputation > 75000 AND u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 100
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
    HAVING
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) >= 5 -- At least 5 gold badges
        AND COUNT(CASE WHEN b.Class = 2 THEN 1 END) >= 30 -- At least 30 silver badges
),
UserPostContributions AS (
    -- Section 2: Analyze the answers provided by these power users.
    -- We use a window function to rank each user's answers by score to find their 'best' work.
    SELECT
        p_ans.OwnerUserId,
        p_ans.Id AS AnswerId,
        p_ans.ParentId AS QuestionId,
        p_ans.Score AS AnswerScore,
        p_ans.CreationDate AS AnswerCreationDate,
        p_ans.Body,
        p_que.AcceptedAnswerId = p_ans.Id AS IsAcceptedAnswer,
        p_que.Tags AS QuestionTags,
        EXTRACT(EPOCH FROM (p_ans.CreationDate - p_que.CreationDate)) / 3600.0 AS HoursToAnswer,
        ROW_NUMBER() OVER(PARTITION BY p_ans.OwnerUserId ORDER BY p_ans.Score DESC, p_ans.CreationDate ASC) AS UserAnswerRank
    FROM
        Posts p_ans
    JOIN
        Posts p_que ON p_ans.ParentId = p_que.Id AND p_que.PostTypeId = 1
    WHERE
        p_ans.PostTypeId = 2 -- Answers
        AND p_ans.OwnerUserId IN (SELECT UserId FROM PowerUsers)
),
AggregatedUserStats AS (
    -- Section 3: Aggregate contribution stats for each power user.
    -- This provides a summary of their answering performance.
    SELECT
        OwnerUserId,
        COUNT(*) AS TotalAnswers,
        AVG(AnswerScore) AS AverageAnswerScore,
        MAX(AnswerScore) AS BestAnswerScore,
        SUM(CASE WHEN IsAcceptedAnswer THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS AcceptanceRate,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY HoursToAnswer) AS MedianHoursToAnswer
    FROM
        UserPostContributions
    GROUP BY
        OwnerUserId
),
-- Section 4: Define a contrasting group of users - those who ask many questions that often go unanswered.
ProlificAskers AS (
    SELECT
        OwnerUserId AS UserId,
        COUNT(*) AS QuestionsAsked,
        SUM(CASE WHEN AnswerCount = 0 AND ClosedDate IS NULL THEN 1 ELSE 0 END) AS UnansweredQuestions,
        AVG(Score) AS AvgQuestionScore,
        AVG(ViewCount) AS AvgViewCount,
        -- Find the ID of their most viewed question
        (ARRAY_AGG(Id ORDER BY ViewCount DESC))[1] AS MostViewedQuestionId
    FROM Posts
    WHERE PostTypeId = 1 AND OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
    HAVING COUNT(*) > 50 AND SUM(CASE WHEN AnswerCount = 0 AND ClosedDate IS NULL THEN 1 ELSE 0 END) > 15
)
-- Final Assembly: Combine the two user profiles using a UNION operator for a comparative benchmark.
SELECT
    'Power Answerer' AS UserProfile,
    pu.DisplayName,
    pu.Reputation,
    aus.TotalAnswers AS ContributionCount,
    ROUND(aus.AverageAnswerScore, 2) AS AvgContributionScore,
    -- Complex string manipulation and conditional logic
    CONCAT(
        'Best Answer in Tag: ',
        (string_to_array(substring(upc.QuestionTags, 2, length(upc.QuestionTags)-2), '><'))[1],
        '. Accepted: ',
        CASE WHEN upc.IsAcceptedAnswer THEN 'Yes' ELSE 'No' END
    ) AS PrimaryInfo,
    -- Correlated subquery to find the latest edit reason on their best answer
    (SELECT ph.Comment
     FROM PostHistory ph
     WHERE ph.PostId = upc.AnswerId AND ph.PostHistoryTypeId IN (4, 5, 6)
     ORDER BY ph.CreationDate DESC
     LIMIT 1) AS LastEditReason,
    NTILE(100) OVER (ORDER BY pu.Reputation DESC, aus.AverageAnswerScore DESC) AS PerformancePercentile
FROM
    PowerUsers pu
JOIN
    AggregatedUserStats aus ON pu.UserId = aus.OwnerUserId
JOIN
    UserPostContributions upc ON pu.UserId = upc.OwnerUserId AND upc.UserAnswerRank = 1
WHERE
    aus.AcceptanceRate > 25.0 AND pu.AccountAgeYears > 3

UNION ALL

SELECT
    'Struggling Asker' AS UserProfile,
    u.DisplayName,
    u.Reputation,
    pa.QuestionsAsked AS ContributionCount,
    ROUND(pa.AvgQuestionScore, 2) AS AvgContributionScore,
    -- Subquery within the SELECT to retrieve the title of the most viewed question
    (SELECT Title FROM Posts WHERE Id = pa.MostViewedQuestionId) AS PrimaryInfo,
    -- Logic involving NULLs and division
    'Unanswered Ratio: ' || ROUND((pa.UnansweredQuestions * 100.0 / NULLIF(pa.QuestionsAsked, 0)), 2) || '%' AS LastEditReason,
    NTILE(100) OVER (ORDER BY (pa.UnansweredQuestions * 1.0 / pa.QuestionsAsked) DESC, pa.AvgQuestionScore ASC) AS PerformancePercentile
FROM
    ProlificAskers pa
JOIN
    Users u ON pa.UserId = u.Id
WHERE
    u.Reputation < 10000 AND pa.AvgQuestionScore < 0.5

ORDER BY
    UserProfile, PerformancePercentile, Reputation DESC;
