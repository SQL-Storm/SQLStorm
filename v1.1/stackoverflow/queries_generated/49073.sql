-- {"query": "49073.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1833} 

WITH HotTopicQuestions AS (
    -- Identify questions related to a set of 'hot' technical tags and their basic properties,
    -- along with initial user reputation and vote counts for the question owner.
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId AS QuestionOwnerId,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViewCount,
        q.AnswerCount AS QuestionAnswerCount,
        q.AcceptedAnswerId,
        q.Title AS QuestionTitle,
        q.Tags,
        u_q.Reputation AS QuestionOwnerReputation,
        u_q.UpVotes AS QuestionOwnerUpVotes,
        u_q.DownVotes AS QuestionOwnerDownVotes
    FROM Posts AS q
    JOIN Users AS u_q ON q.OwnerUserId = u_q.Id
    WHERE
        q.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question')
        AND q.Tags IS NOT NULL
        AND EXISTS (
            -- Efficiently check for the presence of any of the specified 'hot' tags
            SELECT 1
            FROM UNNEST(string_to_array(SUBSTRING(q.Tags FROM 2 FOR LENGTH(q.Tags) - 2), '><')) AS tag_name
            WHERE tag_name IN ('sql', 'python', 'javascript', 'c#', 'java', 'dotnet', 'azure', 'aws', 'docker', 'kubernetes', 'reactjs', 'angular', 'vue.js', 'machine-learning', 'deep-learning', 'data-science', 'devops')
        )
),
UserBadgeSummary AS (
    -- Aggregate badge counts for each unique user ID that owns a 'hot topic' question.
    SELECT
        htq.QuestionOwnerId AS UserId,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM HotTopicQuestions AS htq
    LEFT JOIN Badges AS b ON htq.QuestionOwnerId = b.UserId
    GROUP BY htq.QuestionOwnerId
),
AcceptedAnswerDetails AS (
    -- Retrieve details for accepted answers to the hot topic questions,
    -- including the answer's score and the answerer's reputation and upvotes.
    SELECT
        htq.QuestionId,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwnerId,
        a.Score AS AnswerScore,
        u_a.Reputation AS AnswerOwnerReputation,
        u_a.UpVotes AS AnswerOwnerUpVotes
    FROM HotTopicQuestions AS htq
    JOIN Posts AS a ON htq.AcceptedAnswerId = a.Id
    JOIN Users AS u_a ON a.OwnerUserId = u_a.Id
    WHERE a.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer')
),
PostLifecycleActivity AS (
    -- Summarize historical activity for each hot topic question,
    -- including edit counts, close/reopen status, and comment counts.
    SELECT
        htq.QuestionId,
        COUNT(ph_edit.Id) FILTER (WHERE ph_edit.PostHistoryTypeId IN (
            -- Select specific PostHistoryTypes related to edits
            SELECT Id FROM PostHistoryTypes WHERE Name IN ('Edit Body', 'Edit Title', 'Edit Tags', 'Suggested Edit Applied')
        )) AS EditCount,
        MAX(CASE WHEN ph_close.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Closed') THEN 1 ELSE 0 END) AS WasClosed,
        MAX(CASE WHEN ph_reopen.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Reopened') THEN 1 ELSE 0 END) AS WasReopened,
        COUNT(c.Id) AS CommentCountOnQuestion
    FROM HotTopicQuestions AS htq
    LEFT JOIN PostHistory AS ph_edit ON htq.QuestionId = ph_edit.PostId
    LEFT JOIN PostHistory AS ph_close ON htq.QuestionId = ph_close.PostId AND ph_close.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Closed')
    LEFT JOIN PostHistory AS ph_reopen ON htq.QuestionId = ph_reopen.PostId AND ph_reopen.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Reopened')
    LEFT JOIN Comments AS c ON htq.QuestionId = c.PostId
    GROUP BY htq.QuestionId
)
-- Final query to calculate a comprehensive 'Composite Influence Score' for each question owner.
-- The score considers various factors: user reputation, badge achievements, question performance,
-- accepted answer quality, and post activity/engagement.
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation AS UserReputation,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    SUM(htq.QuestionScore) AS TotalQuestionScore,
    SUM(htq.QuestionViewCount) AS TotalQuestionViewCount,
    SUM(COALESCE(aad.AnswerScore, 0)) AS TotalAcceptedAnswerScore,
    COUNT(DISTINCT htq.QuestionId) AS QuestionsAskedCount,
    -- Calculation of the Composite Influence Score
    (
        u.Reputation * 0.05 -- Base reputation contribution (scaled)
        + COALESCE(ubs.GoldBadges * 100, 0) -- Gold badges provide a significant boost
        + COALESCE(ubs.SilverBadges * 50, 0) -- Silver badges provide a moderate boost
        + COALESCE(ubs.BronzeBadges * 10, 0) -- Bronze badges provide a minor boost
        + SUM(htq.QuestionScore * 0.6) -- Raw question score is a direct indicator of quality
        + SUM(htq.QuestionViewCount * 0.005) -- Question views indicate reach
        + SUM(pha.EditCount * 5) -- More edits suggest dedication/maintenance
        + SUM(CASE WHEN pha.WasClosed = 1 AND pha.WasReopened = 1 THEN 200 ELSE 0 END) -- Bonus for questions that were highly active/controversial (closed and then reopened)
        + SUM(COALESCE(aad.AnswerScore * 0.7, 0)) -- Score of accepted answers reflects the value provided to the questioner
        + SUM(COALESCE(aad.AnswerOwnerReputation * 0.02, 0)) -- The reputation of the accepted answerer adds to the question's overall value
        + SUM(pha.CommentCountOnQuestion * 0.3) -- Comments indicate engagement and discussion around the question
        + (u.UpVotes - u.DownVotes) * 0.02 -- Net upvotes given by the user, indicating helpfulness to community
    ) AS CompositeInfluenceScore
FROM Users AS u
JOIN HotTopicQuestions AS htq ON u.Id = htq.QuestionOwnerId
LEFT JOIN UserBadgeSummary AS ubs ON u.Id = ubs.UserId
LEFT JOIN AcceptedAnswerDetails AS aad ON htq.QuestionId = aad.QuestionId
LEFT JOIN PostLifecycleActivity AS pha ON htq.QuestionId = pha.QuestionId
GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges
ORDER BY
    CompositeInfluenceScore DESC,
    UserReputation DESC,
    QuestionsAskedCount DESC
LIMIT 50;
