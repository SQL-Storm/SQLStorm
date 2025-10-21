-- {"query": "19019.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2862} 

WITH UserActivitySummary AS (
    -- Aggregates user-specific metrics including posts, comments, and badge counts
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.UpVotes AS TotalUpVotesReceived,
        u.DownVotes AS TotalDownVotesReceived,
        COUNT(DISTINCT p.Id) AS TotalPostsCreated,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgesCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgesCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes
),
QuestionPerformance AS (
    -- Analyzes question performance, including accepted answer score, actual answer count, and view rank
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId AS QuestionOwnerId,
        q.Title AS QuestionTitle,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.Tags,
        q.LastActivityDate,
        q.ClosedDate,
        a.Score AS AcceptedAnswerScore,
        COUNT(DISTINCT ans.Id) FILTER (WHERE ans.PostTypeId = 2) OVER (PARTITION BY q.Id) AS ActualAnswerCount,
        AVG(ans.Score) FILTER (WHERE ans.PostTypeId = 2) OVER (PARTITION BY q.Id) AS AverageAnswerScore,
        -- Calculate the proportion of positive votes for answers to this question
        NULLIF(SUM(CASE WHEN v_ans.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY q.Id), 0) /
        NULLIF(COUNT(v_ans.Id) OVER (PARTITION BY q.Id), 0)::numeric AS AnswerUpvoteRatio,
        RANK() OVER (PARTITION BY EXTRACT(YEAR FROM q.CreationDate) ORDER BY q.ViewCount DESC, q.Score DESC) AS ViewScoreRankByYear,
        EXTRACT(EPOCH FROM (NOW() - q.LastActivityDate)) / 3600 AS HoursSinceLastActivity, -- Hours since last activity
        LAG(q.CreationDate, 1) OVER (ORDER BY q.CreationDate) AS PreviousQuestionCreationDate
    FROM Posts q
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id AND a.PostTypeId = 2
    LEFT JOIN Posts ans ON q.Id = ans.ParentId AND ans.PostTypeId = 2
    LEFT JOIN Votes v_ans ON ans.Id = v_ans.PostId
    WHERE q.PostTypeId = 1 -- Only consider questions
),
PostEditHistoryDetails AS (
    -- Summarizes post history, focusing on distinct editors and types of edits
    SELECT
        ph.PostId,
        COUNT(DISTINCT ph.UserId) AS UniqueEditors,
        SUM(CASE WHEN pht.Name LIKE '%Body%' THEN 1 ELSE 0 END) AS BodyEditEvents,
        SUM(CASE WHEN pht.Name LIKE '%Tags%' THEN 1 ELSE 0 END) AS TagEditEvents,
        SUM(CASE WHEN pht.Name LIKE '%Closed%' OR pht.Name LIKE '%Reopened%' THEN 1 ELSE 0 END) AS ClosureReopenEvents,
        MAX(ph.CreationDate) AS LastEditDate,
        MIN(ph.CreationDate) AS FirstHistoryEventDate,
        -- Check if the question was ever migrated away (PostHistoryTypeId = 35)
        MAX(CASE WHEN ph.PostHistoryTypeId = 35 THEN 1 ELSE 0 END)::boolean AS WasMigratedAway,
        COALESCE(
            EXTRACT(DAY FROM (MAX(ph.CreationDate) - MIN(ph.CreationDate))),
            0
        ) AS DaysBetweenFirstAndLastHistory
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    GROUP BY ph.PostId
),
DuplicateLinkInfo AS (
    -- Gathers information about duplicate links for questions, including a correlated subquery
    SELECT
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) AS NumberOfDuplicateLinks,
        -- Correlated subquery: check if any related (duplicate) post has a score above a threshold AND has specific tags
        EXISTS (
            SELECT 1
            FROM Posts dup_p
            LEFT JOIN LATERAL (SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(dup_p.Tags, 2, LENGTH(dup_p.Tags) - 2), '><')) AS TagName) AS t ON TRUE
            WHERE dup_p.Id = pl.RelatedPostId
              AND dup_p.Score > 50
              AND t.TagName IN ('sql', 'database', 'performance-tuning')
        ) AS HasHighScoringRelevantDuplicate,
        STRING_AGG(DISTINCT t.TagName, ', ') FILTER (WHERE t.TagName IS NOT NULL) AS DuplicateTagsSummary
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    LEFT JOIN Posts p_rel ON pl.RelatedPostId = p_rel.Id
    LEFT JOIN LATERAL (SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(p_rel.Tags, 2, LENGTH(p_rel.Tags) - 2), '><')) AS TagName) AS t ON p_rel.Tags IS NOT NULL
    WHERE lt.Name = 'Duplicate'
    GROUP BY pl.PostId
)
-- Main Query: Combine all CTEs to find influential questions and their authors
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.UserCreationDate,
    uas.TotalPostsCreated,
    uas.TotalCommentsMade,
    uas.GoldBadgesCount,
    uas.SilverBadgesCount,
    uas.BronzeBadgesCount,
    qp.QuestionId,
    qp.QuestionTitle,
    qp.QuestionCreationDate,
    qp.QuestionScore,
    COALESCE(qp.ViewCount, 0) AS QuestionViewCount, -- Handle NULL ViewCount
    qp.ActualAnswerCount,
    COALESCE(qp.AverageAnswerScore, 0.0) AS AverageAnswerScoreOfAnswers,
    COALESCE(qp.AcceptedAnswerScore, 0) AS AcceptedAnswerScore,
    COALESCE(qp.AnswerUpvoteRatio, 0.0) AS AnswersUpvoteRatio,
    peh.UniqueEditors,
    peh.BodyEditEvents,
    peh.TagEditEvents,
    peh.ClosureReopenEvents,
    peh.LastEditDate AS LastHistoryEditDate,
    peh.DaysBetweenFirstAndLastHistory,
    peh.WasMigratedAway,
    COALESCE(dli.NumberOfDuplicateLinks, 0) AS NumberOfDuplicateLinks,
    dli.HasHighScoringRelevantDuplicate,
    dli.DuplicateTagsSummary,
    qp.ViewScoreRankByYear,
    qp.HoursSinceLastActivity,
    -- Calculate days between the current question and the previous one by the same owner
    EXTRACT(DAY FROM (qp.QuestionCreationDate - qp.PreviousQuestionCreationDate)) AS DaysSincePreviousQuestion,
    -- Custom category based on user and question metrics
    CASE
        WHEN uas.Reputation > 20000 AND uas.GoldBadgesCount >= 5 AND qp.QuestionScore > 100 THEN 'Legendary Questioner'
        WHEN uas.Reputation > 10000 AND qp.ActualAnswerCount > 10 AND qp.AverageAnswerScore > 5 THEN 'Expert Authority'
        WHEN peh.UniqueEditors > 5 AND peh.ClosureReopenEvents > 0 THEN 'Highly Debated Question'
        WHEN qp.QuestionTitle ILIKE '%performance%' AND qp.QuestionScore > 20 THEN 'Performance Hotspot'
        ELSE 'General Interest'
    END AS QuestionCategory,
    -- Complicated string expression for tags: extract top 3 tags if available, otherwise 'No Specific Tags'
    COALESCE(
        SUBSTRING(
            STRING_AGG(t.TagName, ', ') FILTER (WHERE t.TagName IS NOT NULL ORDER BY t.TagName)
        FROM 1 FOR 
            CASE WHEN LENGTH(STRING_AGG(t.TagName, ', ') FILTER (WHERE t.TagName IS NOT NULL ORDER BY t.TagName)) > 100 THEN 100 
                 ELSE LENGTH(STRING_AGG(t.TagName, ', ') FILTER (WHERE t.TagName IS NOT NULL ORDER BY t.TagName)) END
        ),
    'No Specific Tags') AS TopQuestionTagsSnippet,
    (uas.TotalUpVotesReceived - uas.TotalDownVotesReceived) AS NetVotesReceived,
    NULLIF(uas.TotalUpVotesReceived, 0) / NULLIF(uas.TotalDownVotesReceived::numeric, 0) AS UpvoteDownvoteRatioReceived
