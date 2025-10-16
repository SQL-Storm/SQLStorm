-- {"query": "3010.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1437} 
WITH UserReputationStats AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        -- Sum of votes received on posts owned by user
        COALESCE(SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END), 0) AS TotalVotesReceived,
        -- Count of badges by class
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        -- Number of posts with content containing the word 'performance'
        SUM(CASE WHEN LOWER(p.Body) LIKE '%performance%' THEN 1 ELSE 0 END) AS PostsWithPerformanceKeyword,
        -- Nullify Reputation if user has no badges
        CASE WHEN COUNT(b.Id) = 0 THEN NULL ELSE u.Reputation END AS RepuUnlessNoBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RecentPostChanges AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        -- Capture the old title if type indicates title change
        CASE WHEN ph.PostHistoryTypeId IN (4,7) THEN ph.Comment ELSE NULL END AS OldTitle,
        -- Capture the old body if type indicates body change
        CASE WHEN ph.PostHistoryTypeId IN (5,8) THEN ph.Text ELSE NULL END AS OldBody,
        -- Count number of historical changes per post
        COUNT(*) OVER (PARTITION BY ph.PostId) AS ChangeCount
    FROM PostHistory ph
),
PostAnswerStats AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        -- Total scores of answers linked to each question
        (SELECT SUM(a.Score) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS SumAnswerScores,
        -- Count of comments on question and answers
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS QuestionCommentCount,
        (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS NumberOfAnswers,
        -- Average score of answers
        (SELECT AVG(a.Score) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS AvgAnswerScore,
        -- Max score among answers
        (SELECT MAX(a.Score) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS MaxAnswerScore
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Questions only
),
TagPopularity AS (
    SELECT 
        t.TagName,
        t.ExcerptPostId,
        t.WikiPostId,
        -- Number of questions tagged with this tag
        t.Count AS TagQuestionCount,
        -- Sum of ViewCount across questions with this tag
        SUM(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS TotalViewsForTag,
        -- Count of answers associated with questions of this tag
        (SELECT COUNT(*) FROM Posts a WHERE a.ParentId IN (
            SELECT Id FROM Posts WHERE Tags LIKE '%' || t.TagName || '%') AND a.PostTypeId = 2) AS AnswersWithTag
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE t.IsModeratorOnly = FALSE
),
AggregateResults AS (
    SELECT 
        u.UserId,
        u.DisplayName,
        u.TotalVotesReceived,
        u.GoldBadges,
        u.SilverBadges,
        u.BronzeBadges,
        u.PostsWithPerformanceKeyword,
        u.RepuUnlessNoBadges,
        p.PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.SumAnswerScores,
        p.QuestionCommentCount,
        p.NumberOfAnswers,
        p.AvgAnswerScore,
        p.MaxAnswerScore,
        th.OldTitle,
        th.OldBody,
        th.ChangeCount,
        tp.Tags,
        tp.TagName,
        tp.TagQuestionCount,
        tp.TotalViewsForTag,
        tp.AnswersWithTag
    FROM UserReputationStats u
    LEFT JOIN Posts p ON p.OwnerUserId = u.UserId
    LEFT JOIN RecentPostChanges th ON th.PostId = p.Id
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id AND pl.LinkTypeId = 3 -- Duplicate links
    LEFT JOIN TagPopularity tp ON p.Tags LIKE '%' || tp.TagName || '%'
)
SELECT 
    ar.UserId,
    ar.DisplayName,
    ar.TotalVotesReceived,
    ar.GoldBadges,
    ar.SilverBadges,
    ar.BronzeBadges,
    -- Concatenate titles of recent posts with title changes
    STRING_AGG(DISTINCT ar.Title, '; ') FILTER (WHERE ar.ChangeCount > 0) AS RecentChangedQuestions,
    -- Calculate ratio of answers to questions with at least one answer
    CASE WHEN COUNT(DISTINCT ar.PostId) FILTER (WHERE ar.NumberOfAnswers > 0) = 0 THEN NULL
         ELSE COUNT(DISTINCT ar.PostId) FILTER (WHERE ar.PostTypeId = 2) * 1.0 / COUNT(DISTINCT ar.PostId) FILTER (WHERE ar.PostTypeId = 1) END AS AnswerQuestionRatio,
    -- String of tags ordered alphabetically
    STRING_AGG(DISTINCT ar.TagName, ', ' ORDER BY ar.TagName) AS PopularTags,
    -- Sum of views for questions tagged with the top five tags
    SUM(CASE WHEN ar.TagName IN (
        SELECT TagName FROM TagPopularity ORDER BY TagQuestionCount DESC LIMIT 5
    ) THEN ar.ViewCount ELSE 0 END) AS TopTagsTotalViews,
    -- Joint use of window function: cumulative answer scores per user
    SUM(ar.SumAnswerScores) OVER (PARTITION BY ar.UserId ORDER BY ar.UserId ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeAnswerScore
FROM AggregateResults ar
WHERE ar.UserId IS NOT NULL
GROUP BY ar.UserId, ar.DisplayName, ar.TotalVotesReceived, ar.GoldBadges, ar.SilverBadges, ar.BronzeBadges, ar.RepuUnlessNoBadges;