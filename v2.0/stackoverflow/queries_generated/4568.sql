-- {"query": "4568.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1353} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RowNum
    FROM Posts p
    WHERE p.PostTypeId = 1
),
UserPostEngagement AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalQuestions,
        SUM(CASE WHEN p.AnswerCount > 0 THEN 1 ELSE 0 END) AS QuestionsWithAnswers,
        AVG(p.Score) AS AverageQuestionScore,
        MAX(p.FavoriteCount) AS MaxFavoriteCount
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
LatestUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.LastAccessDate,
        MAX(p.LastActivityDate) AS LatestPostActivityDate,
        COUNT(DISTINCT c.Id) AS CommentCountOnTheirPosts
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.LastAccessDate
),
UserBadgePerformance AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeAwardedDate
    FROM Badges b
    GROUP BY b.UserId
),
PostsWithComplexCalculations AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ViewCount,
        (p.Score * 1.5 + p.AnswerCount * 2.0 + p.FavoriteCount * 0.5) AS WeightedScore,
        CASE
            WHEN p.Tags LIKE '%<sql>%' THEN 'SQL Related'
            WHEN p.Tags LIKE '%<performance>%' THEN 'Performance Related'
            WHEN p.Title ILIKE '%benchmark%' THEN 'Benchmark Query'
            ELSE 'Other'
        END AS ContentCategory,
        COALESCE(p.ClosedDate, p.CreationDate) AS EffectiveCloseDate,
        DATEDIFF(day, p.CreationDate, p.LastActivityDate) AS DaysActive
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
),
TagPerformance AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT ps.Id) AS PostsWithTag,
        AVG(ps.Score) AS AvgTagScore,
        SUM(ps.ViewCount) AS TotalTagViews
    FROM Tags t
    JOIN Posts ps ON ps.Tags LIKE '%' || t.TagName || '%'
    WHERE ps.PostTypeId = 1
    GROUP BY t.TagName
)
SELECT
    l.DisplayName,
    l.Reputation,
    l.LastAccessDate,
    COALESCE(upa.TotalQuestions, 0) AS TotalQuestionsAsked,
    COALESCE(upa.QuestionsWithAnswers, 0) AS QuestionsAnswered,
    upa.AverageQuestionScore,
    upa.MaxFavoriteCount,
    COALESCE(ubp.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubp.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubp.BronzeBadges, 0) AS BronzeBadges,
    ubp.LastBadgeAwardedDate,
    pcc.ContentCategory,
    pcc.WeightedScore,
    pcc.DaysActive,
    CASE
        WHEN pcc.Score > 50 AND pcc.AnswerCount > 10 THEN 'High Impact Question'
        WHEN pcc.Score < 0 THEN 'Negative Impact Question'
        ELSE 'Standard Question'
    END AS ImpactLevel,
    CASE
        WHEN pcc.WeightedScore > (SELECT AVG(WeightedScore) FROM PostsWithComplexCalculations) THEN 'Above Average'
        ELSE 'Below Average'
    END AS ScoreVsAvg,
    CASE
        WHEN rp.RowNum <= 3 THEN 'Top 3 Recent'
        ELSE 'Other'
    END AS RecentPostRank,
    tp.TagName AS TopPerformingTag,
    tp.AvgTagScore AS TopTagAvgScore,
    l.CommentCountOnTheirPosts AS CommentsOnTheirPosts
FROM LatestUserActivity l
LEFT JOIN UserPostEngagement upa ON l.UserId = upa.OwnerUserId
LEFT JOIN UserBadgePerformance ubp ON l.UserId = ubp.UserId
LEFT JOIN PostsWithComplexCalculations pcc ON l.UserId = pcc.OwnerUserId
LEFT JOIN RankedPosts rp ON l.UserId = rp.OwnerUserId AND rp.RowNum = 1
LEFT JOIN (
    SELECT
        tp.TagName,
        tp.AvgTagScore,
        ROW_NUMBER() OVER(PARTITION BY tp.TagName ORDER BY tp.AvgTagScore DESC) AS TagRank
    FROM TagPerformance tp
) AS tp ON tp.TagRank = 1 AND pcc.Id = (SELECT Id FROM Posts WHERE Tags LIKE '%' || tp.TagName || '%' ORDER BY Score DESC LIMIT 1)
WHERE l.Reputation > 1000
ORDER BY l.Reputation DESC, l.LastAccessDate ASC
LIMIT 100;