FROM UserActivitySummary uas
JOIN QuestionPerformance qp ON uas.UserId = qp.QuestionOwnerId
LEFT JOIN PostEditHistoryDetails peh ON qp.QuestionId = peh.PostId
LEFT JOIN DuplicateLinkInfo dli ON qp.QuestionId = dli.PostId
LEFT JOIN LATERAL (SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(qp.Tags, 2, LENGTH(qp.Tags) - 2), '><')) AS TagName) AS t ON qp.Tags IS NOT NULL
WHERE
    uas.Reputation > 2500 -- Filter for users with significant reputation
    AND qp.QuestionScore > 5 -- Filter for questions with some positive score
    AND qp.ViewCount > 100 -- Filter for questions with reasonable visibility
    AND qp.ActualAnswerCount >= 1 -- Ensure questions have at least one answer
    AND (qp.QuestionTitle ILIKE '%sql%' OR qp.Tags LIKE '%<database>%' OR qp.Tags LIKE '%<query>%') -- Focus on database/SQL related questions
    AND qp.HoursSinceLastActivity < 720 -- Active in the last month
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory ph_close
        WHERE ph_close.PostId = qp.QuestionId
          AND ph_close.PostHistoryTypeId IN (10, 12) -- Post Closed or Post Deleted
          AND ph_close.CreationDate > (NOW() - INTERVAL '6 months') -- Recently closed/deleted
    ) -- Exclude recently closed/deleted questions
GROUP BY
    uas.UserId, uas.DisplayName, uas.Reputation, uas.UserCreationDate, uas.TotalPostsCreated,
    uas.TotalCommentsMade, uas.GoldBadgesCount, uas.SilverBadgesCount, uas.BronzeBadgesCount,
    uas.TotalUpVotesReceived, uas.TotalDownVotesReceived,
    qp.QuestionId, qp.QuestionTitle, qp.QuestionCreationDate, qp.QuestionScore, qp.ViewCount,
    qp.ActualAnswerCount, qp.AverageAnswerScore, qp.AcceptedAnswerScore, qp.AnswerUpvoteRatio,
    peh.UniqueEditors, peh.BodyEditEvents, peh.TagEditEvents, peh.ClosureReopenEvents,
    peh.LastEditDate, peh.DaysBetweenFirstAndLastHistory, peh.WasMigratedAway,
    dli.NumberOfDuplicateLinks, dli.HasHighScoringRelevantDuplicate, dli.DuplicateTagsSummary,
    qp.ViewScoreRankByYear, qp.HoursSinceLastActivity, qp.PreviousQuestionCreationDate
ORDER BY
    (uas.Reputation * 0.4) + (qp.QuestionScore * 0.3) + (COALESCE(qp.AverageAnswerScore, 0) * 0.2) + (uas.GoldBadgesCount * 10) DESC,
    qp.LastActivityDate DESC
LIMIT 500;
