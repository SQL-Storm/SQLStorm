-- {"query": "7050.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2679}
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT v.Id) as VoteCount,
        COALESCE(SUM(p.Score), 0) as TotalPostScore,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews,
        MAX(p.CreationDate) as LatestPostDate,
        MAX(c.CreationDate) as LatestCommentDate,
        MAX(b.Date) as LatestBadgeDate,
        MAX(v.CreationDate) as LatestVoteDate,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 AND COUNT(DISTINCT c.Id) > 0 THEN 'Active'
            WHEN COUNT(DISTINCT p.Id) > 0 OR COUNT(DISTINCT c.Id) > 0 THEN 'Partially Active'
            ELSE 'Inactive'
        END as ActivityStatus,
        ROW_NUMBER() OVER (PARTITION BY u.Reputation ORDER BY COUNT(DISTINCT p.Id) DESC, u.Views DESC) as RepRank,
        ROW_NUMBER() OVER (PARTITION BY u.Views ORDER BY COUNT(DISTINCT p.Id) DESC, u.Reputation DESC) as ViewRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
    WHERE u.CreationDate >= TIMESTAMP '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate, u.LastAccessDate
),
PostAnalysis AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Body,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.LastEditDate,
        p.AcceptedAnswerId,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Q+AcceptedAnswer'
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostCategory,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'High'
            WHEN p.ViewCount > 100 THEN 'Medium'
            WHEN p.ViewCount > 0 THEN 'Low'
            ELSE 'None'
        END as ViewCategory,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 10 THEN 'Medium'
            WHEN p.Score > 0 THEN 'Low'
            ELSE 'Negative'
        END as ScoreCategory,
        CASE 
            WHEN p.Tags IS NOT NULL AND CHAR_LENGTH(p.Tags) > 2 THEN 
                REPLACE(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags)-2), '><', ', ')
            ELSE NULL 
        END as TagList,
        EXTRACT(DAY FROM (p.LastActivityDate - p.CreationDate)) as DaysSinceCreation,
        EXTRACT(DAY FROM (TIMESTAMP '2024-10-01 12:34:56' - p.CreationDate)) as DaysActive,
        CASE 
            WHEN p.LastEditDate IS NOT NULL 
                AND EXTRACT(DAY FROM (p.LastEditDate - p.CreationDate)) > 30 
                THEN 'EditedAfter30Days'
            WHEN p.LastEditDate IS NOT NULL 
                AND EXTRACT(DAY FROM (p.LastEditDate - p.CreationDate)) > 7 
                THEN 'EditedAfter7Days'
            ELSE 'NotEditedRecently'
        END as EditStatus,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) as UserPostRank,
        RANK() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) as GlobalScoreRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC, p.Score DESC) as GlobalViewRank,
        (SELECT u.Reputation FROM Users u WHERE u.Id = p.OwnerUserId) as OwnerReputation
    FROM Posts p
    WHERE p.CreationDate >= TIMESTAMP '2020-01-01'
    AND p.PostTypeId IN (1, 2)
),
ComplexJoinResults AS (
    SELECT 
        pa.Id as PostId,
        pa.PostTypeId,
        pa.ParentId,
        pa.OwnerUserId,
        pa.Score,
        pa.ViewCount,
        pa.Title,
        pa.Body,
        pa.Tags,
        pa.AnswerCount,
        pa.CommentCount,
        pa.FavoriteCount,
        pa.CreationDate,
        pa.LastActivityDate,
        pa.LastEditDate,
        pa.AcceptedAnswerId,
        pa.PostCategory,
        pa.ViewCategory,
        pa.ScoreCategory,
        pa.TagList,
        pa.DaysSinceCreation,
        pa.DaysActive,
        pa.EditStatus,
        pa.UserPostRank,
        pa.GlobalScoreRank,
        pa.GlobalViewRank,
        pa.OwnerReputation,
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM PostHistory ph 
                WHERE ph.PostId = pa.Id AND ph.PostHistoryTypeId IN (1, 2, 3) 
                AND ph.CreationDate >= TIMESTAMP '2020-06-01'
            ) THEN 'HasRecentHistory'
            ELSE 'NoRecentHistory'
        END as HistoryStatus,
        AVG(pa.Score) OVER (PARTITION BY pa.OwnerUserId ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) as UserMovingAverageScore,
        CASE 
            WHEN pa.Score > 50 AND pa.ViewCount > 500 AND pa.AnswerCount > 5 
                THEN 'HighImpact'
            WHEN pa.Score > 20 AND pa.ViewCount > 200 
                THEN 'MediumImpact'
            ELSE 'LowImpact'
        END as ImpactCategory,
        COALESCE(pa.Title, 'No Title') || ' - ' || 
        COALESCE(SUBSTRING(pa.Body FROM 1 FOR 50), 'No Body') || '...' as TitleBodySummary,
        CASE 
            WHEN pa.Tags IS NOT NULL AND pa.Tags != '' 
                THEN 'HasTags'
            WHEN pa.Tags IS NULL OR pa.Tags = ''
                THEN 'NoTags'
            ELSE 'UnknownTagStatus'
        END as TagStatus,
        ROUND(
            CASE 
                WHEN pa.ViewCount > 0 THEN (pa.Score * 100.0 / pa.ViewCount)
                ELSE 0 
            END, 2
        ) as ScorePerViewRatio,
        (SELECT COUNT(b.Id) FROM Badges b WHERE b.UserId = pa.OwnerUserId) as OwnerBadgeCount
    FROM PostAnalysis pa
),
FinalAggregation AS (
    SELECT 
        COUNT(*) as TotalPosts,
        COUNT(CASE WHEN cr.PostCategory = 'Question' THEN 1 END) as QuestionCount,
        COUNT(CASE WHEN cr.PostCategory = 'Answer' THEN 1 END) as AnswerCount,
        COUNT(CASE WHEN cr.PostCategory = 'Q+AcceptedAnswer' THEN 1 END) as QuestionWithAcceptedAnswer,
        AVG(cr.Score) as AvgScore,
        AVG(cr.ViewCount) as AvgViews,
        AVG(cr.AnswerCount) as AvgAnswers,
        AVG(cr.CommentCount) as AvgComments,
        SUM(cr.Score) as TotalScore,
        SUM(cr.ViewCount) as TotalViews,
        COUNT(DISTINCT cr.OwnerUserId) as DistinctOwners,
        MAX(cr.OwnerReputation) as MaxReputation,
        MIN(cr.OwnerReputation) as MinReputation,
        AVG(cr.OwnerReputation) as AvgOwnerReputation,
        COUNT(DISTINCT CASE WHEN cr.EditStatus = 'EditedAfter30Days' THEN cr.PostId END) as EditedAfter30Days,
        COUNT(DISTINCT CASE WHEN cr.EditStatus = 'EditedAfter7Days' THEN cr.PostId END) as EditedAfter7Days,
        COUNT(DISTINCT CASE WHEN cr.EditStatus = 'NotEditedRecently' THEN cr.PostId END) as NotEditedRecently,
        COUNT(DISTINCT CASE WHEN cr.ImpactCategory = 'HighImpact' THEN cr.PostId END) as HighImpactPosts,
        COUNT(DISTINCT CASE WHEN cr.ImpactCategory = 'MediumImpact' THEN cr.PostId END) as MediumImpactPosts,
        COUNT(DISTINCT CASE WHEN cr.ImpactCategory = 'LowImpact' THEN cr.PostId END) as LowImpactPosts,
        COUNT(DISTINCT CASE WHEN cr.ScoreCategory = 'High' THEN cr.PostId END) as HighScorePosts,
        COUNT(DISTINCT CASE WHEN cr.ScoreCategory = 'Medium' THEN cr.PostId END) as MediumScorePosts,
        COUNT(DISTINCT CASE WHEN cr.ScoreCategory = 'Low' THEN cr.PostId END) as LowScorePosts,
        COUNT(DISTINCT CASE WHEN cr.TagStatus = 'HasTags' THEN cr.PostId END) as PostsWithTags,
        COUNT(DISTINCT CASE WHEN cr.TagStatus = 'NoTags' THEN cr.PostId END) as PostsWithoutTags,
        COUNT(DISTINCT CASE WHEN cr.DaysSinceCreation > 365 THEN cr.PostId END) as LongevityPosts,
        COUNT(DISTINCT CASE WHEN cr.DaysSinceCreation <= 30 THEN cr.PostId END) as RecentPosts,
        AVG(CASE WHEN cr.ScorePerViewRatio IS NOT NULL THEN cr.ScorePerViewRatio ELSE 0 END) as AvgScorePerViewRatio,
        (SELECT COUNT(DISTINCT TagList) FROM ComplexJoinResults WHERE TagList IS NOT NULL) as DistinctTagLists,
        COUNT(DISTINCT CASE WHEN cr.GlobalScoreRank <= 100 THEN cr.PostId END) as Top100ScoredPosts,
        COUNT(DISTINCT CASE WHEN cr.GlobalViewRank <= 100 THEN cr.PostId END) as Top100ViewedPosts
    FROM ComplexJoinResults cr
    WHERE cr.OwnerReputation > 1000
)
SELECT 
    'Performance Benchmark Query Result' as QueryName,
    fa.TotalPosts,
    fa.QuestionCount,
    fa.AnswerCount,
    fa.QuestionWithAcceptedAnswer,
    ROUND(fa.AvgScore, 2) as AvgScore,
    ROUND(fa.AvgViews, 2) as AvgViews,
    ROUND(fa.AvgAnswers, 2) as AvgAnswers,
    ROUND(fa.AvgComments, 2) as AvgComments,
    fa.TotalScore,
    fa.TotalViews,
    fa.DistinctOwners,
    fa.MaxReputation,
    fa.MinReputation,
    ROUND(fa.AvgOwnerReputation, 2) as AvgOwnerReputation,
    fa.EditedAfter30Days,
    fa.EditedAfter7Days,
    fa.NotEditedRecently,
    fa.HighImpactPosts,
    fa.MediumImpactPosts,
    fa.LowImpactPosts,
    fa.HighScorePosts,
    fa.MediumScorePosts,
    fa.LowScorePosts,
    fa.PostsWithTags,
    fa.PostsWithoutTags,
    fa.LongevityPosts,
    fa.RecentPosts,
    ROUND(fa.AvgScorePerViewRatio, 4) as AvgScorePerViewRatio,
    fa.DistinctTagLists,
    fa.Top100ScoredPosts,
    fa.Top100ViewedPosts
FROM FinalAggregation fa
WHERE fa.TotalPosts > 0;