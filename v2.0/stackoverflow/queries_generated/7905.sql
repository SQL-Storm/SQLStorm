-- {"query": "7905.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2417} 
WITH PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
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
        p.Body,
        COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
            WHEN p.PostTypeId = 5 THEN 'TagWiki'
            WHEN p.PostTypeId = 6 THEN 'ModeratorNomination'
            WHEN p.PostTypeId = 7 THEN 'WikiPlaceholder'
            WHEN p.PostTypeId = 8 THEN 'PrivilegeWiki'
            ELSE 'Unknown'
        END AS PostTypeName,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as RankByScore,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) as RowNum,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as RankByViews,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgScore,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as TotalPosts,
        PERCENT_RANK() OVER (ORDER BY p.Score) as PercentileRank
    FROM Posts p
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE WHEN t.IsRequired = 1 THEN 'Required' ELSE 'Optional' END AS TagType,
        CASE WHEN t.IsModeratorOnly = 1 THEN 'Moderator Only' ELSE 'Public' END AS AccessLevel,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as TagRank,
        CAST(CEILING(LOG10(t.Count + 1)) AS INT) as LogCountGroup,
        LAG(t.Count, 1) OVER (ORDER BY t.Count DESC) as PrevCount,
        COALESCE(t.Count, 0) - COALESCE(LAG(t.Count, 1) OVER (ORDER BY t.Count DESC), 0) as CountDifference
    FROM Tags t
),
UserActivity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        u.CreationDate,
        u.LastAccessDate,
        DATEDIFF(DAY, u.CreationDate, u.LastAccessDate) as DaysSinceRegistration,
        CASE 
            WHEN u.Reputation >= 1000000 THEN 'Legendary'
            WHEN u.Reputation >= 100000 THEN 'Master'
            WHEN u.Reputation >= 10000 THEN 'Expert'
            WHEN u.Reputation >= 1000 THEN 'Advanced'
            WHEN u.Reputation >= 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END AS ReputationTier,
        AVG(p.Score) OVER (PARTITION BY u.Id) as AvgPostScore,
        COUNT(DISTINCT p.Id) OVER (PARTITION BY u.Id) as TotalPosts,
        COUNT(DISTINCT c.Id) OVER (PARTITION BY u.Id) as TotalComments,
        COUNT(DISTINCT b.Id) OVER (PARTITION BY u.Id) as TotalBadges,
        COALESCE(SUM(p.Score) OVER (PARTITION BY u.Id), 0) as TotalScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
),
BadgesByUser AS (
    SELECT 
        b.UserId,
        COUNT(*) as BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) as GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) as SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) as BronzeBadges,
        STRING_AGG(b.Name, ', ') WITHIN GROUP (ORDER BY b.Date) as BadgesList,
        MAX(b.Date) as LastBadgeDate,
        MIN(b.Date) as FirstBadgeDate,
        DATEDIFF(DAY, MIN(b.Date), MAX(b.Date)) as BadgeDurationDays
    FROM Badges b
    GROUP BY b.UserId
),
AnswerQuality AS (
    SELECT 
        p.Id,
        p.ParentId,
        p.Score,
        p.OwnerUserId,
        p.CreationDate,
        p.LastActivityDate,
        CASE 
            WHEN p.Score >= 10 THEN 'High Quality'
            WHEN p.Score >= 5 THEN 'Medium Quality'
            WHEN p.Score >= 1 THEN 'Low Quality'
            ELSE 'Very Low Quality'
        END AS QualityLevel,
        RANK() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC) as AnswerRankByScore,
        COUNT(*) OVER (PARTITION BY p.ParentId) as TotalAnswers,
        AVG(p.Score) OVER (PARTITION BY p.ParentId) as AvgScorePerQuestion
    FROM Posts p
    WHERE p.PostTypeId = 2
),
PostHistoryAnalysis AS (
    SELECT 
        ph.PostId,
        COUNT(*) as TotalEdits,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6) THEN 1 ELSE 0 END) as EditEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN 1 ELSE 0 END) as StatusEvents,
        STRING_AGG(ph.Comment, '; ') WITHIN GROUP (ORDER BY ph.CreationDate) as EditComments,
        MAX(ph.CreationDate) as LastEditDate,
        MIN(ph.CreationDate) as FirstEditDate
    FROM PostHistory ph
    GROUP BY ph.PostId
),
ComplexQueryResults AS (
    SELECT 
        ps.Id as PostId,
        ps.PostTypeName,
        ps.Title,
        ps.Tags,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.RankByScore,
        ps.PercentileRank,
        ps.RowNum,
        ps.TotalPosts,
        ps.AvgScore,
        ps.PrevScore,
        ps.NextScore,
        u.DisplayName as OwnerDisplayName,
        u.Reputation as OwnerReputation,
        u.Views as OwnerViews,
        ba.BadgeCount,
        ba.GoldBadges,
        ba.SilverBadges,
        ba.BronzeBadges,
        ta.TagName,
        ta.Count as TagCount,
        ta.TagRank,
        aq.QualityLevel,
        aq.AnswerRankByScore,
        ph.TotalEdits,
        ph.EditEvents,
        ph.StatusEvents,
        CASE 
            WHEN ps.Score > (SELECT AVG(Score) FROM Posts) THEN 'Above Average'
            WHEN ps.Score < (SELECT AVG(Score) FROM Posts) THEN 'Below Average'
            ELSE 'Average'
        END as ScorePerformance,
        CASE 
            WHEN ps.PostTypeId = 1 AND ps.AcceptedAnswerId > 0 THEN 'Question with Accepted Answer'
            WHEN ps.PostTypeId = 1 THEN 'Question without Answer'
            WHEN ps.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostCategory,
        COALESCE(ps.Score, 0) + COALESCE(ps.ViewCount, 0) + COALESCE(ps.AnswerCount, 0) as ActivityMetric,
        CASE 
            WHEN ps.AnswerCount > 0 THEN ROUND(CAST(ps.ViewCount AS FLOAT) / CAST(ps.AnswerCount AS FLOAT), 2)
            ELSE 0.00
        END as ViewsPerAnswer,
        CASE 
            WHEN ps.CommentCount > 0 THEN ROUND(CAST(ps.Score AS FLOAT) / CAST(ps.CommentCount AS FLOAT), 2)
            ELSE 0.00
        END as ScorePerComment,
        CASE 
            WHEN u.Reputation >= 10000 THEN 1
            WHEN u.Reputation >= 1000 THEN 0.5
            WHEN u.Reputation >= 100 THEN 0.25
            ELSE 0.1
        END as RepMultiplier,
        CONCAT('Post_', ps.Id, '_by_', u.DisplayName) as PostIdentifier,
        CASE 
            WHEN ps.CreationDate > CURRENT_TIMESTAMP - INTERVAL '7' DAY THEN 'Recent'
            WHEN ps.CreationDate > CURRENT_TIMESTAMP - INTERVAL '30' DAY THEN 'Within Month'
            ELSE 'Old'
        END as TimeCategory,
        CASE 
            WHEN ps.Score > 0 THEN 'Positive Score'
            WHEN ps.Score < 0 THEN 'Negative Score'
            ELSE 'Zero Score'
        END as ScoreClassification,
        CASE 
            WHEN ps.Tags IS NOT NULL AND LENGTH(ps.Tags) > 0 THEN
                CONCAT('Tags: ', TRIM(BOTH '<>' FROM ps.Tags), ' | Tag Count: ', 
                       (LENGTH(ps.Tags) - LENGTH(REPLACE(ps.Tags, '><', '')) + 1))
            ELSE 'No Tags'
        END as TagDetails,
        CASE 
            WHEN u.AccountId IS NOT NULL THEN 'User Account Present'
            ELSE 'No Account'
        END as AccountStatus,
        COALESCE(ph.LastEditDate, ps.CreationDate) as EffectiveLastActivityDate,
        COALESCE(ba.LastBadgeDate, ps.CreationDate) as LastActivityDate,
        ps.ViewCount + (ps.AnswerCount * 5) + (ps.CommentCount * 2) as WeightedActivityScore
    FROM PostStats ps
    LEFT JOIN Users u ON ps.OwnerUserId = u.Id
    LEFT JOIN BadgesByUser ba ON u.Id = ba.UserId
    LEFT JOIN TagAnalysis ta ON ta.TagName = SUBSTRING(ps.Tags, 2, LENGTH(ps.Tags) - 2)
    LEFT JOIN AnswerQuality aq ON ps.Id = aq.ParentId
    LEFT JOIN PostHistoryAnalysis ph ON ps.Id = ph.PostId
    WHERE ps.Score IS NOT NULL 
)
SELECT 
    *,
    CASE 
        WHEN PostCategory = 'Question without Answer' AND ScorePerformance = 'Below Average' THEN 'Poor Question'
        WHEN PostCategory = 'Question with Accepted Answer' AND ScorePerformance = 'Above Average' THEN 'Excellent Question'
        WHEN PostCategory = 'Answer' AND QualityLevel IN ('High Quality', 'Medium Quality') THEN 'Useful Answer'
        ELSE 'Standard Post'
    END as PostEvaluation,
    ROW_NUMBER() OVER (ORDER BY WeightedActivityScore DESC) as OverallRank
FROM ComplexQueryResults
WHERE WeightedActivityScore > 0 
HAVING COUNT(*) OVER () > 0
ORDER BY WeightedActivityScore DESC, PostId
LIMIT 1000;