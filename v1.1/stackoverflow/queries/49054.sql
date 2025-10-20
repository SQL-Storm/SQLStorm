-- {"query": "49054.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1523} 
WITH FilteredQuestions AS (
    -- Identify questions tagged with a specific technology (e.g., 'python') that were created after a certain date.
    -- This helps focus the analysis on relevant and potentially more active recent content.
    SELECT
        Id AS QuestionId,
        CreationDate AS QuestionCreationDate
    FROM Posts
    WHERE PostTypeId = 1 -- PostTypeId = 1 indicates a 'Question'
      AND Tags LIKE '%<python>%' -- String pattern matching for the specific tag, wrapped in angle brackets
      AND CreationDate >= '2020-01-01' -- Filter for questions created from a specific date onwards
),
HighlyScoredAnswers AS (
    -- Select answers to the filtered questions that have received a minimum score,
    -- and concurrently count the number of comments each of these answers has received.
    SELECT
        p.Id AS AnswerId,
        p.OwnerUserId,
        p.Score AS AnswerScore,
        p.ParentId AS QuestionId, -- ParentId links an answer back to its question
        p.CreationDate AS AnswerCreationDate,
        COUNT(c.Id) AS CommentCount -- Count comments for each answer
    FROM Posts p
    JOIN FilteredQuestions fq ON p.ParentId = fq.QuestionId
    LEFT JOIN Comments c ON p.Id = c.PostId -- Left join to include answers with no comments
    WHERE p.PostTypeId = 2 -- PostTypeId = 2 indicates an 'Answer'
      AND p.Score >= 5     -- Filter for answers considered 'highly scored'
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ParentId, p.CreationDate
),
UserAnswerSummary AS (
    -- Aggregate statistics for each user based on their highly scored answers to the filtered questions.
    SELECT
        hsa.OwnerUserId AS UserId,
        COUNT(DISTINCT hsa.AnswerId) AS TotalAnswersToTaggedQuestions, -- Total unique highly scored answers
        AVG(hsa.AnswerScore) AS AvgAnswerScoreForTaggedQuestions,
        SUM(hsa.CommentCount) AS TotalCommentsOnTaggedAnswers,
        MAX(hsa.AnswerCreationDate) AS LastAnswerDate -- Most recent activity related to these answers
    FROM HighlyScoredAnswers hsa
    GROUP BY hsa.OwnerUserId
),
UserBadgeSummary AS (
    -- Count the number of Gold, Silver, and Bronze badges for each user.
    -- This provides insight into a user's overall recognition and expertise.
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,   -- Class 1 for Gold
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges, -- Class 2 for Silver
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges  -- Class 3 for Bronze
    FROM Badges b
    GROUP BY b.UserId
),
QuestionHistoryAgg AS (
    -- Calculate the total number of history events (edits, closures, etc.) for each unique question
    -- that has received at least one highly scored answer in our filtered set.
    -- This can indicate how much a question has evolved or been moderated.
    SELECT
        ph.PostId AS QuestionId,
        COUNT(ph.Id) AS HistoryEventsCount
    FROM PostHistory ph
    WHERE ph.PostId IN (SELECT QuestionId FROM FilteredQuestions) -- Ensure we only consider history for relevant questions
    GROUP BY ph.PostId
),
UserAnsweredQuestionHistory AS (
    -- For each user, sum up the history events of the *unique* questions they provided highly-scored answers for.
    -- Also count the number of distinct questions they answered in this context.
    SELECT
        hsa.OwnerUserId AS UserId,
        SUM(qha.HistoryEventsCount) AS TotalHistoryEventsOnAnsweredQuestions,
        COUNT(DISTINCT hsa.QuestionId) AS UniqueQuestionsAnsweredCount
    FROM HighlyScoredAnswers hsa
    JOIN QuestionHistoryAgg qha ON hsa.QuestionId = qha.QuestionId
    GROUP BY hsa.OwnerUserId
)
-- Final selection and aggregation to combine all computed metrics for top users.
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    uas.TotalAnswersToTaggedQuestions,
    uas.AvgAnswerScoreForTaggedQuestions,
    uas.TotalCommentsOnTaggedAnswers,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,   -- Handle users with no badges of a specific class
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    uaqh.TotalHistoryEventsOnAnsweredQuestions,
    -- Calculate the average history events per unique question answered by the user
    CAST(uaqh.TotalHistoryEventsOnAnsweredQuestions AS DECIMAL) / uaqh.UniqueQuestionsAnsweredCount AS AvgHistoryEventsPerUniqueAnsweredQuestion
FROM Users u
JOIN UserAnswerSummary uas ON u.Id = uas.UserId -- Join with user answer statistics
LEFT JOIN UserBadgeSummary ubs ON u.Id = ubs.UserId -- Left join as not all users may have badges
LEFT JOIN UserAnsweredQuestionHistory uaqh ON u.Id = uaqh.UserId -- Left join for history statistics
WHERE u.Reputation >= 10000 -- Filter for highly reputable users
  AND uas.TotalAnswersToTaggedQuestions >= 10 -- Users with significant contributions to the specific tag
  AND uaqh.TotalHistoryEventsOnAnsweredQuestions IS NOT NULL -- Exclude users who answered no questions with history
  AND uaqh.UniqueQuestionsAnsweredCount > 0 -- Ensure no division by zero for the average calculation
GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    uas.TotalAnswersToTaggedQuestions, uas.AvgAnswerScoreForTaggedQuestions,
    uas.TotalCommentsOnTaggedAnswers,
    COALESCE(ubs.GoldBadges, 0), COALESCE(ubs.SilverBadges, 0), COALESCE(ubs.BronzeBadges, 0),
    uaqh.TotalHistoryEventsOnAnsweredQuestions, uaqh.UniqueQuestionsAnsweredCount
ORDER BY
    u.Reputation DESC,
    AvgHistoryEventsPerUniqueAnsweredQuestion DESC,
    uas.AvgAnswerScoreForTaggedQuestions DESC,
    TotalHistoryEventsOnAnsweredQuestions DESC
LIMIT 75;