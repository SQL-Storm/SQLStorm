-- {"query": "1110.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2849} 

WITH UserPostStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalPostScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(CAST(p.Score AS NUMERIC)) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalPostViews,
        SUM(p.FavoriteCount) AS TotalFavorites,
        MAX(p.LastActivityDate) AS LastPostActivity
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserCommentStats AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        SUM(c.Score) AS TotalCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MIN(b.Date) AS FirstBadgeDate,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
UserVoteBehavior AS (
    SELECT
        v.UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoritesMade,
        SUM(CASE WHEN v.BountyAmount IS NOT NULL AND v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS TotalBountyGiven
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
UserTopQuestions AS (
    SELECT
        p.OwnerUserId AS UserId,
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS Rnk_ScoreView,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC, p.Score DESC) AS Rnk_ViewScore
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
),
TopQuestionDetails AS (
    SELECT
        tq.UserId,
        MAX(CASE WHEN tq.Rnk_ScoreView = 1 THEN tq.Title END) AS TopScoringQuestionTitle,
        MAX(CASE WHEN tq.Rnk_ScoreView = 1 THEN tq.Score END) AS TopScoringQuestionScore,
        MAX(CASE WHEN tq.Rnk_ScoreView = 1 THEN tq.PostId END) AS TopScoringQuestionId,
        MAX(CASE WHEN tq.Rnk_ViewScore = 1 THEN tq.PostId END) AS MostViewedQuestionId,
        MAX(CASE WHEN tq.Rnk_ViewScore = 1 THEN tq.Title END) AS MostViewedQuestionTitle,
        MAX(CASE WHEN tq.Rnk_ViewScore = 1 THEN tq.ViewCount END) AS MostViewedQuestionViews
    FROM UserTopQuestions tq
    WHERE tq.Rnk_ScoreView = 1 OR tq.Rnk_ViewScore = 1
    GROUP BY tq.UserId
),
PostTagAnalysis_Raw AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Tags,
        p.Score,
        p.CommentCount,
        STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><') AS TagArray
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.OwnerUserId IS NOT NULL
),
AggregatedTagUsage AS (
    SELECT
        pta.OwnerUserId AS UserId,
        unnest(pta.TagArray) AS TagName,
        COUNT(DISTINCT pta.PostId) AS QuestionsWithTag,
        SUM(pta.Score) AS TaggedPostScore,
        AVG(CAST(pta.CommentCount AS NUMERIC)) AS AvgCommentsPerTaggedPost
    FROM PostTagAnalysis_Raw pta
    GROUP BY pta.OwnerUserId, unnest(pta.TagArray)
),
TopUserTag AS (
    SELECT
        atu.UserId,
        atu.TagName AS MostFrequentTag,
        atu.QuestionsWithTag AS TagQuestionsCount,
        ROW_NUMBER() OVER (PARTITION BY atu.UserId ORDER BY atu.QuestionsWithTag DESC, atu.TaggedPostScore DESC) AS rn
    FROM AggregatedTagUsage atu
),
UserMostFrequentTag AS (
    SELECT UserId, MostFrequentTag, TagQuestionsCount
    FROM TopUserTag
    WHERE rn = 1
),
PostEvolutionSummary AS (
    SELECT
        ph.PostId,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 101) THEN 1 ELSE 0 END) AS CloseEvents, -- Post Closed / Duplicate
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenEvents, -- Post Reopened
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditEvents, -- Edit Title, Body, Tags
        MAX(ph.CreationDate) AS LastEditOrCloseEvent,
        MIN(ph.CreationDate) AS FirstEditOrCloseEvent,
        MAX(LENGTH(ph.Text)) FILTER (WHERE ph.PostHistoryTypeId IN (2, 5)) AS MaxBodyLengthChange
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (2,4,5,6,10,11,101)
    GROUP BY ph.PostId
),
LinkedPostDetails AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) AS TotalLinkedPosts,
        SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedFromThis, -- PostId links to RelatedPostId
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateOfThis, -- PostId is duplicate of RelatedPostId
        MAX(p.Score) AS MaxRelatedPostScore,
        AVG(COALESCE(p.CommentCount, 0)) AS AvgRelatedPostCommentCount
    FROM PostLinks pl
    JOIN Posts p ON pl.RelatedPostId = p.Id
    GROUP BY pl.PostId
),
UserPostHistoryAgg AS (
    SELECT
        ph.PostId,
        ph.UserId,
        STRING_AGG(DISTINCT pht.Name, ';') AS AllHistoryTypes,
        COUNT(DISTINCT ph.PostHistoryTypeId) AS NumDistinctHistoryTypes,
        COUNT(ph.Id) AS TotalHistoryEntries
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.PostId, ph.UserId
),
AllUserPostHistoryTypes AS (
    SELECT
        upas.UserId,
        STRING_AGG(DISTINCT upas.AllHistoryTypes, '|') AS UserAggregatedPostHistory,
        SUM(upas.TotalHistoryEntries) AS TotalUserHistoryEntries
    FROM UserPostHistoryAgg upas
    GROUP BY upas.UserId
),
QuestionAcceptanceSummary AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(p.Id) AS TotalQuestions,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
        SUM(CASE WHEN p.AcceptedAnswerId IS NULL THEN 1 ELSE 0 END) AS QuestionsWithoutAcceptedAnswer,
        AVG(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1.0 ELSE 0.0 END) AS AcceptanceRate
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views AS ProfileViews,
    COALESCE(u.Location, 'Unknown Location') AS UserLocation,
    u.WebsiteUrl,
    u.AboutMe,

    -- User Post Stats
    COALESCE(ups.TotalPosts, 0) AS TotalPostsOwned,
    COALESCE(ups.TotalPostScore, 0) AS TotalPostsScore,
    COALESCE(ups.AvgPostScore, 0.0) AS AvgPostsScore,
    COALESCE(ups.QuestionCount, 0) AS QuestionsAsked,
    COALESCE(ups.AnswerCount, 0) AS AnswersProvided,
    COALESCE(ups.TotalPostViews, 0) AS TotalPostViewsOwned,
    COALESCE(ups.TotalFavorites, 0) AS TotalFavoritesOnPosts,
    ups.LastPostActivity,

    -- User Comment Stats
    COALESCE(ucs.TotalComments, 0) AS TotalCommentsMade,
    COALESCE(ucs.TotalCommentScore, 0) AS TotalCommentScoreMade,
    ucs.LastCommentDate,

    -- User Badge Summary
    COALESCE(ubs.TotalBadges, 0) AS TotalBadgesEarned,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadgesEarned,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadgesEarned,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadgesEarned,
    ubs.FirstBadgeDate,
    EXTRACT(DAY FROM AGE(CURRENT_TIMESTAMP, ubs.FirstBadgeDate)) AS DaysSinceFirstBadge,

    -- User Vote Behavior (as a voter)
    COALESCE(uvb.UpVotesGiven, 0) AS UpvotesCast,
    COALESCE(uvb.DownVotesGiven, 0) AS DownvotesCast,
    COALESCE(uvb.FavoritesMade, 0) AS FavoritesBookmarked,
    COALESCE(uvb.TotalBountyGiven, 0) AS BountyGivenTotal,

    -- Top Question Details
    tqd.TopScoringQuestionTitle,
    tqd.TopScoringQuestionScore,
    tqd.MostViewedQuestionTitle,
    tqd.MostViewedQuestionViews,

    -- Most Frequent Tag
    umft.MostFrequentTag,
    umft.TagQuestionsCount,

    -- Post Evolution Metrics for their Most Viewed Question
    pes.CloseEvents,
    pes.ReopenEvents,
    pes.EditEvents,
    pes.MaxBodyLengthChange,
    pes.LastEditOrCloseEvent,

    -- Linked Post Details for their Highest Scoring Question
    lpd.TotalLinkedPosts,
    lpd.LinkedFromThis,
    lpd.DuplicateOfThis,
    lpd.MaxRelatedPostScore,
    lpd.AvgRelatedPostCommentCount,

    -- Overall user activity score (complicated calculation with NULL handling)
    (
        COALESCE(u.Reputation, 0) * 0.1
        + COALESCE(ups.TotalPostScore, 0) * 0.05
        + COALESCE(ucs.TotalCommentScore, 0) * 0.02
        + COALESCE(ubs.GoldBadges, 0) * 5
        + COALESCE(ubs.SilverBadges, 0) * 2
        + COALESCE(ubs.BronzeBadges