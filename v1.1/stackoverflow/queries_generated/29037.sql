-- {"query": "29037.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1691} 
WITH RankedPosts AS (
    SELECT 
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as UserAvgScore,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            ELSE 'Low'
        END as ScoreCategory,
        COALESCE(p.Title, 'No Title') as CleanTitle,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN ARRAY_LENGTH(string_to_array(trim(trim(p.Tags, '<>'), '><'), '><'), 1)
            ELSE 0
        END as TagCount
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        AVG(p.Score) as AvgScore,
        MAX(p.CreationDate) as LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
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
            ELSE 'Rare'
        END as PopularityLevel,
        RANK() OVER (ORDER BY t.Count DESC) as PopularityRank
    FROM Tags t
    WHERE t.Count > 50
),
PostHistorySummary AS (
    SELECT 
        ph.PostId,
        COUNT(*) as HistoryCount,
        COUNT(DISTINCT ph.PostHistoryTypeId) as UniqueActionTypes,
        MAX(ph.CreationDate) as LastActionDate,
        STRING_AGG(ph.Comment, ' | ') as AllComments,
        STRING_AGG(CAST(ph.PostHistoryTypeId AS VARCHAR), ', ') as ActionTypes
    FROM PostHistory ph
    WHERE ph.CreationDate >= '2023-01-01'
    GROUP BY ph.PostId
)
SELECT 
    'Performance Benchmark Report' as ReportTitle,
    COUNT(*) as TotalRecords,
    COUNT(DISTINCT rp.PostId) as DistinctPosts,
    COUNT(DISTINCT uas.UserId) as ActiveUsers,
    COUNT(DISTINCT ta.TagName) as PopularTags,
    COUNT(DISTINCT phs.PostId) as PostsWithHistory,
    COUNT(*) FILTER (WHERE rp.ScoreCategory = 'High') as HighScorePosts,
    COUNT(*) FILTER (WHERE rp.UserPostRank = 1) as LatestPosts,
    AVG(uas.TotalScore) as AvgTotalScore,
    AVG(rp.ViewCount) as AvgViewCount,
    AVG(rp.AnswerCount) as AvgAnswerCount,
    AVG(rp.CommentCount) as AvgCommentCount,
    (
        SELECT STRING_AGG(
            CONCAT('User:', uas.UserId, '|Reputation:', uas.Reputation, '|Posts:', uas.TotalPosts),
            '; '
        )
        FROM UserActivityStats uas
        WHERE uas.TotalPosts > 100
        LIMIT 10
    ) as HighActivityUsers,
    (
        SELECT STRING_AGG(
            CONCAT('Tag:', ta.TagName, '|Popularity:', ta.PopularityLevel, '|Count:', ta.TagCount),
            '; '
        )
        FROM TagAnalysis ta
        WHERE ta.PopularityLevel = 'Popular'
        LIMIT 5
    ) as PopularTagsList,
    (
        SELECT STRING_AGG(
            CONCAT('Post:', phs.PostId, '|Actions:', phs.HistoryCount, '|Last:', phs.LastActionDate),
            '; '
        )
        FROM PostHistorySummary phs
        WHERE phs.HistoryCount > 50
        LIMIT 3
    ) as HighActivityPosts,
    (
        SELECT COUNT(DISTINCT ph.PostId)
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13)
        AND ph.CreationDate >= '2023-06-01'
    ) as RecentVotingActions,
    (
        SELECT AVG(rp.UserAvgScore)
        FROM RankedPosts rp
        WHERE rp.UserPostRank <= 5
    ) as AvgScoreOfTop5Posts,
    (
        SELECT STRING_AGG(
            CONCAT('Post:', rp.PostId, '|Title:', rp.CleanTitle, '|Score:', rp.Score),
            '; '
        )
        FROM RankedPosts rp
        WHERE rp.Score > 1000
        AND rp.ScoreCategory = 'High'
        LIMIT 5
    ) as HighScoringPosts,
    (
        SELECT COUNT(DISTINCT ph.PostId)
        FROM PostHistory ph
        JOIN Users u ON ph.UserId = u.Id
        WHERE u.Reputation > 10000
        AND ph.CreationDate >= '2023-01-01'
    ) as HighRepUserActions,
    (
        SELECT COUNT(DISTINCT p.Id)
        FROM Posts p
        JOIN Users u ON p.OwnerUserId = u.Id
        WHERE u.Reputation > 10000
        AND p.PostTypeId = 1
        AND p.CreationDate >= '2023-01-01'
    ) as HighRepUserQuestions,
    (
        SELECT 
            COUNT(*) - 
            COUNT(CASE WHEN rp.PrevScore IS NULL THEN 1 END) as
        FROM RankedPosts rp
        WHERE rp.PostTypeId = 1
    ) as PostsWithScoreHistory,
    (
        SELECT COUNT(DISTINCT u.Id)
        FROM Users u
        JOIN PostHistory ph ON u.Id = ph.UserId
        WHERE ph.PostHistoryTypeId IN (1, 2, 3)
        AND ph.CreationDate >= '2023-01-01'
    ) as UsersWithPostHistory,
    (
        SELECT 
            STRING_AGG(CONCAT('User:', uas.UserId, '|AvgScore:', ROUND(uas.AvgScore, 2)), '; ')
        FROM UserActivityStats uas
        WHERE uas.AvgScore > 100
        LIMIT 5
    ) as HighScoringUsers
FROM RankedPosts rp
FULL OUTER JOIN UserActivityStats uas ON 1=1
FULL OUTER JOIN TagAnalysis ta ON 1=1
FULL OUTER JOIN PostHistorySummary phs ON 1=1
WHERE 
    rp.OwnerUserId IS NOT NULL 
    AND uas.UserId IS NOT NULL 
    AND ta.TagName IS NOT NULL
    AND phs.PostId IS NOT NULL