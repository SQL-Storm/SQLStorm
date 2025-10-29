-- {"query": "7115.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3907} 
WITH PostStats AS (
    SELECT 
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.Body,
        u.DisplayName as OwnerDisplayName,
        u.Reputation,
        u.Views as UserViews,
        u.UpVotes,
        u.DownVotes,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) as EngagementCount,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        NTILE(10) OVER (ORDER BY p.ViewCount DESC) as ViewDecile,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgUserScore,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as TotalUserPosts
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
),
UserEngagement AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as TotalPosts,
        SUM(p.ViewCount) as TotalViews,
        SUM(p.Score) as TotalScore,
        AVG(p.Score) as AvgScore,
        MAX(p.CreationDate) as LastPostDate,
        MIN(p.CreationDate) as FirstPostDate,
        DATEDIFF(day, MIN(p.CreationDate), MAX(p.CreationDate)) as ActiveDays,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Veteran'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Experienced'
            WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Active'
            ELSE 'New'
        END as UserStatus,
        CASE 
            WHEN u.Reputation > 10000 THEN 'High'
            WHEN u.Reputation > 1000 THEN 'Medium'
            WHEN u.Reputation > 100 THEN 'Low'
            ELSE 'VeryLow'
        END as ReputationLevel
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
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
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Rare'
        END as TagPopularity,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as TagRank,
        RANK() OVER (PARTITION BY CASE WHEN t.Count > 1000 THEN 'Popular' ELSE 'Other' END ORDER BY t.Count DESC) as PopularityRank,
        LAG(t.Count, 1) OVER (ORDER BY t.Count DESC) as PreviousCount,
        NTILE(5) OVER (ORDER BY t.Count DESC) as CountQuintile
    FROM Tags t
),
PostHistorySummary AS (
    SELECT 
        ph.PostId,
        COUNT(*) as EditCount,
        COUNT(DISTINCT ph.UserId) as EditorCount,
        MAX(ph.CreationDate) as LastEditDate,
        MIN(ph.CreationDate) as FirstEditDate,
        STRING_AGG(DISTINCT ph.PostHistoryTypeId, ', ') as EditTypes,
        AVG(LENGTH(ph.Text)) as AvgEditLength,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (1, 2, 3) THEN 1 ELSE 0 END) as InitialEditCount
    FROM PostHistory ph
    WHERE ph.PostId IS NOT NULL
    GROUP BY ph.PostId
),
ComplexPosts AS (
    SELECT 
        ps.PostId,
        ps.PostTypeId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.CreationDate,
        ps.OwnerUserId,
        ps.OwnerDisplayName,
        ps.Reputation,
        ps.UserViews,
        ps.UpVotes,
        ps.DownVotes,
        ps.EngagementCount,
        ps.PostType,
        ps.UserPostRank,
        ps.ScoreRank,
        ps.ViewDecile,
        ps.PreviousScore,
        ps.NextScore,
        ps.AvgUserScore,
        ps.TotalUserPosts,
        CASE 
            WHEN ps.Score > 50 THEN 'High'
            WHEN ps.Score > 20 THEN 'Medium'
            WHEN ps.Score > 5 THEN 'Low'
            ELSE 'VeryLow'
        END as ScoreCategory,
        CASE 
            WHEN ps.ViewCount > 1000 THEN 'Viral'
            WHEN ps.ViewCount > 100 THEN 'Popular'
            WHEN ps.ViewCount > 10 THEN 'Noticeable'
            ELSE 'Obscure'
        END as Popularity,
        CASE 
            WHEN ps.AnswerCount > 10 THEN 'HighlyAnswered'
            WHEN ps.AnswerCount > 5 THEN 'ModeratelyAnswered'
            WHEN ps.AnswerCount > 0 THEN 'Answered'
            ELSE 'Unanswered'
        END as AnswerStatus,
        CASE 
            WHEN ps.CommentCount > 20 THEN 'HighlyCommented'
            WHEN ps.CommentCount > 10 THEN 'ModeratelyCommented'
            WHEN ps.CommentCount > 5 THEN 'Commented'
            ELSE 'Uncommented'
        END as CommentStatus,
        CASE 
            WHEN ps.FavoriteCount > 50 THEN 'HighlyFavorited'
            WHEN ps.FavoriteCount > 10 THEN 'ModeratelyFavorited'
            WHEN ps.FavoriteCount > 0 THEN 'Favorited'
            ELSE 'NotFavorited'
        END as FavoriteStatus,
        ps.EngagementCount - COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.PostId = ps.PostId), 0) as NetEngagement,
        COALESCE(pht.EditCount, 0) as TotalEdits,
        COALESCE(pht.EditorCount, 0) as UniqueEditors,
        COALESCE(pht.AvgEditLength, 0) as AvgEditLength,
        CASE 
            WHEN ps.Score > ps.AvgUserScore THEN 'AboveAvg'
            WHEN ps.Score < ps.AvgUserScore THEN 'BelowAvg'
            ELSE 'AtAvg'
        END as PerformanceVsUserAvg,
        CASE 
            WHEN ps.Score > (SELECT AVG(Score) FROM Posts) THEN 'AboveOverall'
            WHEN ps.Score < (SELECT AVG(Score) FROM Posts) THEN 'BelowOverall'
            ELSE 'AtOverall'
        END as PerformanceVsOverall,
        CASE 
            WHEN ps.ScoreRank <= 100 THEN 'Top100'
            WHEN ps.ScoreRank <= 1000 THEN 'Top1000'
            WHEN ps.ScoreRank <= 10000 THEN 'Top10000'
            ELSE 'Below10000'
        END as RankCategory,
        CASE 
            WHEN ps.ViewCount > 0 AND ps.Score > 0 THEN 
                CAST(ps.ViewCount AS FLOAT) / CAST(ps.Score AS FLOAT)
            ELSE 0 
        END as ViewToScoreRatio,
        CASE 
            WHEN ps.ViewDecile = 1 THEN 'TopDecile'
            WHEN ps.ViewDecile <= 3 THEN 'HighDecile'
            WHEN ps.ViewDecile <= 7 THEN 'MidDecile'
            ELSE 'LowDecile'
        END as ViewDecileCategory,
        COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = ps.PostId AND v.VoteTypeId IN (2, 3)), 0) as VoteCount,
        COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = ps.OwnerUserId AND b.Name LIKE '%Popular%'), 0) as PopularBadgeCount,
        (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = ps.PostId AND p2.PostTypeId = 2) as AnswerCountForQuestion,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = ps.PostId) as CommentCountForPost
    FROM PostStats ps
    LEFT JOIN PostHistorySummary pht ON ps.PostId = pht.PostId
),
TopTagsFromPosts AS (
    SELECT 
        t.TagName,
        t.Count,
        STRING_AGG(DISTINCT p.Title, '; ') as SampleTitles,
        COUNT(DISTINCT p.Id) as PostCount,
        AVG(p.Score) as AvgScore,
        AVG(p.ViewCount) as AvgViews,
        STRING_AGG(DISTINCT u.DisplayName, ', ') as TopUsers
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%' + t.TagName + '%'
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE t.Count > 1000
    GROUP BY t.TagName, t.Count
),
FinalAnalysis AS (
    SELECT 
        cp.*,
        ta.TagName as RelatedTag,
        ta.Count as TagCount,
        ta.SampleTitles,
        ta.PostCount as TagPostCount,
        ta.AvgScore as TagAvgScore,
        ta.AvgViews as TagAvgViews,
        ta.TopUsers,
        CASE 
            WHEN cp.ViewToScoreRatio > 100 THEN 'HighRatio'
            WHEN cp.ViewToScoreRatio > 50 THEN 'MediumRatio'
            WHEN cp.ViewToScoreRatio > 10 THEN 'LowRatio'
            ELSE 'VeryLowRatio'
        END as RatioCategory,
        CASE 
            WHEN cp.UserPostRank = 1 THEN 'MostRecentPost'
            ELSE 'RegularPost'
        END as PostRankStatus,
        CASE 
            WHEN cp.TotalEdits / NULLIF(cp.TotalUserPosts, 0) > 2 THEN 'FrequentEditor'
            WHEN cp.TotalEdits / NULLIF(cp.TotalUserPosts, 0) > 1 THEN 'OccasionalEditor'
            ELSE 'RareEditor'
        END as EditFrequency,
        CASE 
            WHEN cp.AnswerStatus = 'HighlyAnswered' AND cp.CommentStatus = 'HighlyCommented' THEN 'HighlyEngaged'
            WHEN cp.AnswerStatus = 'Unanswered' AND cp.CommentStatus = 'Uncommented' THEN 'Silent'
            ELSE 'Mixed'
        END as EngagementQuality,
        CASE 
            WHEN cp.EngagementCount > 50 THEN 'HighEngagement'
            WHEN cp.EngagementCount > 20 THEN 'MediumEngagement'
            WHEN cp.EngagementCount > 5 THEN 'LowEngagement'
            ELSE 'VeryLowEngagement'
        END as EngagementLevel,
        COALESCE(ue.TotalPosts, 0) as UserTotalPosts,
        COALESCE(ue.TotalViews, 0) as UserTotalViews,
        COALESCE(ue.TotalScore, 0) as UserTotalScore,
        COALESCE(ue.AvgScore, 0) as UserAvgScore,
        COALESCE(ue.UserStatus, 'Unknown') as UserStatus,
        COALESCE(ue.ReputationLevel, 'Unknown') as ReputationLevel,
        CASE 
            WHEN cp.TotalEdits > 0 AND cp.EditCount > 0 THEN 'Edited'
            ELSE 'Unedited'
        END as EditStatus,
        CASE 
            WHEN cp.NetEngagement > 100 THEN 'ExtremelyEngaged'
            WHEN cp.NetEngagement > 20 THEN 'VeryEngaged'
            WHEN cp.NetEngagement > 5 THEN 'ModeratelyEngaged'
            ELSE 'SlightlyEngaged'
        END as NetEngagementLevel,
        CASE 
            WHEN cp.FavoriteCount > 0 AND cp.FavoriteStatus = 'HighlyFavorited' THEN 'HighlyFavoritedPost'
            WHEN cp.FavoriteCount > 0 THEN 'FavoritedPost'
            ELSE 'UnfavoritedPost'
        END as FavoriteCategory,
        COALESCE((SELECT MIN(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = cp.PostId AND ph.PostHistoryTypeId IN (1, 2, 3)), cp.CreationDate) as TrueCreationDate,
        DATEDIFF(day, cp.CreationDate, COALESCE((SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = cp.PostId AND ph.PostHistoryTypeId IN (10, 11, 12, 13)), cp.CreationDate)) as PostDuration,
        CASE 
            WHEN cp.ViewCount > 0 AND cp.Score > 0 THEN 
                CAST((cp.ViewCount * 100.0) / NULLIF(cp.Score, 0) AS DECIMAL(10,2))
            ELSE 0 
        END as EfficiencyRatio,
        CASE 
            WHEN cp.TotalUserPosts > 100 THEN 'HighVolume'
            WHEN cp.TotalUserPosts > 50 THEN 'MediumVolume'
            WHEN cp.TotalUserPosts > 10 THEN 'LowVolume'
            ELSE 'VeryLowVolume'
        END as PostVolume,
        CASE 
            WHEN cp.AvgUserScore > 100 THEN 'HighScoring'
            WHEN cp.AvgUserScore > 50 THEN 'MediumScoring'
            WHEN cp.AvgUserScore > 10 THEN 'LowScoring'
            ELSE 'VeryLowScoring'
        END as UserScoreLevel,
        CASE 
            WHEN cp.ScoreRank <= 10 THEN 'HighRank'
            WHEN cp.ScoreRank <= 100 THEN 'MidRank'
            WHEN cp.ScoreRank <= 1000 THEN 'LowRank'
            ELSE 'VeryLowRank'
        END as RankLevel,
        CASE 
            WHEN cp.ViewCount > (SELECT AVG(ViewCount) FROM Posts) THEN 'AboveAvgViews'
            WHEN cp.ViewCount < (SELECT AVG(ViewCount) FROM Posts) THEN 'BelowAvgViews'
            ELSE 'AvgViews'
        END as ViewLevel,
        COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = cp.PostId AND v.VoteTypeId = 2), 0) as Upvotes,
        COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = cp.PostId AND v.VoteTypeId = 3), 0) as Downvotes
    FROM ComplexPosts cp
    LEFT JOIN TopTagsFromPosts ta ON cp.Tags LIKE '%' + ta.TagName + '%'
    LEFT JOIN UserEngagement ue ON cp.OwnerUserId = ue.UserId
)
SELECT 
    fa.PostId,
    fa.PostTypeId,
    fa.OwnerUserId,
    fa.OwnerDisplayName,
    fa.Reputation,
    fa.Score,
    fa.ViewCount,
    fa.AnswerCount,
    fa.CommentCount,
    fa.FavoriteCount,
    fa.CreationDate,
    fa.PostType,
    fa.ScoreCategory,
    fa.Popularity,
    fa.AnswerStatus,
    fa.CommentStatus,
    fa.FavoriteStatus,
    fa.UserPostRank,
    fa.ScoreRank,
    fa.ViewDecile,
    fa.ViewToScoreRatio,
    fa.RatioCategory,
    fa.UserStatus,
    fa.ReputationLevel,
    fa.EditStatus,
    fa.NetEngagementLevel,
    fa.FavoriteCategory,
    fa.EfficiencyRatio,
    fa.PostVolume,
    fa.UserScoreLevel,
    fa.RankLevel,
    fa.ViewLevel,
    fa.Upvotes,
    fa.Downvotes,
    fa.RelatedTag,
    fa.TagCount,
    fa.SampleTitles,
    fa.TagPostCount,
    fa.TagAvgScore,
    fa.TagAvgViews,
    fa.TopUsers
