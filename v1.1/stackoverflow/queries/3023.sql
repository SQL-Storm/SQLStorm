WITH RelevantPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.LastActivityDate
    FROM Posts p
    WHERE p.PostTypeId = 1
),
RecentQuestions AS (
    SELECT 
        rp.Id AS QuestionId,
        rp.Title,
        rp.CreationDate,
        rp.OwnerUserId,
        rp.Tags,
        ROW_NUMBER() OVER (PARTITION BY rp.OwnerUserId ORDER BY rp.CreationDate DESC) AS RespRank
    FROM RelevantPosts rp
),
TopUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT rq.QuestionId) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN rq.RespRank = 1 THEN rq.QuestionId END) AS LatestQuestions
    FROM Users u
    LEFT JOIN RecentQuestions rq ON u.Id = rq.OwnerUserId
    WHERE u.Reputation >= 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
AnswerStats AS (
    SELECT 
        a.OwnerUserId,
        COUNT(*) AS AnswerCount,
        AVG(a.Score) AS AvgScore,
        SUM(CASE WHEN a.Score >= 10 THEN 1 ELSE 0 END) AS HighScoreAnswers
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.OwnerUserId
),
UserBadgeSummary AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
VoteAnalysis AS (
    SELECT 
        v.PostId,
        v.VoteTypeId,
        COUNT(*) AS VoteCount
    FROM Votes v
    GROUP BY v.PostId, v.VoteTypeId
),
PostLinksCount AS (
    SELECT 
        pl.PostId,
        COUNT(*) AS RelatedLinks
    FROM PostLinks pl
    GROUP BY pl.PostId
),
PostHistorySummary AS (
    SELECT 
        ph.PostId,
        COUNT(*) AS EditCount,
        COUNT(DISTINCT ph.UserId) AS UniqueEditors,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    GROUP BY ph.PostId
),
UserPosts AS (
    -- Precompute posts per user to avoid non-inner joins on subqueries in JOIN clauses
    SELECT Id, OwnerUserId
    FROM Posts
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(tb.TotalQuestions, 0) AS TotalQuestions,
    COALESCE(tb.LatestQuestions, 0) AS LatestQuestions,
    COALESCE(ans.AnswerCount, 0) AS TotalAnswers,
    COALESCE(ans.AvgScore, 0) AS AvgAnswerScore,
    COALESCE(ans.HighScoreAnswers, 0) AS HighScoreAnswers,
    COALESCE(ub.GoldBadges,0) AS GoldBadges,
    COALESCE(ub.SilverBadges,0) AS SilverBadges,
    COALESCE(ub.BronzeBadges,0) AS BronzeBadges,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId IN (2,3) THEN v.PostId END) AS UpvoteDownvoteCount,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId END) AS Upvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId END) AS Downvotes,
    COUNT(DISTINCT pl.PostId) AS TotalRelatedLinks,
    COALESCE(phs.EditCount,0) AS TotalEdits,
    COALESCE(phs.UniqueEditors,0) AS UniqueEditors,
    phs.LastEditDate
FROM Users u
LEFT JOIN TopUsers tb ON u.Id = tb.UserId
LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
LEFT JOIN AnswerStats ans ON u.Id = ans.OwnerUserId
LEFT JOIN UserBadgeSummary ub ON u.Id = ub.UserId
-- join Votes, PostLinks and PostHistory via UserPosts to avoid subquery-in-join issues
LEFT JOIN UserPosts up ON up.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = up.Id
LEFT JOIN PostLinks pl ON pl.PostId = up.Id
LEFT JOIN PostHistorySummary phs ON phs.PostId = up.Id
GROUP BY u.Id, u.DisplayName, u.Reputation, tb.TotalQuestions, tb.LatestQuestions,
         ans.AnswerCount, ans.AvgScore, ans.HighScoreAnswers,
         ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges,
         phs.EditCount, phs.UniqueEditors, phs.LastEditDate
ORDER BY u.Reputation DESC;