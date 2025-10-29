-- {"query": "7528.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1815} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        DATEDIFF('DAY', u.CreationDate, CURRENT_TIMESTAMP) as AccountAgeDays,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Gold'
            WHEN u.Reputation > 1000 THEN 'Silver'
            ELSE 'Bronze'
        END as ReputationTier
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
TopPosts AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as TypeScoreRank,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId) as AvgScoreByType,
        PERCENT_RANK() OVER (ORDER BY p.Score) as ScorePercentile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
PostDetailAnalysis AS (
    SELECT 
        tp.PostId,
        tp.Title,
        tp.Score,
        tp.ViewCount,
        tp.CreationDate,
        tp.OwnerUserId,
        tp.PostTypeId,
        tp.Tags,
        tp.ScoreRank,
        tp.TypeScoreRank,
        tp.AvgScoreByType,
        tp.ScorePercentile,
        DATEDIFF('DAY', tp.CreationDate, CURRENT_TIMESTAMP) as DaysSinceCreation,
        CASE 
            WHEN tp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = tp.PostTypeId) THEN 'AboveAvg'
            ELSE 'BelowAvg'
        END as ScoreStatus,
        LAG(tp.Score) OVER (ORDER BY tp.Score DESC) as PreviousScore,
        LAG(tp.ViewCount) OVER (ORDER BY tp.Score DESC) as PreviousViews,
        COALESCE(tp.Tags, '') as CleanTags,
        CASE 
            WHEN tp.Tags IS NOT NULL AND LENGTH(tp.Tags) > 0 THEN ARRAY_LENGTH(string_to_array(substring(tp.Tags, 2, length(tp.Tags)-2), '><'), 1)
            ELSE 0
        END as TagCount
    FROM TopPosts tp
),
CommunityEngagement AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId IN (2, 3) THEN v.Id END) as VoteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) as FavoriteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId IN (8, 9) THEN v.Id END) as BountyCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) as UpVotedCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) as DownVotedCount,
        AVG(v.CreationDate) as AvgVoteDate
    FROM Posts p
    INNER JOIN Votes v ON p.Id = v.PostId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > (SELECT AVG(Count) FROM Tags) THEN 'Popular'
            WHEN t.Count > (SELECT AVG(Count)/2 FROM Tags) THEN 'Moderate'
            ELSE 'Sparse'
        END as PopularityLevel,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) as PopularityRank
    FROM Tags t
    WHERE t.TagName IS NOT NULL
)

SELECT 
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.Views,
    uas.UpVotes,
    uas.DownVotes,
    uas.TotalPosts,
    uas.Questions,
    uas.Answers,
    uas.Comments,
    uas.Badges,
    uas.LastPostDate,
    uas.LastCommentDate,
    uas.AccountAgeDays,
    uas.ReputationTier,
    
    pd.Title,
    pd.Score,
    pd.ViewCount,
    pd.CreationDate,
    pd.PostTypeId,
    pd.ScoreRank,
    pd.TypeScoreRank,
    pd.AvgScoreByType,
    pd.ScorePercentile,
    pd.DaysSinceCreation,
    pd.ScoreStatus,
    pd.PreviousScore,
    pd.PreviousViews,
    pd.CleanTags,
    pd.TagCount,
    
    coalesce(ce.VoteCount, 0) as TotalVotes,
    coalesce(ce.FavoriteCount, 0) as TotalFavorites,
    coalesce(ce.BountyCount, 0) as TotalBounties,
    coalesce(ce.UpVotedCount, 0) as UpVotesReceived,
    coalesce(ce.DownVotedCount, 0) as DownVotesReceived,
    
    ta.TagName,
    ta.TagCount as TagFrequency,
    ta.PopularityLevel,
    ta.PopularityRank,
    
    CASE 
        WHEN pd.ScoreRank <= 100 THEN 'Top100'
        WHEN pd.ScoreRank <= 1000 THEN 'Top1000'
        ELSE 'BelowTop1000'
    END as PostPerformanceCategory,
    
    CASE 
        WHEN uas.TotalPosts > 100 THEN 'HighActivity'
        WHEN uas.TotalPosts > 50 THEN 'MediumActivity'
        ELSE 'LowActivity'
    END as UserActivityLevel,
    
    CASE 
        WHEN uas.AccountAgeDays > 365 AND uas.Reputation > 5000 THEN 'VeteranActive'
        WHEN uas.AccountAgeDays > 365 THEN 'Veteran'
        WHEN uas.Reputation > 5000 THEN 'Active'
        ELSE 'New'
    END as UserStatus,
    
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = uas.UserId AND p2.PostTypeId = 1 AND p2.CreationDate >= DATEADD('MONTH', -6, CURRENT_TIMESTAMP)) as RecentQuestions,
    (SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = uas.UserId AND p3.PostTypeId = 2 AND p3.CreationDate >= DATEADD('MONTH', -6, CURRENT_TIMESTAMP)) as RecentAnswers,
    
    CASE 
        WHEN pd.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) AND uas.UpVotes > 50 THEN 'HighQualityContributor'
        WHEN pd.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'GoodContributor'
        WHEN uas.UpVotes > 10 THEN 'ActiveContributor'
        ELSE 'RegularUser'
    END as ContributionRating
    
FROM UserActivityStats uas
LEFT JOIN PostDetailAnalysis pd ON uas.UserId = pd.OwnerUserId
LEFT JOIN CommunityEngagement ce ON uas.UserId = ce.OwnerUserId
LEFT JOIN TagAnalysis ta ON ta.TagName IN (
    SELECT TRIM(UNNEST(string_to_array(substring(pd.CleanTags, 2, length(pd.CleanTags)-2), '><')))
    WHERE pd.CleanTags IS NOT NULL AND LENGTH(pd.CleanTags) > 0
)
WHERE uas.UserId IS NOT NULL
    AND (pd.Score IS NOT NULL OR pd.ScoreRank IS NOT NULL)
    AND (uas.Reputation > 50 OR uas.TotalPosts > 0)
ORDER BY uas.Reputation DESC, pd.Score DESC, uas.TotalPosts DESC
LIMIT 5000;