FROM FinalAnalysis fa
WHERE fa.PostId IS NOT NULL
    AND fa.Score IS NOT NULL
    AND fa.ViewCount IS NOT NULL
    AND fa.UserPostRank IS NOT NULL
    AND (fa.RelatedTag IS NOT NULL OR fa.RelatedTag IS NULL)
    AND NOT EXISTS (
        SELECT 1 
        FROM Posts p 
        WHERE p.Id = fa.PostId 
        AND (p.PostTypeId IS NULL OR p.PostTypeId = 0)
    )
    AND (
        CASE 
            WHEN fa.Score > 50 THEN 1 
            ELSE 0 
        END 
        + 
        CASE 
            WHEN fa.ViewCount > 1000 THEN 1 
            ELSE 0 
        END 
        + 
        CASE 
            WHEN fa.AnswerCount > 5 THEN 1 
            ELSE 0 
        END 
        + 
        CASE 
            WHEN fa.CommentCount > 10 THEN 1 
            ELSE 0 
        END 
        + 
        CASE 
            WHEN fa.FavoriteCount > 5 THEN 1 
            ELSE 0 
        END
    ) >= 3
    AND fa.TotalEdits IS NOT NULL
    AND fa.TotalEdits >= 0
    AND (
        CASE 
            WHEN fa.NetEngagementLevel IN ('HighlyEngaged', 'VeryEngaged') THEN 1
            ELSE 0 
        END
        +
        CASE 
            WHEN fa.FavoriteCategory IN ('HighlyFavoritedPost', 'FavoritedPost') THEN 1
            ELSE 0 
        END
        +
        CASE 
            WHEN fa.EditStatus = 'Edited' THEN 1
            ELSE 0 
        END
        +
        CASE 
            WHEN fa.UserStatus IN ('Veteran', 'Experienced') THEN 1
            ELSE 0 
        END
    ) >= 2
ORDER BY 
    fa.Score DESC,
    fa.ViewCount DESC,
    fa.CreationDate DESC,
    fa.UserPostRank ASC,
    fa.ViewDecile ASC
LIMIT 1000 OFFSET 0;