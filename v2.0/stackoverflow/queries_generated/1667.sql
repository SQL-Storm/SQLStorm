-- {"query": "1667.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2691} 
WITH UserQuestionStats AS (
    -- CTE 1: Summarize user's overall question and post activity
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount END) AS AvgQuestionViews,
        MAX(p.CreationDate) AS LastPostActivityDate,
        MIN(p.CreationDate) AS FirstPostActivityDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
QuestionEngagementDetails AS (
    -- CTE 2: Extract detailed information and computed metrics for specific questions
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.CreationDate AS QuestionCreationDate,
        q.Title AS QuestionTitle,
        q.Body AS QuestionBody,
        q.Tags,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.AcceptedAnswerId,
        a.CreationDate AS AcceptedAnswerCreationDate,
        a.OwnerUserId AS AcceptedAnswerOwnerUserId,
        -- Complex calculation: Time to accept an answer in hours, with NULL handling
        DATE_PART('day', a.CreationDate - q.CreationDate) * 24 +
        DATE_PART('hour', a.CreationDate - q.CreationDate) +
        DATE_PART('minute', a.CreationDate - q.CreationDate) / 60.0 +
        DATE_PART('second', a.CreationDate - q.CreationDate) / 3600.0 AS TimeToAcceptHours,
        COALESCE(ph_reopened.ReopenCount, 0) AS ReopenCount, -- NULL logic: default to 0
        STRING_TO_ARRAY(SUBSTRING(q.Tags, 2, LENGTH(q.Tags) - 2), '><') AS TagArray -- String expression to parse tags
    FROM Posts q
    JOIN PostTypes pt ON q.PostTypeId = pt.Id AND pt.Name = 'Question'
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id AND a.PostTypeId = 2 -- Accepted Answer must be an answer
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS ReopenCount
        FROM PostHistory
        WHERE PostHistoryTypeId = 11 -- 'Post Reopened' event
        GROUP BY PostId
    ) ph_reopened ON q.Id = ph_reopened.PostId
    WHERE q.CreationDate >= '2021-01-01' -- Focus on recent questions for performance
),
RelevantBadgeAchievements AS (
    -- CTE 3: Identify Gold or Silver badges related to specific tags or general excellence
    SELECT
        b.UserId AS BadgeRecipientId,
        b.Name AS BadgeName,
        b.Class AS BadgeClass,
        b.Date AS BadgeAwardDate,
        b.TagBased,
        LOWER(b.Name) AS LowerBadgeName -- String expression
    FROM Badges b
    WHERE b.Class IN (1, 2) -- Gold (1) or Silver (2) badges
      AND (
          LOWER(b.Name) LIKE '%sql%' OR LOWER(b.Name) LIKE '%database%' OR
          LOWER(b.Name) LIKE '%performance%' OR LOWER(b.Name) LIKE '%expert%'
      )
),
UserMonthlyPerformanceRank AS (
    -- CTE 4: Rank users by reputation within their creation month using window functions
    SELECT
        ugs.UserId,
        ugs.UserCreationDate,
        EXTRACT(YEAR FROM ugs.UserCreationDate) AS CreationYear,
        EXTRACT(MONTH FROM ugs.UserCreationDate) AS CreationMonth,
        ugs.Reputation,
        -- Window function: Average reputation of all users created in the same month
        AVG(ugs.Reputation) OVER (PARTITION BY EXTRACT(YEAR FROM ugs.UserCreationDate), EXTRACT(MONTH FROM ugs.UserCreationDate)) AS AvgReputationInMonthCohort,
        -- Window function: Rank users by reputation within their creation month
        RANK() OVER (PARTITION BY EXTRACT(YEAR FROM ugs.UserCreationDate), EXTRACT(MONTH FROM ugs.UserCreationDate) ORDER BY ugs.Reputation DESC, ugs.UserId) AS RankInMonthByReputation
    FROM UserQuestionStats ugs
),
QualifiedQuestionsSummary AS (
    -- CTE 5: Filter questions based on specific criteria and include correlated subquery
    SELECT
        qed.OwnerUserId AS ContributorId,
        qed.QuestionId,
        qed.QuestionTitle,
        qed.QuestionCreationDate,
        qed.TimeToAcceptHours,
        qed.ReopenCount,
        qed.QuestionScore,
        qed.ViewCount,
        qed.AnswerCount,
        qed.AcceptedAnswerOwnerUserId,
        -- Correlated subquery: Calculate the average score of other questions by the same owner in the same year
        (SELECT AVG(sub_p.Score)
         FROM Posts sub_p
         WHERE sub_p.OwnerUserId = qed.OwnerUserId
           AND sub_p.PostTypeId = 1
           AND sub_p.Id != qed.QuestionId -- Exclude the current question
           AND EXTRACT(YEAR FROM sub_p.CreationDate) = EXTRACT(YEAR FROM qed.QuestionCreationDate)
           AND sub_p.Score IS NOT NULL
        ) AS AvgOtherQuestionScoreByOwner,
        COALESCE(qed.Tags, '[untagged]') AS FormattedTags -- NULL logic
    FROM QuestionEngagementDetails qed
    WHERE qed.AnswerCount >= 2
      AND qed.TimeToAcceptHours IS NOT NULL AND qed.TimeToAcceptHours BETWEEN 0.0 AND 48.0 -- Accepted within 48 hours
      AND (
          'sql' = ANY(qed.TagArray) OR 'postgresql' = ANY(qed.TagArray) OR -- Array comparison for tags
          'performance' = ANY(qed.TagArray) OR 'optimization' = ANY(qed.TagArray)
      )
      AND (
          LOWER(qed.QuestionTitle) LIKE '%index%' OR -- String expression and complicated predicate
          LOWER(qed.QuestionBody) LIKE '%explain analyze%' OR
          LOWER(qed.QuestionTitle) LIKE '%query plan%'
      )
),
-- CTE 6: Use a set operator to combine users who got badges for their questions
-- with users whose accepted answers earned badges.
UserBadgeContexts AS (
    SELECT
        qss.ContributorId AS UserId,
        qss.QuestionId,
        qss.QuestionTitle,
        'Question_Owner_Badge' AS BadgeContext,
        rba.BadgeName
    FROM QualifiedQuestionsSummary qss
    JOIN RelevantBadgeAchievements rba ON qss.ContributorId = rba.BadgeRecipientId
    WHERE rba.TagBased = FALSE -- Only general badges for the question owner
    UNION ALL
    SELECT
        qss.AcceptedAnswerOwnerUserId AS UserId,
        qss.QuestionId,
        qss.QuestionTitle,
        'Accepted_Answer_Owner_Badge' AS BadgeContext,
        rba.BadgeName
    FROM QualifiedQuestionsSummary qss
    JOIN RelevantBadgeAchievements rba ON qss.AcceptedAnswerOwnerUserId = rba.BadgeRecipientId
    WHERE qss.AcceptedAnswerOwnerUserId IS NOT NULL
      AND rba.TagBased = TRUE AND rba.LowerBadgeName = ANY(STRING_TO_ARRAY(SUBSTRING(qss.FormattedTags, 2, LENGTH(qss.FormattedTags) - 2), '><')) -- Badge is tag-based and matches a question tag
)
-- Main query: Aggregate results and apply final filters and ordering
SELECT
    ump.UserId,
    ugs.UserName,
    ugs.Reputation,
    ump.UserCreationDate,
    ump.CreationYear,
    ump.CreationMonth,
    ump.AvgReputationInMonthCohort,
    ump.RankInMonthByReputation,
    COUNT(DISTINCT qqs.QuestionId) AS TotalQualifiedQuestions,
    AVG(qqs.TimeToAcceptHours) AS AvgTimeToAcceptQualified,
    SUM(qqs.ReopenCount) AS SumReopensOnQualifiedQuestions,
    SUM(qqs.QuestionScore) AS SumQualifiedQuestionScore,
    AVG(qqs.AvgOtherQuestionScoreByOwner) AS AvgOtherQScoreByOwner,
    STRING_AGG(DISTINCT ubc.BadgeName || ' (' || ubc.BadgeContext || ')', '; ') AS AssociatedBadges, -- Aggregate string with context
    -- Complex conditional expression based on various metrics
    CASE
        WHEN ugs.Reputation > 75000 AND ump.RankInMonthByReputation = 1 AND COUNT(DISTINCT qqs.QuestionId) >= 5 THEN 'Elite_Top_Monthly_Contributor'
        WHEN ugs.Reputation > 20000 AND AVG(qqs.TimeToAcceptHours) IS NOT NULL AND AVG(qqs.TimeToAcceptHours) < 12 AND SUM(qqs.ReopenCount) = 0 THEN 'High_Impact_Fast_Acceptor_Zero_Reopens'
        WHEN ugs.TotalQuestionsAsked IS NULL OR ugs.TotalQuestionsAsked = 0 THEN 'No_Relevant_Questions_Found'
        ELSE 'Active_Qualified_Contributor'
    END AS UserContributionCategory,
    -- Complicated numeric calculation with NULLIF for division by zero
    CAST(SUM(qqs.QuestionScore) AS NUMERIC) / NULLIF(ugs.TotalQuestionScore, 0) AS QualifiedToTotalQuestionScoreRatio,
    -- Another window function: Moving average of their own question scores over a theoretical 3-month window (approximated here by grouping and ordering)
    AVG(qqs.QuestionScore) OVER (PARTITION BY umps.CreationYear, umps.CreationMonth ORDER BY qqs.QuestionCreationDate) AS MovingAvgQualifiedQuestionScore
