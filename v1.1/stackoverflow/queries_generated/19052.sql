-- {"query": "19052.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2252} 

WITH UserVotingStats AS (
    -- Analyze user's overall voting activity and calculate a reliability ratio
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        CAST(u.UpVotes AS NUMERIC) / NULLIF(u.DownVotes, 0) AS UpDownRatio,
        (u.UpVotes + u.DownVotes) AS TotalVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS ActualUpvotesFromUser,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS ActualDownvotesFromUser
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
    HAVING u.Reputation > 5000 AND (u.UpVotes + u.DownVotes) > 500 -- Filter for established and active voters
),
PostEditActivity AS (
    -- Summarize post editing history, including edit counts, distinct editors, and time span of edits
    SELECT
        ph.PostId,
        COUNT(DISTINCT ph.UserId) AS DistinctEditors,
        MAX(ph.CreationDate) AS LastEditDate,
        MIN(ph.CreationDate) AS FirstEditDate,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6, 24) THEN 1 ELSE NULL END) AS MajorEditCount, -- Title, Body, Tags, Suggested Edit Applied
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (7, 8, 9) THEN 1 ELSE NULL END) AS RollbackCount, -- Rollback Title, Body, Tags
        (MAX(ph.CreationDate) - MIN(ph.CreationDate)) AS EditSpan
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL -- Exclude anonymous/community edits from specific user counts
    GROUP BY ph.PostId
    HAVING COUNT(DISTINCT ph.UserId) > 1 OR COUNT(ph.Id) > 3 -- Posts with multiple editors or a significant number of edits
),
PostCommentMetrics AS (
    -- Aggregate comment statistics for each post
    SELECT
        c.PostId,
        COUNT(c.Id) AS TotalCommentCount,
        AVG(c.Score) AS AvgCommentScore,
        SUM(CASE WHEN c.UserId IS NULL THEN 1 ELSE 0 END) AS CommunityComments,
        SUM(c.Score) AS TotalCommentScore
    FROM Comments c
    GROUP BY c.PostId
),
QuestionAnswerEngagement AS (
    -- Link questions to their answers, rank answers, and gather basic question metrics
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.OwnerUserId AS QuestionOwnerId,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        p.Id AS AnswerId,
        p.Score AS AnswerScore,
        p.OwnerUserId AS AnswerOwnerId,
        p.CreationDate AS AnswerCreationDate,
        q.AcceptedAnswerId,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY p.Score DESC, p.CreationDate) AS AnswerRankByScore, -- Rank answers by score for each question
        AVG(p.Score) OVER (PARTITION BY q.Id) AS QuestionAvgAnswerScore, -- Average score of all answers for a question
        (SELECT COUNT(DISTINCT c_sub.UserId) FROM Comments c_sub WHERE c_sub.PostId = q.Id AND c_sub.UserId IS NOT NULL) AS DistinctCommentersForQuestion -- Correlated subquery for distinct commenters
    FROM Posts q
    LEFT JOIN Posts p ON q.Id = p.ParentId AND p.PostTypeId = 2 -- Join to get answers
    WHERE q.PostTypeId = 1 -- Only questions
),
TopQuestionTags AS (
    -- Extract and unnest tags for each question
    SELECT
        PostId,
        TRIM(unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><'))) AS TagName
    FROM Posts
    WHERE PostTypeId = 1 AND Tags IS NOT NULL
)
SELECT
    q.QuestionId,
    q.QuestionTitle,
    u_owner.DisplayName AS QuestionOwnerDisplayName,
    u_owner.Reputation AS QuestionOwnerReputation,
    uvs.UpDownRatio AS QuestionOwnerVotingRatio,
    q.QuestionCreationDate,
    q.QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    q.AcceptedAnswerId,
    COALESCE(pq.TotalCommentCount, 0) AS TotalQuestionComments,
    COALESCE(pq.AvgCommentScore, 0.0) AS AvgQuestionCommentScore,
    COALESCE(pea.MajorEditCount, 0) AS QuestionMajorEditCount,
    COALESCE(pea.RollbackCount, 0) AS QuestionRollbackCount,
    COALESCE(pea.DistinctEditors, 0) AS QuestionDistinctEditors,
    COALESCE(EXTRACT(EPOCH FROM (pea.LastEditDate - pea.FirstEditDate)) / 3600, 0) AS HoursBetweenFirstAndLastEdit, -- Time duration of edits
    q.QuestionAvgAnswerScore,
    q.DistinctCommentersForQuestion,
    tq.TagName,
    RANK() OVER (PARTITION BY tq.TagName ORDER BY q.QuestionScore DESC, q.ViewCount DESC) AS RankWithinTag, -- Rank questions within specific tags
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY q.QuestionId) AS TotalUpvotesForQuestion,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY q.QuestionId) AS TotalDownvotesForQuestion,
    LAG(q.QuestionScore, 1, 0) OVER (PARTITION BY q.QuestionOwnerId ORDER BY q.QuestionCreationDate) AS PreviousQuestionScoreByOwner, -- Score of owner's previous question
    LEAD(q.QuestionScore, 1, 0) OVER (PARTITION BY q.QuestionOwnerId ORDER BY q.QuestionCreationDate) AS NextQuestionScoreByOwner, -- Score of owner's next question
    COALESCE(aa.Score, 0) AS AcceptedAnswerScore,
    COALESCE(ua.DisplayName, 'Community') AS AcceptedAnswerOwnerDisplayName,
    NULLIF(q.ViewCount, 0) / NULLIF(q.AnswerCount, 0) AS ViewToAnswerRatio, -- Handle division by zero
    CASE
        WHEN q.QuestionScore > 100 AND q.ViewCount > 5000 AND q.AnswerCount > 5 THEN 'HighImpact'
        WHEN q.QuestionScore > 50 AND q.ViewCount > 1000 THEN 'MediumImpact'
        ELSE 'LowImpact'
    END AS QuestionImpactCategory,
    b.Name AS OwnerGoldBadgeName,
    b.Class AS OwnerGoldBadgeClass,
    (SELECT COUNT(DISTINCT pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId = q.QuestionId AND pl.LinkTypeId = 3) AS DuplicateCount, -- Number of duplicate questions linked
    COALESCE(NULLIF(LENGTH(q.QuestionTitle), 0), 1) * COALESCE(NULLIF(LENGTH(q.Body), 0), 1) AS TitleBodyLengthProduct, -- Complicated calculation
    CURRENT_TIMESTAMP - q.QuestionCreationDate AS QuestionAge
FROM QuestionAnswerEngagement q
LEFT JOIN Users u_owner ON q.QuestionOwnerId = u_owner.Id
LEFT JOIN UserVotingStats uvs ON q.QuestionOwnerId = uvs.UserId
LEFT JOIN PostEditActivity pea ON q.QuestionId = pea.PostId
LEFT JOIN PostCommentMetrics pq ON q.QuestionId = pq.PostId
LEFT JOIN Posts aa ON q.AcceptedAnswerId = aa.Id -- Details for the Accepted Answer
LEFT JOIN Users ua ON aa.OwnerUserId = ua.Id -- Owner of the Accepted Answer
LEFT JOIN Badges b ON u_owner.Id = b.UserId AND b.Class = 1 -- Only Gold badges for the question owner
LEFT JOIN TopQuestionTags tq ON q.QuestionId = tq.PostId
LEFT JOIN Votes v ON q.QuestionId = v.PostId AND v.VoteTypeId IN (2, 3) -- Upvotes and Downvotes for the question itself
WHERE
    q.QuestionCreationDate >= '2020-01-01' -- Focus on recent data
    AND u_owner.Reputation IS NOT NULL
    AND u_owner.Reputation > 2000 -- Filter for more established users
    AND (
        tq.TagName ILIKE '%performance%'
        OR tq.TagName ILIKE '%optimization%'
        OR tq.TagName ILIKE '%scalability%'
        OR tq.TagName ILIKE '%speed%'
    ) -- Filter for specific performance-related tags (case-insensitive)
    AND q.AnswerRankByScore = 1 -- Consider only the top-scoring answer for each question in this context
    AND COALESCE(pea.MajorEditCount, 0) > 0 -- Only questions that have received at least one major edit
    AND q.QuestionScore >= 10 -- Minimum score for relevance
    AND q.ViewCount >= 500 -- Minimum view count for visibility
    AND q.AcceptedAnswerId IS NOT NULL -- Only questions with an accepted answer
ORDER BY
    QuestionImpactCategory DESC, q.QuestionScore DESC, q.ViewCount DESC, q.QuestionCreationDate DESC
LIMIT 1000;
