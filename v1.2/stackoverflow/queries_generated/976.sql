-- {"query": "976.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1780} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        0 AS Level,
        ARRAY[t.TagName] AS Ancestry
    FROM Tags t
    WHERE t.Count > 1000
  UNION ALL
    SELECT 
        c.Id,
        c.TagName,
        c.Count,
        c.ExcerptPostId,
        c.WikiPostId,
        rh.Level + 1,
        rh.Ancestry || c.TagName
    FROM Tags c
    JOIN Posts p ON p.Tags LIKE '%' || '<' || c.TagName || '>' || '%'
    JOIN RecursiveTagHierarchy rh ON p.OwnerUserId = rh.Id
    WHERE c.Count > 500 AND rh.Level < 2
),
UserBadgesRanked AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        b.Name AS BadgeName,
        b.Class,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY b.Class, b.Date DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
),
UserPostStats AS (
    SELECT 
        p.OwnerUserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
        SUM(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestionViews,
        MAX(p.LastActivityDate) AS LastActivityDate,
        BOOL_OR(p.ClosedDate IS NOT NULL) AS HasClosedPosts
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserCommentsAgg AS (
    SELECT 
        c.UserId,
        COUNT(*) AS TotalComments,
        AVG(LENGTH(c.Text)) AS AvgCommentLength,
        COUNT(DISTINCT c.PostId) AS DistinctCommentedPosts
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserVoteSummary AS (
    SELECT 
        v.UserId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS UpVotesGiven,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownVotesGiven,
        COUNT(DISTINCT v.PostId) AS UniquePostsVoted
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
AggregatedUserData AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        COALESCE(ups.QuestionCount,0) AS Questions,
        COALESCE(ups.AnswerCount,0) AS Answers,
        COALESCE(ups.AvgQuestionScore,0) AS AvgQuestionScore,
        COALESCE(ups.AvgAnswerScore,0) AS AvgAnswerScore,
        COALESCE(ups.TotalQuestionViews,0) AS TotalQuestionViews,
        COALESCE(uc.TotalComments,0) AS TotalComments,
        COALESCE(uc.AvgCommentLength,0) AS AvgCommentLength,
        COALESCE(uv.UpVotesGiven,0) AS UpVotesGiven,
        COALESCE(uv.DownVotesGiven,0) AS DownVotesGiven,
        CASE WHEN ups.HasClosedPosts THEN 'Yes' ELSE 'No' END AS HasClosedPosts,
        COALESCE(ub.BadgeName, 'No Badges') AS TopBadge,
        COALESCE(ub.Class, 4) AS TopBadgeClass,
        ups.LastActivityDate
    FROM Users u
    LEFT JOIN UserPostStats ups ON u.Id = ups.OwnerUserId
    LEFT JOIN UserCommentsAgg uc ON u.Id = uc.UserId
    LEFT JOIN UserVoteSummary uv ON u.Id = uv.UserId
    LEFT JOIN UserBadgesRanked ub ON u.Id = ub.UserId AND ub.BadgeRank = 1
    WHERE u.Reputation > 500
),
TopQuestionsWithAnswerStats AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.Tags,
        q.AnswerCount,
        a.Id AS AcceptedAnswerId,
        a.Score AS AcceptedAnswerScore,
        a.CreationDate AS AcceptedAnswerDate,
        u.DisplayName AS QuestionOwnerName,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.Score DESC, q.ViewCount DESC) AS QuestionOrder
    FROM Posts q
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id
    LEFT JOIN Users u ON q.OwnerUserId = u.Id
    WHERE q.PostTypeId = 1 AND q.Score > 5
),
ClosedQuestionsDetails AS (
    SELECT
        ph.PostId,
        ph.CreationDate AS CloseDate,
        crt.Name AS CloseReason,
        p.Title,
        p.OwnerUserId,
        u.DisplayName AS OwnerName
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON ph.Comment::int = crt.Id
    JOIN Posts p ON ph.PostId = p.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
),
UserQuestionTextSearch AS (
    SELECT
        p.OwnerUserId,
        COUNT(*) AS QuestionsWithHowMany,
        SUM(CASE WHEN p.Title ILIKE '%how many%' THEN 1 ELSE 0 END) AS HowManyQuestions,
        SUM(CASE WHEN p.Body ILIKE '%performance%' THEN 1 ELSE 0 END) AS PerformanceMentions
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
)
SELECT  
    aud.UserId,
    aud.DisplayName,
    aud.Reputation,
    aud.Location,
    aud.Views,
    aud.Questions,
    aud.Answers,
    aud.AvgQuestionScore,
    aud.AvgAnswerScore,
    aud.TotalQuestionViews,
    aud.TotalComments,
    aud.AvgCommentLength,
    aud.UpVotesGiven,
    aud.DownVotesGiven,
    aud.HasClosedPosts,
    aud.TopBadge,
    aud.TopBadgeClass,
    aud.LastActivityDate,
    tq.QuestionId,
    tq.Title AS TopQuestionTitle,
    tq.Score AS TopQuestionScore,
    tq.ViewCount AS TopQuestionViews,
    tq.Tags AS TopQuestionTags,
    tq.AnswerCount AS TopQuestionAnswerCount,
    tq.AcceptedAnswerId,
    tq.AcceptedAnswerScore,
    tq.AcceptedAnswerDate,
    cq.CloseDate AS LastCloseDate,
    cq.CloseReason,
    cq.Title AS ClosedQuestionTitle,
    cq.OwnerName AS ClosedQuestionOwner,
    uqt.HowManyQuestions,
    uqt.PerformanceMentions
FROM AggregatedUserData aud
LEFT JOIN TopQuestionsWithAnswerStats tq ON aud.UserId = tq.OwnerUserId AND tq.QuestionOrder = 1
LEFT JOIN LATERAL (
    SELECT MAX(ph.CreationDate) AS CloseDate, crt.Name AS CloseReason, p.Title, u.DisplayName AS OwnerName
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON ph.Comment::int = crt.Id
    JOIN Posts p ON ph.PostId = p.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE ph.PostHistoryTypeId = 10 AND p.OwnerUserId = aud.UserId
    GROUP BY crt.Name, p.Title, u.DisplayName
    ORDER BY CloseDate DESC
    LIMIT 1
) cq ON TRUE
LEFT JOIN UserQuestionTextSearch uqt ON aud.UserId = uqt.OwnerUserId
WHERE aud.TopBadgeClass <= 2 -- Gold or Silver badge holders only
AND (
    aud.Questions > 10 
    OR aud.Answers > 20
    OR aud.TotalComments > 50
)
ORDER BY aud.Reputation DESC, tq.Score DESC NULLS LAST
LIMIT 100;
