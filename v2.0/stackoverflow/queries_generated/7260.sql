-- {"query": "7260.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1614} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as AvgScore3,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            ELSE 'Low'
        END as ScoreCategory,
        COALESCE(p.Title, 'No Title') as SafeTitle,
        COALESCE(p.Tags, '') as SafeTags,
        CASE 
            WHEN p.CommentCount > 10 AND p.AnswerCount > 5 THEN 'Engaged'
            WHEN p.AnswerCount > 0 THEN 'Answered'
            ELSE 'Unanswered'
        END as EngagementLevel
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.CreationDate >= '2020-01-01'
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.ViewCount as UserProfileViews,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        SUM(p.Score) as TotalScore,
        AVG(p.Score) as AvgScore,
        MAX(p.CreationDate) as LastPostDate,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Veteran'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Experienced'
            WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Active'
            ELSE 'New'
        END as UserStatus
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2019-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.ViewCount
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Niche'
        END as Popularity,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as TagRank,
        LAG(t.Count) OVER (ORDER BY t.Count DESC) as PrevTagCount,
        LAG(t.TagName) OVER (ORDER BY t.Count DESC) as PrevTagName
    FROM Tags t
    WHERE t.Count > 10
),
CombinedAnalysis AS (
    SELECT 
        rp.Id as PostId,
        rp.OwnerUserId,
        rp.Score,
        rp.ScoreCategory,
        rp.UserPostRank,
        rp.AvgScore3,
        u.DisplayName,
        u.UserStatus,
        u.TotalScore as UserTotalScore,
        u.AvgScore as UserAvgScore,
        ta.TagName,
        ta.TagCount,
        ta.Popularity,
        CASE 
            WHEN rp.Score > u.AvgScore * 1.5 THEN 'AboveAvg'
            WHEN rp.Score < u.AvgScore * 0.5 THEN 'BelowAvg'
            ELSE 'Normal'
        END as ScoreVsUserAvg,
        CASE 
            WHEN rp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) * 1.2 THEN 'Exceptional'
            ELSE 'Regular'
        END as ScoreVsSiteAvg,
        CASE 
            WHEN rp.Tags IS NOT NULL AND rp.Tags != '' THEN 
                (SELECT COUNT(*) FROM unnest(string_to_array(rp.Tags, '><')) AS tag 
                 WHERE tag ILIKE '%' || COALESCE(ta.TagName, '') || '%')
            ELSE 0
        END as TagMatches,
        CASE 
            WHEN rp.CreationDate > (SELECT MAX(CreationDate) FROM Posts WHERE PostTypeId = 1) - INTERVAL '30 days' THEN 'Recent'
            ELSE 'Old'
        END as PostTimeliness
    FROM RankedPosts rp
    INNER JOIN UserActivity u ON rp.OwnerUserId = u.UserId
    LEFT JOIN TagAnalysis ta ON rp.Tags IS NOT NULL AND ta.TagName IN (
        SELECT unnest(string_to_array(rp.Tags, '><'))
        WHERE unnest(string_to_array(rp.Tags, '><')) ILIKE '%' || COALESCE(ta.TagName, '') || '%'
    )
    WHERE rp.UserPostRank <= 5
)
SELECT 
    ca.PostId,
    ca.OwnerUserId,
    ca.Score,
    ca.ScoreCategory,
    ca.UserPostRank,
    ca.AvgScore3,
    ca.DisplayName as OwnerName,
    ca.UserStatus,
    ca.UserTotalScore,
    ca.UserAvgScore,
    ca.TagName,
    ca.TagCount,
    ca.Popularity,
    ca.ScoreVsUserAvg,
    ca.ScoreVsSiteAvg,
    ca.TagMatches,
    ca.PostTimeliness,
    CASE 
        WHEN ca.TagMatches > 0 AND ca.ScoreVsUserAvg = 'AboveAvg' THEN 'HighValuePost'
        WHEN ca.ScoreVsSiteAvg = 'Exceptional' THEN 'SiteExceptional'
        ELSE 'RegularPost'
    END as PostClassification,
    DENSE_RANK() OVER (ORDER BY ca.Score DESC, ca.TagCount DESC) as GlobalRank,
    COUNT(*) OVER () as TotalPosts,
    RANK() OVER (PARTITION BY ca.UserStatus ORDER BY ca.Score DESC) as StatusRank,
    PERCENT_RANK() OVER (ORDER BY ca.Score) as ScorePercentile,
    NTH_VALUE(ca.DisplayName, 1) OVER (ORDER BY ca.Score DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as HighestScoringUser,
    CASE 
        WHEN ca.PostId IN (
            SELECT DISTINCT ph.PostId 
            FROM PostHistory ph 
            WHERE ph.PostHistoryTypeId IN (10, 12, 13) 
            AND ph.CreationDate >= '2021-01-01'
        ) THEN 'HasHistoryChanges'
        ELSE 'NoHistoryChanges'
    END as HistoryStatus,
    NULLIF(LENGTH(ca.SafeTitle) - LENGTH(REPLACE(ca.SafeTitle, ' ', '')) + 1, 0) as TitleWordCount,
    COALESCE(LENGTH(ca.SafeTags), 0) as TagsLength,
    CASE 
        WHEN ca.Score > 0 AND ca.AnswerCount > 0 THEN ca.Score::FLOAT / NULLIF(ca.AnswerCount, 0)
        ELSE 0
    END as ScorePerAnswer
FROM CombinedAnalysis ca
WHERE ca.Score > 0 
    AND ca.TagCount > 50
    AND ca.UserTotalScore > 1000
    AND ca.PostTimeliness IN ('Recent', 'Old')
    AND (ca.Score > 10 OR ca.TagCount > 100)
ORDER BY ca.Score DESC, ca.TagCount DESC, ca.UserTotalScore DESC
LIMIT 500;