FROM UserMonthlyPerformanceRank ump
JOIN UserQuestionStats ugs ON ump.UserId = ugs.UserId
LEFT JOIN QualifiedQuestionsSummary qqs ON ugs.UserId = qqs.ContributorId
LEFT JOIN UserBadgeContexts ubc ON ugs.UserId = ubc.UserId AND qqs.QuestionId = ubc.QuestionId
LEFT JOIN UserMonthlyPerformanceRank umps ON ump.UserId = umps.UserId -- For the moving average
WHERE ugs.TotalQuestionsAsked IS NOT NULL AND ugs.TotalQuestionsAsked > 0
  AND ugs.AvgQuestionViews IS NOT NULL AND ugs.AvgQuestionViews > 500
  AND ump.Reputation IS NOT NULL AND ump.Reputation > 5000
GROUP BY
    ump.UserId, ugs.UserName, ugs.Reputation, ump.UserCreationDate, ump.CreationYear, ump.CreationMonth,
    ump.AvgReputationInMonthCohort, ump.RankInMonthByReputation, ugs.TotalQuestionsAsked, ugs.TotalQuestionScore,
    qqs.QuestionCreationDate -- Added for moving average in main select, though it will make the group larger
HAVING
    COUNT(DISTINCT qqs.QuestionId) > 0 -- Must have at least one qualified question
    OR COUNT(DISTINCT ubc.BadgeName) > 0 -- Or received a relevant badge
ORDER BY
    ugs.Reputation DESC, TotalQualifiedQuestions DESC, AvgTimeToAcceptQualified ASC NULLS LAST
LIMIT 100;