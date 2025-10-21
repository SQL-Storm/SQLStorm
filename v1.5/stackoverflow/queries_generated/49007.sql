-- {"query": "49007.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1893} 

WITH PopularRecentTags AS (
    -- Identify the top 50 most frequently used tags in questions posted in the last 2 years,
    -- ensuring only tags with at least 100 questions are considered.
    SELECT
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
        COUNT(DISTINCT p.Id) AS QuestionCount
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Only questions
      AND p.CreationDate >= (NOW() - INTERVAL '2 year')
      AND p.Tags IS NOT NULL AND length(p.Tags) > 2 -- Ensure tags string is not empty or just "<>"
    GROUP BY unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
    HAVING COUNT(DISTINCT p.Id) > 100
    ORDER BY QuestionCount DESC
    LIMIT 50
),
TopQuestionsInPopularTags AS (
    -- Select high-scoring and high-viewed questions that belong to the identified popular tags.
    -- Rank these questions by score and view count within each popular tag.
    SELECT
        q.PostId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.CreationDate,
        q.OwnerUserId,
        q.TagName, -- Keep individual tag for partitioning
        DENSE_RANK() OVER (PARTITION BY q.TagName ORDER BY q.Score DESC, q.ViewCount DESC, q.PostId DESC) as TagQuestionRank
    FROM (
        SELECT
            p.Id AS PostId,
            p.Title,
            p.Score,
            p.ViewCount,
            p.AnswerCount,
            p.CreationDate,
            p.OwnerUserId,
            unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.Score > 10 -- Consider only questions with a decent score
          AND p.ViewCount > 500 -- Consider only well-viewed questions
          AND p.CreationDate >= (NOW() - INTERVAL '3 year') -- Broader date range for questions
          AND p.Tags IS NOT NULL AND length(p.Tags) > 2
          AND p.OwnerUserId IS NOT NULL
    ) AS q
    INNER JOIN PopularRecentTags prt ON q.TagName = prt.TagName
),
FilteredTopQuestions AS (
    -- Consolidate questions, keeping only the top 10 questions for each popular tag.
    -- Aggregate all related popular tags for each question.
    SELECT
        PostId,
        Title,
        Score,
        ViewCount,
        AnswerCount,
        CreationDate,
        OwnerUserId,
        STRING_AGG(DISTINCT TagName, ',' ORDER BY TagName) AS AllRelatedTags
    FROM TopQuestionsInPopularTags
    WHERE TagQuestionRank <= 10 -- Top 10 questions per popular tag
    GROUP BY PostId, Title, Score, ViewCount, AnswerCount, CreationDate, OwnerUserId
),
UserQualityMetrics AS (
    -- For the owners of these top questions, gather comprehensive user statistics:
    -- reputation, vote counts, profile views, badge counts, average answer score, and total comments made.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        u.Views AS UserViews,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(DISTINCT p_ans.Id) AS TotalAnswers,
        COALESCE(AVG(p_ans.Score), 0) AS AvgAnswerScore,
        COUNT(DISTINCT c_made.Id) AS TotalCommentsMadeByOwner
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p_ans ON u.Id = p_ans.OwnerUserId AND p_ans.PostTypeId = 2 -- Owner's answers
    LEFT JOIN Comments c_made ON u.Id = c_made.UserId -- Comments made by the owner
    WHERE u.Id IN (SELECT DISTINCT OwnerUserId FROM FilteredTopQuestions WHERE OwnerUserId IS NOT NULL)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes, u.Views
),
PostEngagementHistory AS (
    -- For each of the filtered top questions, summarize engagement and history:
    -- total comments, unique editors (excluding owner), and counts of specific history events like edits or closures.
    SELECT
        ftq.PostId,
        COUNT(DISTINCT c_on_post.Id) AS QuestionCommentCount,
        COUNT(DISTINCT ph.Id) AS TotalHistoryEvents,
        COUNT(DISTINCT ph.UserId) FILTER (WHERE ph.UserId IS NOT NULL AND ph.UserId != ftq.OwnerUserId) AS UniqueEditorsExcludingOwner,
        MAX(ph.CreationDate) AS LastHistoryActivityDate,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9, 24) THEN ph.Id END) AS EditRelatedHistoryCount, -- Title/Body/Tags edits & rollbacks, suggested edits applied
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS CloseHistoryCount, -- Post closed
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.Id END) AS DeleteHistoryCount -- Post deleted
    FROM FilteredTopQuestions ftq
    LEFT JOIN Comments c_on_post ON ftq.PostId = c_on_post.PostId -- Comments on the question
    LEFT JOIN PostHistory ph ON ftq.PostId = ph.PostId
    GROUP BY ftq.PostId, ftq.OwnerUserId
)
-- Final selection: Combine all gathered metrics to provide a comprehensive view
-- of high-impact questions and their influential contributors within trending topics.
SELECT
    ftq.PostId,
    ftq.Title,
    ftq.Score AS QuestionScore,
    ftq.ViewCount AS QuestionViewCount,
    ftq.AnswerCount AS QuestionAnswerCount,
    ftq.CreationDate AS QuestionCreationDate,
    ftq.AllRelatedTags,
    uqm.DisplayName AS QuestionOwnerDisplayName,
    uqm.Reputation AS QuestionOwnerReputation,
    uqm.UserUpVotes AS OwnerTotalUpVotesReceived,
    uqm.UserDownVotes AS OwnerTotalDownVotesReceived,
    uqm.UserViews AS OwnerProfileViews,
    uqm.GoldBadges,
    uqm.SilverBadges,
    uqm.BronzeBadges,
    uqm.TotalAnswers AS OwnerTotalAnswersPosted,
    uqm.AvgAnswerScore AS OwnerAverageAnswerScore,
    uqm.TotalCommentsMadeByOwner,
    peh.QuestionCommentCount,
    peh.TotalHistoryEvents AS QuestionTotalHistoryEvents,
    peh.UniqueEditorsExcludingOwner AS QuestionUniqueEditorsExcludingOwner,
    peh.EditRelatedHistoryCount AS QuestionEditRelatedHistoryCount,
    peh.CloseHistoryCount AS QuestionCloseHistoryCount,
    peh.DeleteHistoryCount AS QuestionDeleteHistoryCount,
    peh.LastHistoryActivityDate AS QuestionLastHistoryActivityDate
FROM FilteredTopQuestions ftq
INNER JOIN UserQualityMetrics uqm ON ftq.OwnerUserId = uqm.UserId
LEFT JOIN PostEngagementHistory peh ON ftq.PostId = peh.PostId
ORDER BY
    uqm.Reputation DESC,      -- Prioritize questions by highly reputed owners
    ftq.Score DESC,           -- Then by question score
    ftq.ViewCount DESC,       -- Then by question view count
    ftq.CreationDate DESC     -- Finally by recency
LIMIT 100;
