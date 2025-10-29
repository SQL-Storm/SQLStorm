-- {"query": "1802.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 301}
WITH UserEngagementPostsComments AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.AboutMe,
        u.WebsiteUrl,
        u.Location,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserUpVotesGiven,
        u.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsPosted,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersPosted,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.Score, 0) ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN COALESCE(p.Score, 0) ELSE 0 END) AS TotalAnswerScore,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) FILTER (WHERE p.Id IS NOT NULL) AS QuestionsWithPostsFlag,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) FILTER (WHERE p.Id IS NOT NULL) AS AnswersWithPostsFlag,
        MAX(p.CreationDate) AS LastPostDate,
        MIN(p.CreationDate) AS FirstPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.AboutMe,
        u.WebsiteUrl,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.UserCreationDate,
    ue.LastAccessDate,
    ue.AboutMe,
    ue.WebsiteUrl,
    ue.Location,
    ue.UserProfileViews,
    ue.UserUpVotesGiven,
    ue.UserDownVotesGiven,
    ue.TotalPosts,
    ue.QuestionsPosted,
    ue.AnswersPosted,
    ue.TotalPostScore,
    ue.TotalQuestionScore,
    ue.TotalAnswerScore,
    ue.CommentsMade,
    ue.TotalCommentScore,
    ue.LastPostDate,
    ue.FirstPostDate,
    CASE
        WHEN ue.TotalPosts > 0 THEN (CAST(ue.TotalPostScore AS DECIMAL) / ue.TotalPosts)
        ELSE 0
    END AS AvgScorePerPost,
    CASE
        WHEN ue.QuestionsPosted > 0 THEN (CAST(ue.TotalQuestionScore AS DECIMAL) / ue.QuestionsPosted)
        ELSE 0
    END AS AvgScorePerQuestion,
    CASE
        WHEN ue.AnswersPosted > 0 THEN (CAST(ue.TotalAnswerScore AS DECIMAL) / ue.AnswersPosted)
        ELSE 0
    END AS AvgScorePerAnswer
FROM UserEngagementPostsComments ue;