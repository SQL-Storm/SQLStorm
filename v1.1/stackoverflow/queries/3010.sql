WITH UserReputationStats AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        COALESCE(SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END), 0) AS TotalVotesReceived,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        SUM(CASE WHEN LOWER(p.Body) LIKE '%performance%' THEN 1 ELSE 0 END) AS PostsWithPerformanceKeyword,
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
        CASE WHEN ph.PostHistoryTypeId IN (4,7) THEN ph.Comment ELSE NULL END AS OldTitle,
        CASE WHEN ph.PostHistoryTypeId IN (5,8) THEN ph.Text ELSE NULL END AS OldBody,
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
        (SELECT SUM(a.Score) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS SumAnswerScores,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS QuestionCommentCount,
        (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS NumberOfAnswers,
        (SELECT AVG(a.Score) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS AvgAnswerScore,
        (SELECT MAX(a.Score) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS MaxAnswerScore
    FROM Posts p
    WHERE p.PostTypeId = 1
),
TagPopularity AS (
    SELECT 
        t.TagName,
        t.ExcerptPostId,
        t.WikiPostId,
        t.Count AS TagQuestionCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalViewsForTag,
        (SELECT COUNT(*) FROM Posts a WHERE a.ParentId IN (
            SELECT Id FROM Posts WHERE Tags LIKE '%' || t.TagName || '%') AND a.PostTypeId = 2) AS AnswersWithTag
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE t.IsModeratorOnly = FALSE
    GROUP BY t.TagName, t.ExcerptPostId, t.WikiPostId, t.Count
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
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        pas.SumAnswerScores,
        pas.QuestionCommentCount,
        pas.NumberOfAnswers,
        pas.AvgAnswerScore,
        pas.MaxAnswerScore,
        th.OldTitle,
        th.OldBody,
        th.ChangeCount,
        p.Tags,
        tp.TagName,
        tp.TagQuestionCount,
        tp.TotalViewsForTag,
        tp.AnswersWithTag,
        p.PostTypeId
    FROM UserReputationStats u
    LEFT JOIN Posts p ON p.OwnerUserId = u.UserId
    LEFT JOIN PostAnswerStats pas ON pas.PostId = p.Id
    LEFT JOIN RecentPostChanges th ON th.PostId = p.Id
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id AND pl.LinkTypeId = 3
    LEFT JOIN TagPopularity tp ON p.Tags LIKE '%' || tp.TagName || '%'
)
SELECT 
    ar.UserId,
    ar.DisplayName,
    ar.TotalVotesReceived,
    ar.GoldBadges,
    ar.SilverBadges,
    ar.BronzeBadges,
    STRING_AGG(ar.Title, '; ') FILTER (WHERE ar.ChangeCount > 0) AS RecentChangedQuestions,
    CASE WHEN COUNT(DISTINCT ar.PostId) FILTER (WHERE ar.NumberOfAnswers > 0) = 0 THEN NULL
         ELSE COUNT(DISTINCT ar.PostId) FILTER (WHERE ar.PostTypeId = 2) * 1.0 / NULLIF(COUNT(DISTINCT ar.PostId) FILTER (WHERE ar.PostTypeId = 1), 0) END AS AnswerQuestionRatio,
    STRING_AGG(DISTINCT ar.TagName, ', ') AS PopularTags,
    SUM(CASE WHEN ar.TagName IN (
        SELECT TagName FROM TagPopularity ORDER BY TagQuestionCount DESC LIMIT 5
    ) THEN ar.ViewCount ELSE 0 END) AS TopTagsTotalViews,
    SUM(ar.SumAnswerScores) OVER (PARTITION BY ar.UserId ORDER BY ar.UserId ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeAnswerScore
FROM AggregateResults ar
WHERE ar.UserId IS NOT NULL
GROUP BY 
    ar.UserId, 
    ar.DisplayName, 
    ar.TotalVotesReceived, 
    ar.GoldBadges, 
    ar.SilverBadges, 
    ar.BronzeBadges, 
    ar.RepuUnlessNoBadges,
    ar.SumAnswerScores,
    ar.ViewCount,
    ar.ChangeCount,
    ar.TagName,
    ar.PostId,
    ar.PostTypeId,
    ar.Title
;