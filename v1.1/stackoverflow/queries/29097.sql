WITH PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostType,
        COALESCE(p.ViewCount, 0) + COALESCE(p.FavoriteCount, 0) AS EngagementScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserScore
    FROM Posts p
    WHERE p.CreationDate >= DATE '2019-01-01' AND p.CreationDate < DATE '2023-01-01'
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT ps.Id) AS TotalPosts,
        SUM(CASE WHEN ps.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN ps.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        MAX(ps.CreationDate) AS LastPostDate,
        SUM(ps.Score) AS TotalScore,
        AVG(ps.Score) AS AvgScore,
        SUM(ps.ViewCount) AS TotalViews
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
AnswerStats AS (
    SELECT 
        ps.ParentId,
        COUNT(ps.Id) AS AnswerCount,
        SUM(ps.Score) AS TotalAnswerScore,
        AVG(ps.Score) AS AvgAnswerScore,
        MAX(ps.LastActivityDate) AS LastAnswerActivity,
        -- use a generic string aggregation function; if STRING_AGG not available replace with appropriate function for dialect
        STRING_AGG(ps.Title, '; ') AS AnswerTitles
    FROM PostStats ps
    WHERE ps.PostTypeId = 2
    GROUP BY ps.ParentId
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Minor'
            ELSE 'Rare'
        END AS TagPopularityLevel,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS RankByPopularity
    FROM Tags t
),
TopTags AS (
    SELECT TagName, Count FROM TagAnalysis WHERE RankByPopularity <= 100
),
QuestionWithAnswers AS (
    SELECT 
        qs.Id AS QuestionId,
        qs.Title AS QuestionTitle,
        qs.Score AS QuestionScore,
        qs.AnswerCount,
        qs.ViewCount,
        qs.CreationDate AS QuestionDate,
        qs.OwnerUserId,
        COALESCE(as_.AnswerCount, 0) AS AnswerCountActual,
        COALESCE(as_.TotalAnswerScore, 0) AS TotalAnswerScore,
        COALESCE(as_.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(as_.AnswerTitles, '') AS AnswerTitles,
        qs.Tags,
        -- convert tags like "<tag1><tag2>" into array; use standard functions where available
        CASE 
            WHEN qs.Tags IS NULL OR qs.Tags = '' THEN NULL
            ELSE regexp_split_to_array(trim(both '<' FROM replace(qs.Tags, '><', '>|<')), '\\|')
        END AS TagArray,
        CASE WHEN qs.AnswerCount > 0 THEN 'Has Answers' ELSE 'No Answers' END AS AnswerStatus,
        -- compute days difference as integer number of days; use EXTRACT(EPOCH FROM ...) alternative where supported
        CAST(EXTRACT(EPOCH FROM (COALESCE(qs.LastActivityDate, qs.CreationDate) - qs.CreationDate)) / 86400 AS INTEGER) AS DaysSinceLastActivity
    FROM PostStats qs
    LEFT JOIN AnswerStats as_ ON qs.Id = as_.ParentId
    WHERE qs.PostTypeId = 1
),
UserBadges AS (
    SELECT 
        b.UserId,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        STRING_AGG(b.Name, ', ') AS BadgeNames,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
ComplexPostQuery AS (
    SELECT 
        qwa.QuestionId,
        qwa.QuestionTitle,
        qwa.QuestionScore,
        qwa.AnswerCountActual,
        qwa.TotalAnswerScore,
        qwa.AvgAnswerScore,
        qwa.AnswerTitles,
        qwa.QuestionDate,
        qwa.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        qwa.Tags,
        qwa.TagArray,
        ua.TotalPosts,
        ua.QuestionCount,
        ua.AnswerCount AS UserAnswerCount,
        ua.TotalScore AS UserTotalScore,
        ua.AvgScore AS UserAvgScore,
        ua.LastPostDate,
        ub.BadgeCount,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.BadgeNames,
        ub.LastBadgeDate,
        CASE 
            WHEN qwa.QuestionScore > (SELECT AVG(QuestionScore) FROM QuestionWithAnswers) THEN 'Above Average'
            WHEN qwa.QuestionScore < (SELECT AVG(QuestionScore) FROM QuestionWithAnswers) THEN 'Below Average'
            ELSE 'Average'
        END AS ScoreCategory,
        (CASE WHEN qwa.AnswerCountActual >= 3 THEN 'Well Answered' ELSE 'Poorly Answered' END) AS AnswerQuality,
        (CASE 
            WHEN qwa.DaysSinceLastActivity <= 30 THEN 'Recently Active'
            WHEN qwa.DaysSinceLastActivity <= 90 THEN 'Moderately Active'
            ELSE 'Inactive'
        END) AS ActivityStatus,
        ROW_NUMBER() OVER (ORDER BY qwa.QuestionScore DESC) AS ScoreRank,
        DENSE_RANK() OVER (PARTITION BY qwa.OwnerUserId ORDER BY qwa.QuestionScore DESC) AS UserScoreRank,
        CASE 
            WHEN (qwa.QuestionScore > 0 AND qwa.AnswerCountActual > 0) THEN 
                (qwa.QuestionScore - (qwa.AnswerCountActual * 2)) 
            ELSE 0 
        END AS AdjustedScore,
        (
            'Q-' || CAST(qwa.QuestionId AS VARCHAR) || ' | ' ||
            CASE WHEN qwa.AnswerCountActual > 0 THEN ('A-' || CAST(qwa.AnswerCountActual AS VARCHAR) || ' | ') ELSE '' END ||
            'P-' || CAST(qwa.QuestionScore AS VARCHAR) || ' | ' || COALESCE(ub.BadgeNames, 'No Badges')
        ) AS PostSummary,
        CASE WHEN qwa.QuestionScore > 10 THEN 1 ELSE 0 END AS HighValueQuestion,
        CASE WHEN qwa.Tags LIKE '%<sql>%' THEN 1 ELSE 0 END AS SQLTagged,
        CASE 
            WHEN qwa.QuestionScore > 0 AND qwa.AnswerCountActual > 0 AND 
                 (CASE WHEN qwa.AnswerCountActual = 0 THEN NULL ELSE (qwa.TotalAnswerScore / qwa.AnswerCountActual) END) > qwa.QuestionScore
            THEN 'Highly Rated Answers'
            ELSE 'Regular Answers'
        END AS AnswerQualityIndicator
    FROM QuestionWithAnswers qwa
    LEFT JOIN Users u ON qwa.OwnerUserId = u.Id
    LEFT JOIN UserActivity ua ON qwa.OwnerUserId = ua.UserId
    LEFT JOIN UserBadges ub ON qwa.OwnerUserId = ub.UserId
    WHERE qwa.QuestionScore >= 0 AND 
          (qwa.QuestionScore > (SELECT AVG(QuestionScore) FROM QuestionWithAnswers) OR 
           (qwa.AnswerCountActual >= 1 AND qwa.QuestionScore > 5))
),
FinalStats AS (
    SELECT 
        cq.QuestionId,
        cq.QuestionTitle,
        cq.QuestionScore,
        cq.AnswerCountActual,
        cq.TotalAnswerScore,
        cq.AvgAnswerScore,
        cq.AnswerTitles,
        cq.QuestionDate,
        cq.OwnerUserId,
        cq.OwnerDisplayName,
        cq.Tags,
        cq.TagArray,
        cq.TotalPosts,
        cq.QuestionCount,
        cq.UserAnswerCount,
        cq.UserTotalScore,
        cq.UserAvgScore,
        cq.LastPostDate,
        cq.BadgeCount,
        cq.GoldBadges,
        cq.SilverBadges,
        cq.BronzeBadges,
        cq.BadgeNames,
        cq.LastBadgeDate,
        cq.ScoreCategory,
        cq.AnswerQuality,
        cq.ActivityStatus,
        cq.ScoreRank,
        cq.UserScoreRank,
        cq.AdjustedScore,
        cq.PostSummary,
        cq.HighValueQuestion,
        cq.SQLTagged,
        cq.AnswerQualityIndicator,
        CASE 
            WHEN cq.ScoreRank <= 10 THEN 'Top 10'
            WHEN cq.ScoreRank <= 50 THEN 'Top 50'
            WHEN cq.ScoreRank <= 100 THEN 'Top 100'
            ELSE 'Below Top 100'
        END AS PerformanceTier,
        DENSE_RANK() OVER (ORDER BY cq.UserTotalScore DESC) AS UserPerformanceRank,
        CASE 
            WHEN cq.UserTotalScore >= 10000 THEN 'Elite'
            WHEN cq.UserTotalScore >= 5000 THEN 'Advanced'
            WHEN cq.UserTotalScore >= 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END AS UserSkillLevel,
        ABS(cq.QuestionScore - cq.AvgAnswerScore) AS ScoreDeviation,
        CASE 
            WHEN cq.OwnerDisplayName IS NULL THEN 'Deleted User'
            ELSE cq.OwnerDisplayName 
        END AS DisplayUserName
    FROM ComplexPostQuery cq
)
SELECT 
    fs.QuestionId,
    fs.QuestionTitle,
    fs.QuestionScore,
    fs.AnswerCountActual,
    fs.TotalAnswerScore,
    fs.AvgAnswerScore,
    fs.QuestionDate,
    fs.OwnerUserId,
    fs.DisplayUserName,
    fs.Tags,
    fs.ScoreCategory,
    fs.AnswerQuality,
    fs.ActivityStatus,
    fs.ScoreRank,
    fs.UserScoreRank,
    fs.AdjustedScore,
    fs.PostSummary,
    fs.HighValueQuestion,
    fs.SQLTagged,
    fs.AnswerQualityIndicator,
    fs.PerformanceTier,
    fs.UserPerformanceRank,
    fs.UserSkillLevel,
    fs.ScoreDeviation,
    fs.BadgeCount,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    fs.BadgeNames,
    fs.LastBadgeDate
FROM FinalStats fs
WHERE fs.QuestionId IS NOT NULL
  AND (fs.QuestionScore > 5 OR fs.AnswerCountActual > 0)
  AND fs.QuestionTitle IS NOT NULL
ORDER BY fs.QuestionScore DESC, fs.AnswerCountActual DESC
FETCH FIRST 1000 ROWS ONLY;