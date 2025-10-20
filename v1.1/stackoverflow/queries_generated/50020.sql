-- {"query": "50020.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1415} 

WITH PopularTags AS (
    SELECT
        t.TagName,
        t.Id
    FROM Tags t
    WHERE t.Count > 10000 AND t.IsRequired = false
),
UserContributionDetails AS (
    SELECT
        p.OwnerUserId AS UserId,
        p.Score AS PostScore,
        p.PostTypeId,
        p.ParentId,
        p.Tags,
        p.CreationDate AS PostCreationDate,
        p.Id AS PostId,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS Upvotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS Downvotes,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountOnPost
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.CreationDate > (NOW() - INTERVAL '5 year')
),
AnswerStats AS (
    SELECT
        ucd_a.UserId,
        AVG(ucd_a.PostScore) AS AverageAnswerScore,
        SUM(ucd_a.PostScore) AS TotalAnswerScore,
        COUNT(ucd_a.PostId) AS TotalAnswersInPopularTags,
        SUM(CASE WHEN q.AcceptedAnswerId = ucd_a.PostId THEN 1 ELSE 0 END) AS AcceptedAnswerCount,
        SUM(ucd_a.Upvotes) AS TotalUpvotesOnAnswers,
        SUM(ucd_a.Downvotes) AS TotalDownvotesOnAnswers,
        AVG(ucd_a.CommentCountOnPost) AS AvgCommentsPerAnswer
    FROM UserContributionDetails ucd_a
    JOIN Posts q ON ucd_a.ParentId = q.Id AND q.PostTypeId = 1
    JOIN PopularTags pt ON q.Tags LIKE '%' || pt.TagName || '%'
    WHERE ucd_a.PostTypeId = 2
    GROUP BY ucd_a.UserId
    HAVING COUNT(ucd_a.PostId) > 20
),
QuestionStats AS (
    SELECT
        ucd_q.UserId,
        AVG(ucd_q.PostScore) AS AverageQuestionScore,
        COUNT(ucd_q.PostId) AS TotalQuestionsInPopularTags,
        SUM(ucd_q.Upvotes) AS TotalUpvotesOnQuestions
    FROM UserContributionDetails ucd_q
    JOIN PopularTags pt ON ucd_q.Tags LIKE '%' || pt.TagName || '%'
    WHERE ucd_q.PostTypeId = 1
    GROUP BY ucd_q.UserId
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
FinalUserScores AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Views AS ProfileViews,
        COALESCE(ans.TotalAnswersInPopularTags, 0) AS NumAnswers,
        COALESCE(qs.TotalQuestionsInPopularTags, 0) AS NumQuestions,
        COALESCE(ans.AverageAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(ans.AcceptedAnswerCount, 0) AS AcceptedAnswers,
        COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
        COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
        COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
        (
            (u.Reputation * 0.1) +
            (COALESCE(ans.TotalAnswerScore, 0) * 0.3) +
            (COALESCE(ans.AcceptedAnswerCount, 0) * 15) +
            (COALESCE(ubs.GoldBadges, 0) * 100) +
            (COALESCE(ubs.SilverBadges, 0) * 30) +
            (COALESCE(ubs.BronzeBadges, 0) * 10) +
            (COALESCE(ans.TotalUpvotesOnAnswers, 0) * 0.2) -
            (COALESCE(ans.TotalDownvotesOnAnswers, 0) * 0.5) +
            (LN(GREATEST(u.Views, 1)) * 5) -
            (EXTRACT(EPOCH FROM (NOW() - ubs.LastBadgeDate)) / (3600 * 24 * 90))
        ) AS EngagementScore
    FROM Users u
    INNER JOIN AnswerStats ans ON u.Id = ans.UserId
    LEFT JOIN QuestionStats qs ON u.Id = qs.UserId
    LEFT JOIN UserBadgeStats ubs ON u.Id = ubs.UserId
    WHERE u.Reputation > 5000 AND u.Id > 0
)
SELECT
    UserId,
    DisplayName,
    Reputation,
    CAST(EngagementScore AS INT) AS EngagementScore,
    NumAnswers,
    NumQuestions,
    AcceptedAnswers,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    CAST(AvgAnswerScore AS DECIMAL(10, 2)) AS AvgAnswerScore,
    DENSE_RANK() OVER (ORDER BY EngagementScore DESC, Reputation DESC) AS UserRank,
    (SELECT STRING_AGG(ph.Comment, ' | ') FROM PostHistory ph WHERE ph.UserId = fs.UserId AND ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL LIMIT 5) AS RecentCloseReasons
FROM FinalUserScores fs
WHERE EngagementScore > 0
ORDER BY UserRank, UserId
LIMIT 200;
