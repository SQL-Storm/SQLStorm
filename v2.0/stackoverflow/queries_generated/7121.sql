-- {"query": "7121.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3211} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as RankByReputation,
        DENSE_RANK() OVER (ORDER BY u.Views DESC) as RankByViews,
        NTILE(100) OVER (ORDER BY u.Reputation) as PercentileByReputation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.OwnerUserId,
        p.PostTypeId,
        pt.Name as PostTypeName,
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
        END as PostTypeDescription,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'ModeratelyVoted'
            WHEN p.Score > 0 THEN 'SlightlyVoted'
            WHEN p.Score = 0 THEN 'Neutral'
            WHEN p.Score < 0 THEN 'DownVoted'
            ELSE 'Unknown'
        END as ScoreCategory,
        CASE 
            WHEN p.ViewCount > 10000 THEN 'Viral'
            WHEN p.ViewCount > 5000 THEN 'Popular'
            WHEN p.ViewCount > 1000 THEN 'Notable'
            WHEN p.ViewCount > 0 THEN 'Seen'
            ELSE 'Unseen'
        END as ViewCategory,
        ISNULL(p.Tags, '') as Tags,
        ISNULL(p.Body, '') as Body,
        NULLIF(p.Title, '') as TitleNotNULL,
        COALESCE(p.Title, 'No Title') as TitleOrPlaceholder,
        LTRIM(RTRIM(ISNULL(p.Title, ''))) as CleanedTitle,
        LEN(ISNULL(p.Title, '')) as TitleLength,
        p.AnswerCount - ISNULL((SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2), 0) as NetAnswerCount,
        DATEDIFF(DAY, p.CreationDate, GETDATE()) as DaysSinceCreation,
        DATEDIFF(DAY, p.LastActivityDate, GETDATE()) as DaysSinceLastActivity,
        CASE 
            WHEN p.ParentId IS NOT NULL THEN (SELECT TOP 1 Title FROM Posts WHERE Id = p.ParentId)
            ELSE NULL 
        END as ParentTitle,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
            WHEN p.PostTypeId = 1 THEN 'Unanswered'
            ELSE 'NotApplicable'
        END as QuestionStatus,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as RankByOwnerScore,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) as GlobalScoreRank
    FROM Posts p
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
),
ComplexUserAnalysis AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.PostCount,
        uas.CommentCount,
        uas.BadgeCount,
        uas.LastPostDate,
        uas.RankByReputation,
        uas.PercentileByReputation,
        CASE 
            WHEN uas.PostCount > 100 AND uas.CommentCount > 500 THEN 'HighlyActive'
            WHEN uas.PostCount > 50 AND uas.CommentCount > 250 THEN 'ModeratelyActive'
            WHEN uas.PostCount > 10 AND uas.CommentCount > 50 THEN 'OccasionallyActive'
            ELSE 'Inactive'
        END as ActivityLevel,
        CASE 
            WHEN uas.Reputation > 100000 THEN 'Legendary'
            WHEN uas.Reputation > 10000 THEN 'Master'
            WHEN uas.Reputation > 1000 THEN 'Expert'
            WHEN uas.Reputation > 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END as ReputationTier,
        CAST((ISNULL(uas.PostCount, 0) + ISNULL(uas.CommentCount, 0)) * 0.8 AS INT) as WeightedActivityScore,
        CASE 
            WHEN uas.LastPostDate IS NOT NULL AND DATEDIFF(DAY, uas.LastPostDate, GETDATE()) <= 30 THEN 'RecentlyActive'
            WHEN uas.LastPostDate IS NOT NULL AND DATEDIFF(DAY, uas.LastPostDate, GETDATE()) <= 180 THEN 'ModeratelyActive'
            ELSE 'InactiveLongTerm'
        END as RecentActivityStatus
    FROM UserActivityStats uas
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.IsModeratorOnly,
        t.IsRequired,
        CASE 
            WHEN t.Count > 10000 THEN 'VeryPopular'
            WHEN t.Count > 5000 THEN 'Popular'
            WHEN t.Count > 1000 THEN 'Moderate'
            WHEN t.Count > 100 THEN 'UnderModerate'
            ELSE 'Rare'
        END as PopularityCategory,
        ISNULL(t.ExcerptPostId, 0) as ExcerptPostId,
        ISNULL(t.WikiPostId, 0) as WikiPostId,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as PopularityRank,
        LAG(t.Count, 1) OVER (ORDER BY t.Count DESC) - t.Count as PopularityChangeFromPrevious,
        AVG(t.Count) OVER (ORDER BY t.Count ROWS BETWEEN 5 PRECEDING AND 5 FOLLOWING) as MovingAvgCount
    FROM Tags t
    WHERE t.TagName IS NOT NULL
),
ComplexAnalysisResults AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.TitleNotNULL,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.PostTypeId,
        p.PostTypeName,
        p.ScoreCategory,
        p.ViewCategory,
        p.DaysSinceCreation,
        p.DaysSinceLastActivity,
        p.ParentTitle,
        p.QuestionStatus,
        p.RankByOwnerScore,
        p.GlobalScoreRank,
        CASE 
            WHEN p.Score > 0 AND p.ViewCount > 100 THEN 'Featured'
            WHEN p.Score > 0 AND p.ViewCount > 50 THEN 'Trending'
            WHEN p.Score > 0 AND p.ViewCount > 0 THEN 'Popular'
            ELSE 'UnderReview'
        END as FeatureStatus,
        CASE 
            WHEN p.AnswerCount > 0 AND p.PostTypeId = 1 THEN 'Answered'
            WHEN p.PostTypeId = 1 THEN 'Unanswered'
            ELSE 'NotQuestion'
        END as AnswerStatus,
        CASE 
            WHEN p.LastActivityDate > DATEADD(DAY, -7, GETDATE()) THEN 'RecentlyActive'
            WHEN p.LastActivityDate > DATEADD(DAY, -30, GETDATE()) THEN 'ModeratelyActive'
            ELSE 'Inactive'
        END as TemporalActivityStatus,
        p.TitleLength,
        p.NetAnswerCount,
        CASE 
            WHEN p.Score > 5 AND p.AnswerCount > 2 THEN 'WellAnsweredQuestion'
            WHEN p.Score > 10 THEN 'HighlyRatedQuestion'
            WHEN p.AnswerCount > 5 THEN 'FrequentlyAnsweredQuestion'
            ELSE 'RegularQuestion'
        END as QuestionQualityMetric,
        CASE 
            WHEN p.PostTypeName = 'Question' AND p.ViewCategory = 'Viral' THEN 'ViralQuestion'
            WHEN p.PostTypeName = 'Question' AND p.ViewCategory = 'Popular' THEN 'PopularQuestion'
            WHEN p.PostTypeName = 'Answer' AND p.Score > 10 THEN 'HighValueAnswer'
            WHEN p.PostTypeName = 'Answer' AND p.Score > 0 THEN 'StandardAnswer'
            ELSE 'OtherContent'
        END as ContentQualityType
    FROM PostAnalysis p
    WHERE p.PostId IS NOT NULL
)
SELECT 
    ca.UserId,
    ca.DisplayName,
    ca.Reputation,
    ca.PostCount,
    ca.CommentCount,
    ca.BadgeCount,
    ca.RecentActivityStatus,
    ca.ActivityLevel,
    ca.ReputationTier,
    ca.WeightedActivityScore,
    ta.TagName,
    ta.Count as TagCount,
    ta.PopularityCategory,
    ca.ReputationTier + ' - ' + ca.ActivityLevel + ' - ' + ca.RecentActivityStatus as UserSegment,
    CASE 
        WHEN ca.Reputation > 5000 AND ca.PostCount > 50 THEN 'VeteranEngager'
        WHEN ca.Reputation > 1000 AND ca.PostCount > 10 THEN 'RegularContributor'
        WHEN ca.Reputation > 100 AND ca.PostCount > 5 THEN 'OccasionalContributor'
        ELSE 'NewUser'
    END as ContributorTier,
    IIF(ta.Count > 500, 'HighInterest', 'RegularInterest') as InterestLevel,
    CASE 
        WHEN ta.PopularityCategory IN ('VeryPopular', 'Popular') THEN 'TrendSetting'
        WHEN ta.PopularityCategory IN ('Moderate') THEN 'Established'
        WHEN ta.PopularityCategory IN ('UnderModerate') THEN 'Growing'
        ELSE 'Emerging'
    END as TrendStatus,
    LAG(ca.Reputation, 1) OVER (ORDER BY ca.Reputation DESC) - ca.Reputation as ReputationChangeFromPrevious,
    ABS(ISNULL(ta.PopularityChangeFromPrevious, 0)) as PopularityChange,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ca.UserId AND p.Score > 0 AND DATEDIFF(DAY, p.CreationDate, GETDATE()) <= 30) as RecentHighScorePosts,
    ISNULL((SELECT TOP 1 Title FROM Posts p WHERE p.OwnerUserId = ca.UserId ORDER BY p.Score DESC), 'No High Score Posts') as TopScoringPost,
    (SELECT STRING_AGG(pt.Name, ', ') FROM Posts p LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id WHERE p.OwnerUserId = ca.UserId GROUP BY p.OwnerUserId) as PostTypesContributed,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = ca.UserId AND b.Class = 1) THEN 'GoldBadgeHolder'
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = ca.UserId AND b.Class = 2) THEN 'SilverBadgeHolder'
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = ca.UserId AND b.Class = 3) THEN 'BronzeBadgeHolder'
        ELSE 'NoBadge'
    END as BadgeStatus,
    COALESCE(
        (SELECT TOP 1 p.Title FROM Posts p WHERE p.OwnerUserId = ca.UserId AND p.PostTypeId = 1 AND p.Score > 50 ORDER BY p.Score DESC),
        (SELECT TOP 1 p.Title FROM Posts p WHERE p.OwnerUserId = ca.UserId AND p.PostTypeId = 2 AND p.Score > 10 ORDER BY p.Score DESC)
    ) as MostValuablePostTitle,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ca.UserId AND p.CreationDate > DATEADD(MONTH, -6, GETDATE())) as PostsInLast6Months,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = ca.UserId AND v.VoteTypeId = 2) as UpVotesGiven,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = ca.UserId AND v.VoteTypeId = 3) as DownVotesGiven,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = ca.UserId AND c.CreationDate > DATEADD(DAY, -30, GETDATE())) as CommentsInLast30Days,
    (SELECT COUNT(DISTINCT p.Id) FROM Posts p LEFT JOIN Comments c ON p.Id = c.PostId WHERE p.OwnerUserId = ca.UserId AND c.Id IS NOT NULL) as PostsWithComments,
    (SELECT COUNT(DISTINCT p.Id) FROM Posts p LEFT JOIN Votes v ON p.Id = v.PostId WHERE p.OwnerUserId = ca.UserId AND v.Id IS NOT NULL AND (v.VoteTypeId = 2 OR v.VoteTypeId = 3)) as PostsWithVotes,
    ISNULL((SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = ca.UserId), 0) as AverageScore,
    (SELECT TOP 1 p.CreationDate FROM Posts p WHERE p.OwnerUserId = ca.UserId ORDER BY p.CreationDate) as FirstPostDate,
    (SELECT TOP 1 p.CreationDate FROM Posts p WHERE p.OwnerUserId = ca.UserId ORDER BY p.CreationDate DESC) as LastPostDate,
    DATEDIFF(DAY, 
        (SELECT TOP 1 p.CreationDate FROM Posts p WHERE p.OwnerUserId = ca.UserId ORDER BY p.CreationDate),
        GETDATE()) as DaysSinceFirstPost,
    CASE 
        WHEN (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ca.UserId) > 0 THEN 
            DATEDIFF(DAY, 
                (SELECT TOP 1 p.CreationDate FROM Posts p WHERE p.OwnerUserId = ca.UserId ORDER BY p.CreationDate),
                (SELECT TOP 1 p.CreationDate FROM Posts p WHERE p.OwnerUserId = ca.UserId ORDER BY p.CreationDate DESC)
            )
        ELSE 0
    END as ActivePeriodDays
FROM ComplexUserAnalysis ca
FULL OUTER JOIN TagAnalysis ta ON ta.PopularityRank BETWEEN 1 AND 100
WHERE (ca.WeightedActivityScore > 100 OR ta.Count > 500)
    AND (ca.ReputationTier IN ('Master', 'Legendary') OR ta.PopularityCategory IN ('VeryPopular', 'Popular'))
ORDER BY ca.Reputation DESC, ta.Count DESC
OPTION (MAXDOP 1, RECOMPILE)