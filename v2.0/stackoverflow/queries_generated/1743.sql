-- {"query": "1743.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3620} 
WITH UserCoreActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalPostViews,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalPostFavorites,
        SUM(p.Score) AS TotalPostScoreReceived
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.CreationDate, u.LastAccessDate
),
UserVoteActivity AS (
    SELECT
        v.UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS TotalBountyGiven
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
PostMetrics AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId AS UserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.AcceptedAnswerId,
        p.ParentId,
        p.Body,
        p.Title,
        p.Tags,
        LENGTH(p.Body) AS BodyLength,
        LENGTH(p.Title) AS TitleLength,
        (SELECT COUNT(DISTINCT pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1) AS LinkedPostCount,
        (SELECT COUNT(DISTINCT pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicatePostCount,
        (SELECT COUNT(ph.Id) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)) AS EditCount,
        (SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountOnPost,
        CASE
            WHEN p.Body ILIKE '%<pre><code>%' OR p.Body ILIKE '%<code class=%>' THEN 1
            ELSE 0
        END AS HasCodeSnippet,
        CASE
            WHEN p.Tags IS NOT NULL AND LENGTH(TRIM(p.Tags)) > 2 THEN ARRAY_LENGTH(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 1)
            ELSE 0
        END AS TagCountForPost
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
),
QuestionAnswerContext AS (
    SELECT
        pm.PostId,
        pm.UserId,
        pm.PostTypeId,
        pm.CreationDate,
        pm.Score,
        pm.ViewCount,
        pm.AnswerCount,
        pm.FavoriteCount,
        pm.AcceptedAnswerId,
        pm.ParentId,
        pm.BodyLength,
        pm.TitleLength,
        pm.LinkedPostCount,
        pm.DuplicatePostCount,
        pm.EditCount,
        pm.CommentCountOnPost,
        pm.HasCodeSnippet,
        pm.TagCountForPost,
        CASE
            WHEN pm.PostTypeId = 1 AND pm.AnswerCount > 0 AND pm.AcceptedAnswerId IS NOT NULL THEN 1.0 / pm.AnswerCount
            WHEN pm.PostTypeId = 1 AND pm.AnswerCount > 0 AND pm.AcceptedAnswerId IS NULL THEN 0.0
            ELSE NULL
        END AS AcceptedAnswerRatio,
        (SELECT AVG(ans.Score) FROM Posts ans WHERE ans.ParentId = pm.PostId AND ans.PostTypeId = 2) AS AvgAnswerScore,
        (SELECT q.Score FROM Posts q WHERE q.Id = pm.ParentId AND pm.PostTypeId = 2) AS ParentQuestionScore,
        (SELECT EXTRACT(EPOCH FROM (pm.CreationDate - q.CreationDate)) / 3600.0 FROM Posts q WHERE q.Id = pm.ParentId AND pm.PostTypeId = 2) AS TimeToAnswerHours
    FROM PostMetrics pm
),
UserAggregatedPostMetrics AS (
    SELECT
        qac.UserId,
        SUM(CASE WHEN qac.PostTypeId = 1 THEN qac.Score ELSE 0 END) AS QuestionScoreSum,
        SUM(CASE WHEN qac.PostTypeId = 2 THEN qac.Score ELSE 0 END) AS AnswerScoreSum,
        AVG(CASE WHEN qac.PostTypeId = 1 THEN qac.Score ELSE NULL END) AS AvgQuestionScore,
        AVG(CASE WHEN qac.PostTypeId = 2 THEN qac.Score ELSE NULL END) AS AvgAnswerScore,
        AVG(CASE WHEN qac.PostTypeId = 1 THEN qac.ViewCount ELSE NULL END) AS AvgQuestionViewCount,
        AVG(CASE WHEN qac.PostTypeId = 1 THEN qac.AcceptedAnswerRatio ELSE NULL END) AS AvgAcceptedAnswerRatio,
        AVG(qac.BodyLength) AS AvgPostBodyLength,
        AVG(qac.TitleLength) AS AvgPostTitleLength,
        SUM(qac.LinkedPostCount) AS TotalLinkedPosts,
        SUM(qac.DuplicatePostCount) AS TotalDuplicatePosts,
        SUM(qac.EditCount) AS TotalEditsOnPosts,
        SUM(qac.CommentCountOnPost) AS TotalCommentsOnPosts,
        SUM(qac.HasCodeSnippet) AS PostsWithCodeSnippets,
        AVG(qac.TagCountForPost) AS AvgTagsPerPost,
        AVG(qac.AvgAnswerScore) AS AvgAnswerScoreForQuestionsOwned,
        AVG(qac.ParentQuestionScore) AS AvgParentQuestionScoreForAnswers,
        AVG(qac.TimeToAnswerHours) AS AvgTimeToAnswerHours
    FROM QuestionAnswerContext qac
    GROUP BY qac.UserId
),
UserTagPosts AS (
    SELECT
        p.OwnerUserId AS UserId,
        LOWER(TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')))) AS TagName,
        p.Id AS PostId,
        p.Score AS PostScore,
        p.PostTypeId
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.Tags IS NOT NULL AND LENGTH(TRIM(p.Tags)) > 2 AND p.PostTypeId = 1
),
TagPerformanceByUser AS (
    SELECT
        utp.UserId,
        utp.TagName,
        COUNT(utp.PostId) AS PostsInTag,
        SUM(utp.PostScore) AS ScoreInTag,
        RANK() OVER (PARTITION BY utp.UserId ORDER BY COUNT(utp.PostId) DESC, SUM(utp.PostScore) DESC) AS TagRankByUser
    FROM UserTagPosts utp
    GROUP BY utp.UserId, utp.TagName
),
TopNUserTags AS (
    SELECT
        tpb.UserId,
        STRING_AGG(tpb.TagName, ', ') FILTER (WHERE tpb.TagRankByUser <= 3) AS Top3Tags,
        MAX(CASE WHEN tpb.TagRankByUser = 1 THEN tpb.TagName ELSE NULL END) AS PrimaryTag
    FROM TagPerformanceByUser tpb
    GROUP BY tpb.UserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.LastAccessDate,
    COALESCE(u.Views, 0) AS UserProfileViews,
    COALESCE(u.UpVotes, 0) AS UpvotesGivenBySystem,
    COALESCE(u.DownVotes, 0) AS DownvotesGivenBySystem,
    uca.TotalPosts,
    uca.TotalQuestions,
    uca.TotalAnswers,
    uca.TotalComments,
    uca.TotalBadges,
    uca.GoldBadges,
    uca.SilverBadges,
    uca.BronzeBadges,
    uca.TotalPostViews,
    uca.TotalPostFavorites,
    uca.TotalPostScoreReceived,
    uva.UpvotesGiven,
    uva.DownvotesGiven,
    uva.TotalBountyGiven,
    uapm.QuestionScoreSum,
    uapm.AnswerScoreSum,
    uapm.AvgQuestionScore,
    uapm.AvgAnswerScore,
    uapm.AvgQuestionViewCount,
    uapm.AvgAcceptedAnswerRatio,
    uapm.AvgPostBodyLength,
    uapm.AvgPostTitleLength,
    uapm.TotalLinkedPosts,
    uapm.TotalDuplicatePosts,
    uapm.TotalEditsOnPosts,
    uapm.TotalCommentsOnPosts,
    uapm.PostsWithCodeSnippets,
    uapm.AvgTagsPerPost,
    uapm.AvgAnswerScoreForQuestionsOwned,
    uapm.AvgParentQuestionScoreForAnswers,
    uapm.AvgTimeToAnswerHours,
    tut.Top3Tags,
    tut.PrimaryTag,
    (
        COALESCE(u.Reputation * 0.1, 0) +
        COALESCE(uca.TotalPosts * 0.5, 0) +
        COALESCE(uca.TotalQuestions * 0.7, 0) +
        COALESCE(uca.TotalAnswers * 0.8, 0) +
        COALESCE(uca.TotalPostScoreReceived * 0.2, 0) +
        COALESCE(uca.GoldBadges * 5, 0) + COALESCE(uca.SilverBadges * 2, 0) +
        COALESCE(uapm.AvgAcceptedAnswerRatio * 100, 0) +
        COALESCE(uapm.AvgQuestionScore * 0.1, 0) +
        COALESCE(uapm.AvgAnswerScore * 0.15, 0) +
        COALESCE(uapm.PostsWithCodeSnippets * 0.3, 0) +
        COALESCE(u.Views * 0.01, 0) +
        CASE WHEN u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 100 THEN 10 ELSE 0 END +
        CASE WHEN u.WebsiteUrl IS NOT NULL THEN 5 ELSE 0 END +
        (SELECT COUNT(ph.Id) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 10 AND ph.CreationDate >= u.CreationDate - INTERVAL '1 year') * -2
    ) AS RawInfluenceScore,
    RANK() OVER (ORDER BY (
        COALESCE(u.Reputation * 0.1, 0) +
        COALESCE(uca.TotalPosts * 0.5, 0) +
        COALESCE(uca.TotalQuestions * 0.7, 0) +
        COALESCE(uca.TotalAnswers * 0.8, 0) +
        COALESCE(uca.TotalPostScoreReceived * 0.2, 0) +
        COALESCE(uca.GoldBadges * 5, 0) + COALESCE(uca.SilverBadges * 2, 0) +
        COALESCE(uapm.AvgAcceptedAnswerRatio * 100, 0) +
        COALESCE(uapm.AvgQuestionScore * 0.1, 0) +
        COALESCE(uapm.AvgAnswerScore * 0.15, 0) +
        COALESCE(uapm.PostsWithCodeSnippets * 0.3, 0) +
        COALESCE(u.Views * 0.01, 0) +
        CASE WHEN u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 100 THEN 10 ELSE 0 END +
        CASE WHEN u.WebsiteUrl IS NOT NULL THEN 5 ELSE 0 END +
        (SELECT COUNT(ph.Id) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 10 AND ph.CreationDate >= u.CreationDate - INTERVAL '1 year') * -2
    ) DESC) AS OverallInfluenceRank,
    NTILE(10) OVER (ORDER BY (
        COALESCE(u.Reputation * 0.1, 0) +
        COALESCE(uca.TotalPosts * 0.5, 0) +
        COALESCE(uca.TotalQuestions * 0.7, 0) +
        COALESCE(uca.TotalAnswers * 0.8, 0) +
        COALESCE(uca.TotalPostScoreReceived * 0.2, 0) +
        COALESCE(uca.GoldBadges * 5, 0) + COALESCE(uca.SilverBadges * 2, 0) +
        COALESCE(uapm.AvgAcceptedAnswerRatio * 100, 0) +
        COALESCE(uapm.AvgQuestionScore * 0.1, 0) +
        COALESCE(uapm.AvgAnswerScore * 0.15, 0) +
        COALESCE(uapm.PostsWithCodeSnippets * 0.3, 0) +
        COALESCE(u.Views * 0.01, 0) +
        CASE WHEN u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 100 THEN 10 ELSE 0 END +
        CASE WHEN u.WebsiteUrl IS NOT NULL THEN 5 ELSE 0 END +
        (SELECT COUNT(ph.Id) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 10 AND ph.CreationDate >= u.CreationDate - INTERVAL '1 year') * -2
    ) DESC) AS InfluenceDecile
FROM Users u
LEFT JOIN UserCoreActivity uca ON u.Id = uca.UserId
LEFT JOIN UserVoteActivity uva ON u.Id = uva.UserId
LEFT JOIN UserAggregatedPostMetrics uapm ON u.Id = uapm.UserId
LEFT JOIN TopNUserTags tut ON u.Id = tut.UserId
WHERE
    u.Reputation > 1000
    AND u.LastAccessDate >= CURRENT_DATE - INTERVAL '2 years'
    AND (u.Location ILIKE '%USA%' OR u.Location ILIKE '%Canada%' OR u.Location IS NULL)
ORDER BY OverallInfluenceRank ASC, u.Id ASC
LIMIT 100;