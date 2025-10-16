-- {"query": "19081.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3673} 

WITH QuestionBase AS (
    -- Filters and enriches core question data, applying initial complex predicate and NULL logic for acceptance status.
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate AS QuestionCreationDate,
        p.ViewCount AS QuestionViewCount,
        p.Score AS QuestionScore,
        p.Tags,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.CommentCount AS QuestionCommentCount,
        p.FavoriteCount AS QuestionFavoriteCount,
        -- Complicated string predicate: identify questions potentially related to SQL/databases but excluding NoSQL.
        (LOWER(p.Title) LIKE '%sql%' OR LOWER(p.Title) LIKE '%database%' OR LOWER(p.Body) LIKE '%transaction%')
        AND LOWER(p.Title) NOT LIKE '%nosql%'
        AND LOWER(p.Body) NOT LIKE '%mongodb%' AS IsSqlRelated,
        -- NULL logic with CASE statement to classify acceptance status.
        CASE
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
            WHEN p.AnswerCount > 0 AND p.AcceptedAnswerId IS NULL THEN 'Unaccepted (Has Answers)'
            ELSE 'No Answer Yet'
        END AS AcceptanceStatus
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1 -- Only questions
        AND p.CreationDate >= '2021-01-01' -- Filter for relatively recent questions
        AND p.ViewCount > 750 -- Ensure sufficient visibility
        AND p.OwnerUserId IS NOT NULL -- Exclude questions from deleted users for owner analysis
),
UserActivitySummary AS (
    -- Aggregates user statistics, includes a correlated subquery for badge count.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        u.Location,
        u.CreationDate AS UserCreationDate,
        -- Complex calculation: UpVoteRatio, handling division by zero.
        CAST(u.UpVotes AS NUMERIC) / NULLIF(u.UpVotes + u.DownVotes, 0) AS UpVoteRatio,
        -- Correlated subquery: count user's gold badges directly from Badges table.
        (SELECT COUNT(b.Id) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadgeCount
    FROM
        Users u
    WHERE u.Reputation > 500 -- Focus on more established users
),
AnswerAndCommentAnalysis AS (
    -- Analyzes answers and comments, demonstrating outer joins, aggregation, window functions, and string expressions.
    SELECT
        qb.QuestionId,
        qb.AcceptedAnswerId,
        qb.QuestionScore,
        a.Id AS AcceptedAnswerPostId,
        a.Score AS AcceptedAnswerScore,
        a.CreationDate AS AcceptedAnswerCreationDate,
        -- String expression: calculate length of accepted answer body.
        LENGTH(a.Body) AS AcceptedAnswerBodyLength,
        -- Window function: ranks all answers for a question by score, handling ties by creation date.
        RANK() OVER (PARTITION BY qb.QuestionId ORDER BY a_all.Score DESC, a_all.CreationDate ASC) AS AnswerRankByScore,
        COUNT(DISTINCT a_all.Id) AS TotalAnswersForQuestion,
        -- Aggregation: sum of scores for comments on the question. COALESCE handles NULL comment scores.
        SUM(COALESCE(qc.Score, 0)) AS TotalQuestionCommentScore,
        -- String expression: Concatenates and truncates top-scoring comments on the question.
        SUBSTRING(STRING_AGG(qc.Text, ' || ' ORDER BY qc.Score DESC), 1, 500) AS TopQuestionCommentsExcerpt
    FROM
        QuestionBase qb
    LEFT JOIN Posts a ON qb.AcceptedAnswerId = a.Id AND a.PostTypeId = 2 -- Accepted answer details (outer join for questions without accepted answer)
    LEFT JOIN Posts a_all ON qb.QuestionId = a_all.ParentId AND a_all.PostTypeId = 2 -- All answers for ranking (outer join)
    LEFT JOIN Comments qc ON qb.QuestionId = qc.PostId -- Comments on the question itself (outer join)
    GROUP BY
        qb.QuestionId, qb.AcceptedAnswerId, qb.QuestionScore, a.Id, a.Score, a.CreationDate, LENGTH(a.Body)
),
PostHistoryTimeline AS (
    -- Summarizes post history, calculating edit durations and identifying closure/reopening events.
    SELECT
        qb.QuestionId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        COUNT(DISTINCT ph.UserId) AS DistinctHistoryEditors,
        MAX(ph.CreationDate) AS LastHistoryEditDate,
        -- NULL logic with MAX and CASE to determine if the post was ever closed or reopened.
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasEverClosed, -- Post Closed
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasEverReopened, -- Post Reopened
        -- Complicated calculation: difference in days between first and last significant history event.
        DATE_PART('day', MAX(ph.CreationDate) - MIN(ph.CreationDate)) AS DaysBetweenFirstAndLastEdit
    FROM
        QuestionBase qb
    JOIN PostHistory ph ON qb.QuestionId = ph.PostId
    WHERE
        ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 10, 11, 12, 13) -- Focus on key content and status change history types
    GROUP BY
        qb.QuestionId
),
TagPerformance AS (
    -- Aggregates performance metrics per tag using string manipulation for tag extraction.
    SELECT
        UNNEST(string_to_array(SUBSTRING(qb.Tags, 2, LENGTH(qb.Tags) - 2), '><')) AS TagName,
        COUNT(DISTINCT qb.QuestionId) AS QuestionsWithTag,
        AVG(qb.QuestionScore) AS AvgQuestionScoreForTag,
        AVG(qb.QuestionViewCount) AS AvgQuestionViewCountForTag,
        -- NULL logic for tag attributes
        MAX(CASE WHEN t.IsModeratorOnly = true THEN 1 ELSE 0 END) AS IsModeratorOnlyTag,
        MAX(CASE WHEN t.IsRequired = true THEN 1 ELSE 0 END) AS IsRequiredTag
    FROM
        QuestionBase qb
    LEFT JOIN Tags t ON UNNEST(string_to_array(SUBSTRING(qb.Tags, 2, LENGTH(qb.Tags) - 2), '><')) = t.TagName
    WHERE
        qb.Tags IS NOT NULL AND LENGTH(qb.Tags) > 2 -- Ensure valid tags exist
    GROUP BY
        TagName
),
ClassifiedQuestions AS (
    -- Uses a set operator (UNION ALL) to combine two different classifications of questions.
    -- Set 1: High-Engagement SQL-Related Questions meeting specific criteria.
    SELECT
        qb.QuestionId,
        qb.Title,
        qb.QuestionCreationDate,
        qb.QuestionScore,
        qb.QuestionViewCount,
        qb.Tags,
        qb.AcceptanceStatus,
        qb.IsSqlRelated,
        uas.DisplayName AS OwnerDisplayName,
        uas.Reputation AS OwnerReputation,
        uas.UpVoteRatio AS OwnerUpVoteRatio,
        uas.GoldBadgeCount AS OwnerGoldBadges,
        aca.AcceptedAnswerScore,
        aca.AcceptedAnswerBodyLength,
        aca.TotalAnswersForQuestion,
        aca.AnswerRankByScore,
        aca.TotalQuestionCommentScore,
        ph.TotalHistoryEvents,
        ph.DistinctHistoryEditors,
        ph.WasEverClosed,
        ph.WasEverReopened,
        ph.DaysBetweenFirstAndLastEdit,
        tp_primary.QuestionsWithTag AS PrimaryTagQuestionCount,
        tp_primary.AvgQuestionScoreForTag AS PrimaryTagAvgScore,
        tp_primary.IsModeratorOnlyTag AS PrimaryTagIsModeratorOnly,
        -- Complicated calculation for a combined engagement score, uses COALESCE for NULL safety.
        (qb.QuestionScore * 0.6 + qb.QuestionViewCount * 0.05 + COALESCE(qb.QuestionFavoriteCount, 0) * 2 + aca.TotalQuestionCommentScore * 0.4)
        * (1 + COALESCE(uas.UpVoteRatio, 0.5)) AS CombinedEngagementScore, -- Apply UpVoteRatio as a multiplier
        'High Engagement & SQL-Related' AS ClassificationType,
        NULLIF(SUBSTRING(qb.Tags, 2, LENGTH(qb.Tags) - 2), '') AS FormattedTags -- Cleaned string of tags
    FROM
        QuestionBase qb
    LEFT JOIN UserActivitySummary uas ON qb.OwnerUserId = uas.UserId
    LEFT JOIN AnswerAndCommentAnalysis aca ON qb.QuestionId = aca.QuestionId
    LEFT JOIN PostHistoryTimeline ph ON qb.QuestionId = ph.QuestionId
    LEFT JOIN TagPerformance tp_primary ON (string_to_array(SUBSTRING(qb.Tags, 2, LENGTH(qb.Tags) - 2), '><'))[1] = tp_primary.TagName
    WHERE
        qb.IsSqlRelated = TRUE
        AND qb.QuestionScore > 15
        AND qb.AnswerCount > 0
        AND uas.Reputation > 2000
        AND (ph.WasEverClosed = 0 OR ph.WasEverReopened = 1) -- Not closed, or if closed, was reopened
        AND aca.AcceptedAnswerScore IS NOT NULL AND aca.AcceptedAnswerScore > qb.QuestionScore * 0.7 -- Accepted answer is significant
        AND tp_primary.IsModeratorOnlyTag = 0 -- Not a moderator-only tag
        AND ph.DaysBetweenFirstAndLastEdit IS NOT NULL AND ph.DaysBetweenFirstAndLastEdit < 365 -- Edited within a year
    UNION ALL
    -- Set 2: "Emerging Potential" Questions - lower score but high activity, no accepted answer, potentially interesting.
    SELECT
        qb.QuestionId,
        qb.Title,
        qb.QuestionCreationDate,
        qb.QuestionScore,
        qb.QuestionViewCount,
        qb.Tags,
        qb.AcceptanceStatus,
        qb.IsSqlRelated,
        uas.DisplayName AS OwnerDisplayName,
        uas.Reputation AS OwnerReputation,
        uas.UpVoteRatio AS OwnerUpVoteRatio,
        uas.GoldBadgeCount AS OwnerGoldBadges,
        aca.AcceptedAnswerScore,
        aca.AcceptedAnswerBodyLength,
        aca.TotalAnswersForQuestion,
        aca.AnswerRankByScore,
        aca.TotalQuestionCommentScore,
        ph.TotalHistoryEvents,
        ph.DistinctHistoryEditors,
        ph.WasEverClosed,
        ph.WasEverReopened,
        ph.DaysBetweenFirstAndLastEdit,
        tp_primary.QuestionsWithTag AS PrimaryTagQuestionCount,
        tp_primary.AvgQuestionScoreForTag AS PrimaryTagAvgScore,
        tp_primary.IsModeratorOnlyTag AS PrimaryTagIsModeratorOnly,
        (qb.QuestionScore * 0.6 + qb.QuestionViewCount * 0.05 + COALESCE(qb.QuestionFavoriteCount, 0) * 2 + aca.TotalQuestionCommentScore * 0.4)
        * (1 + COALESCE(uas.UpVoteRatio, 0.5)) AS CombinedEngagementScore,
        'Emerging Potential' AS ClassificationType,
        NULLIF(SUBSTRING(qb.Tags, 2, LENGTH(qb.Tags) - 2), '') AS FormattedTags
    FROM
        QuestionBase qb
    LEFT JOIN UserActivitySummary uas ON qb.OwnerUserId = uas.UserId
    LEFT JOIN AnswerAndCommentAnalysis aca ON qb.QuestionId = aca.QuestionId
    LEFT JOIN PostHistoryTimeline ph ON qb.QuestionId = ph.QuestionId
    LEFT JOIN TagPerformance tp_primary ON (string_to_array(SUBSTRING(qb.Tags, 2, LENGTH(qb.Tags) - 2), '><'))[1] = tp_primary.TagName
    WHERE
        qb.IsSqlRelated = TRUE
        AND qb.QuestionScore <= 15 -- Score not too high
        AND qb.AcceptedAnswerId IS NULL -- No accepted answer yet
        AND qb.QuestionViewCount > 3000 -- But very high views
        AND qb.QuestionCommentCount > 7 -- And many comments, indicating discussion
        AND NOT EXISTS (SELECT 1 FROM Posts a WHERE a.ParentId = qb.QuestionId AND a.PostTypeId = 2 AND a.Score > 75) -- No extremely highly-voted answers, suggesting need for better answer
)
-- Main query: Combines all processed data, applies final filtering, and includes a window function for ranking.
SELECT
    cq.QuestionId,
    cq.Title,
    cq.QuestionCreationDate,
    cq.QuestionScore,
    cq.QuestionViewCount,
    cq.FormattedTags,
    cq.AcceptanceStatus,
    cq.IsSqlRelated,
    cq.OwnerDisplayName,
    cq.OwnerReputation,
    cq.OwnerUpVoteRatio,
    cq.GoldBadgeCount AS OwnerGoldBadges,
    cq.AcceptedAnswerScore,
    cq.AcceptedAnswerBodyLength,
    cq.TotalAnswersForQuestion,
    cq.AnswerRankByScore,
    cq.TotalQuestionCommentScore,
    cq.TotalHistoryEvents,
    cq.DistinctHistoryEditors,
    cq.WasEverClosed,
    cq.WasEverReopened,
    cq.DaysBetweenFirstAndLastEdit,
    cq.PrimaryTagQuestionCount,
    cq.PrimaryTagAvgScore,
    cq.PrimaryTagIsModeratorOnly,
    cq.CombinedEngagementScore,
    cq.ClassificationType,
    -- Complex string expression for a detailed summary, incorporating multiple fields and NULL handling.
    COALESCE(cq.ClassificationType, 'Unclassified') || ' Question: "' || COALESCE(cq.Title, 'N/A Question') || '" by ' || COALESCE(cq.OwnerDisplayName, 'Community User') ||
    ' (Score: ' || COALESCE(CAST(cq.QuestionScore AS VARCHAR), '0') || ', Views: ' || COALESCE(CAST(cq.QuestionViewCount AS VARCHAR), '0') || ')'
    || CASE WHEN cq.WasEverClosed = 1 AND cq.WasEverReopened = 0 THEN ' [CLOSED PERMANENTLY]'
            WHEN cq.WasEverClosed = 1 AND cq.WasEverReopened = 1 THEN ' [CLOSED & REOPENED]'
            ELSE '' END
    || CASE WHEN cq.AcceptedAnswerScore IS NOT NULL THEN ' [HAS ACCEPTED ANSWER (Score: ' || COALESCE(CAST(cq.AcceptedAnswerScore AS VARCHAR), 'N/A') || ')]' ELSE '' END AS QuestionDetailedSummary,
    -- Window function: DENSE_RANK for overall ranking based on the calculated engagement score.
    DENSE_RANK() OVER (ORDER BY cq.CombinedEngagementScore DESC, cq.QuestionCreationDate DESC) AS OverallRanking
FROM
    ClassifiedQuestions cq
WHERE
    cq.CombinedEngagementScore > 0 -- Ensure positive engagement score
    AND (cq.OwnerReputation IS NULL OR cq.OwnerReputation > 500) -- Filter out very low-rep owners, or allow null (deleted users)
    AND cq.QuestionCommentCount >= 2 -- Require at least two comments to ensure some discussion
ORDER BY
    OverallRanking ASC, cq.QuestionCreationDate DESC
LIMIT 100;
