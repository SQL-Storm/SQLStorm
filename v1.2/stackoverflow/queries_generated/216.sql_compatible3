WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 AS Level
    FROM Tags t
    WHERE t.IsRequired = TRUE

    UNION ALL

    SELECT
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        t2.IsModeratorOnly,
        t2.IsRequired,
        r.Level + 1
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON t2.Id <> r.Id AND t2.Count < r.Count
    WHERE r.Level < 3
),
UserBadgeCounts AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COALESCE(SUM(b.Class), 0) AS BadgeScore
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
PostActivity AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        p.Title,
        p.AcceptedAnswerId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RecentPostRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS TotalPostsByUser
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
PostWithComments AS (
    SELECT
        pa.Id,
        pa.PostTypeId,
        pa.OwnerUserId,
        pa.CreationDate,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCount,
        pa.FavoriteCount,
        pa.Tags,
        pa.Title,
        pa.AcceptedAnswerId,
        pa.RecentPostRank,
        pa.TotalPostsByUser,
        c.CommentCount,
        c.LatestCommentText,
        c.LatestCommentDate
    FROM PostActivity pa
    LEFT JOIN (
        SELECT
            PostId,
            COUNT(*) AS CommentCount,
            MAX(CreationDate) AS LatestCommentDate,
            STRING_AGG(Text, ' || ' ORDER BY CreationDate DESC) FILTER (WHERE Text IS NOT NULL) AS LatestCommentText
        FROM Comments
        GROUP BY PostId
    ) c ON pa.Id = c.PostId
),
PostLinkAggregates AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT CASE WHEN lt.Name = 'Duplicate' THEN pl.RelatedPostId END) AS DuplicateLinks,
        COUNT(DISTINCT CASE WHEN lt.Name = 'Linked' THEN pl.RelatedPostId END) AS LinkedPosts
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId
),
UserReputationWindow AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        DENSE_RANK() OVER (PARTITION BY DATE_TRUNC('year', u.CreationDate) ORDER BY u.Reputation DESC) AS YearlyReputationRank
    FROM Users u
),
ComplexPostStats AS (
    SELECT
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        COALESCE(pl.DuplicateLinks, 0) AS DuplicateLinks,
        COALESCE(pl.LinkedPosts, 0) AS LinkedPosts,
        pc.CommentCount,
        pc.LatestCommentText,
        pc.LatestCommentDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS UserTopPostRank,
        CASE WHEN EXISTS (
            SELECT 1 FROM Votes v
            WHERE v.PostId = p.Id AND v.VoteTypeId = 2 AND v.CreationDate > p.CreationDate + INTERVAL '30 days'
        ) THEN TRUE ELSE FALSE END AS HasLateUpvotes
    FROM Posts p
    LEFT JOIN PostLinkAggregates pl ON p.Id = pl.PostId
    LEFT JOIN (
        SELECT
            PostId,
            COUNT(*) AS CommentCount,
            MAX(CreationDate) AS LatestCommentDate,
            STRING_AGG(Text, ' || ' ORDER BY CreationDate DESC) FILTER (WHERE Text IS NOT NULL) AS LatestCommentText
        FROM Comments
        GROUP BY PostId
    ) pc ON p.Id = pc.PostId
    WHERE p.PostTypeId = 1
),
UserAnswerStats AS (
    SELECT
        u.Id AS UserId,
        COUNT(a.Id) AS TotalAnswers,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        SUM(CASE WHEN a.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswersCount
    FROM Users u
    LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    GROUP BY u.Id
),
FinalUserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ua.TotalAnswers,
        ua.AvgAnswerScore,
        ua.MaxAnswerScore,
        ua.AcceptedAnswersCount,
        urw.ReputationRank,
        urw.YearlyReputationRank,
        COALESCE(SUM(p.Score), 0) AS TotalQuestionScore,
        COUNT(p.Id) AS TotalQuestions,
        MAX(p.Score) AS MaxQuestionScore,
        STRING_AGG(DISTINCT r.TagName, ', ') FILTER (WHERE r.TagName IS NOT NULL) AS RequiredTagsUsed
    FROM Users u
    LEFT JOIN UserBadgeCounts ubc ON u.Id = ubc.UserId
    LEFT JOIN UserAnswerStats ua ON u.Id = ua.UserId
    LEFT JOIN UserReputationWindow urw ON u.Id = urw.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    LEFT JOIN RecursiveTagHierarchy r ON POSITION('<' || r.TagName || '>' IN COALESCE(p.Tags, '')) > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, ubc.GoldBadges, ubc.SilverBadges, ubc.BronzeBadges, ua.TotalAnswers, ua.AvgAnswerScore, ua.MaxAnswerScore, ua.AcceptedAnswersCount, urw.ReputationRank, urw.YearlyReputationRank
)
SELECT
    fus.Id AS UserId,
    fus.DisplayName,
    fus.Reputation,
    fus.GoldBadges,
    fus.SilverBadges,
    fus.BronzeBadges,
    fus.TotalAnswers,
    ROUND(CAST(fus.AvgAnswerScore AS numeric), 2) AS AvgAnswerScore,
    fus.MaxAnswerScore,
    fus.AcceptedAnswersCount,
    fus.ReputationRank,
    fus.YearlyReputationRank,
    fus.TotalQuestionScore,
    fus.TotalQuestions,
    fus.MaxQuestionScore,
    fus.RequiredTagsUsed,
    cps.Id AS TopQuestionId,
    cps.Title AS TopQuestionTitle,
    cps.Score AS TopQuestionScore,
    cps.ViewCount AS TopQuestionViews,
    cps.AnswerCount AS TopQuestionAnswers,
    cps.FavoriteCount AS TopQuestionFavorites,
    cps.DuplicateLinks,
    cps.LinkedPosts,
    cps.CommentCount AS TopQuestionComments,
    cps.LatestCommentText AS TopQuestionLatestComment,
    cps.LatestCommentDate AS TopQuestionLatestCommentDate,
    CASE
        WHEN cps.HasLateUpvotes THEN 'Yes'
        ELSE 'No'
    END AS HasLateUpvotes
FROM FinalUserStats fus
LEFT JOIN LATERAL (
    SELECT cps_sub.*
    FROM ComplexPostStats cps_sub
    WHERE cps_sub.OwnerUserId = fus.Id
    ORDER BY cps_sub.Score DESC, cps_sub.ViewCount DESC
    FETCH FIRST 1 ROW ONLY
) cps ON TRUE
WHERE fus.TotalQuestions > 5
  AND fus.GoldBadges > 0
  AND fus.ReputationRank <= 100
ORDER BY fus.ReputationRank, fus.TotalQuestionScore DESC
LIMIT 50;