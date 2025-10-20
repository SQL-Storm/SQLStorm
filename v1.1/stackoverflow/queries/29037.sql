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
            WHEN p.Tags IS NOT NULL AND p.Tags <> '' THEN
                -- count tags by counting occurrences of '><' and adding 1 after trimming leading/trailing angle brackets
                (LENGTH(TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM p.Tags))) - LENGTH(REPLACE(TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM p.Tags)), '><', '')))/LENGTH('><') + 1
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
    WHERE ph.CreationDate >= DATE '2023-01-01'
    GROUP BY ph.PostId
)
SELECT 
    'Performance Benchmark Report' as ReportTitle,
    COUNT(*) as TotalRecords,
    COUNT(DISTINCT rp.PostId) as DistinctPosts,
    COUNT(DISTINCT uas.UserId) as ActiveUsers,
    COUNT(DISTINCT ta.TagName) as PopularTags,
    COUNT(DISTINCT phs.PostId) as PostsWithHistory,
    COUNT(CASE WHEN rp.ScoreCategory = 'High' THEN 1 END) as HighScorePosts,
    COUNT(CASE WHEN rp.UserPostRank = 1 THEN 1 END) as LatestPosts,
    AVG(uas.TotalScore) as AvgTotalScore,
    AVG(rp.ViewCount) as AvgViewCount,
    AVG(rp.AnswerCount) as AvgAnswerCount,
    AVG(rp.CommentCount) as AvgCommentCount,
    (
        SELECT STRING_AGG(
            ('User:' || CAST(uas2.UserId AS VARCHAR) || '|Reputation:' || CAST(uas2.Reputation AS VARCHAR) || '|Posts:' || CAST(uas2.TotalPosts AS VARCHAR)),
            '; '
        )
        FROM UserActivityStats uas2
        WHERE uas2.TotalPosts > 100
        LIMIT 10
    ) as HighActivityUsers,
    (
        SELECT STRING_AGG(
            ('Tag:' || ta2.TagName || '|Popularity:' || ta2.PopularityLevel || '|Count:' || CAST(ta2.TagCount AS VARCHAR)),
            '; '
        )
        FROM TagAnalysis ta2
        WHERE ta2.PopularityLevel = 'Popular'
        LIMIT 5
    ) as PopularTagsList,
    (
        SELECT STRING_AGG(
            ('Post:' || CAST(phs2.PostId AS VARCHAR) || '|Actions:' || CAST(phs2.HistoryCount AS VARCHAR) || '|Last:' || CAST(phs2.LastActionDate AS VARCHAR)),
            '; '
        )
        FROM PostHistorySummary phs2
        WHERE phs2.HistoryCount > 50
        LIMIT 3
    ) as HighActivityPosts,
    (
        SELECT COUNT(DISTINCT ph.PostId)
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13)
        AND ph.CreationDate >= DATE '2023-06-01'
    ) as RecentVotingActions,
    (
        SELECT AVG(rp2.UserAvgScore)
        FROM RankedPosts rp2
        WHERE rp2.UserPostRank <= 5
    ) as AvgScoreOfTop5Posts,
    (
        SELECT STRING_AGG(
            ('Post:' || CAST(rp3.PostId AS VARCHAR) || '|Title:' || COALESCE(rp3.CleanTitle, '') || '|Score:' || CAST(rp3.Score AS VARCHAR)),
            '; '
        )
        FROM RankedPosts rp3
        WHERE rp3.Score > 1000
        AND rp3.ScoreCategory = 'High'
        LIMIT 5
    ) as HighScoringPosts,
    (
        SELECT COUNT(DISTINCT ph.UserId)
        FROM PostHistory ph
        JOIN Users u2 ON ph.UserId = u2.Id
        WHERE u2.Reputation > 10000
        AND ph.CreationDate >= DATE '2023-01-01'
    ) as HighRepUserActions,
    (
        SELECT COUNT(DISTINCT p2.Id)
        FROM Posts p2
        JOIN Users u3 ON p2.OwnerUserId = u3.Id
        WHERE u3.Reputation > 10000
        AND p2.PostTypeId = 1
        AND p2.CreationDate >= DATE '2023-01-01'
    ) as HighRepUserQuestions,
    (
        SELECT 
            COUNT(*) - 
            COUNT(CASE WHEN rp4.PrevScore IS NULL THEN 1 END)
        FROM RankedPosts rp4
        WHERE rp4.PostTypeId = 1
    ) as PostsWithScoreHistory,
    (
        SELECT COUNT(DISTINCT u4.Id)
        FROM Users u4
        JOIN PostHistory ph4 ON u4.Id = ph4.UserId
        WHERE ph4.PostHistoryTypeId IN (1, 2, 3)
        AND ph4.CreationDate >= DATE '2023-01-01'
    ) as UsersWithPostHistory,
    (
        SELECT 
            STRING_AGG(('User:' || CAST(uas3.UserId AS VARCHAR) || '|AvgScore:' || ROUND(CAST(uas3.AvgScore AS NUMERIC), 2)), '; ')
        FROM UserActivityStats uas3
        WHERE uas3.AvgScore > 100
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
GROUP BY
    rp.PostId,
    rp.PostTypeId,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.Title,
    rp.Tags,
    rp.OwnerUserId,
    rp.AcceptedAnswerId,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.UserPostRank,
    rp.PrevScore,
    rp.UserAvgScore,
    rp.ScoreCategory,
    rp.CleanTitle,
    rp.TagCount,
    uas.UserId,
    uas.Reputation,
    uas.DisplayName,
    uas.Views,
    uas.UpVotes,
    uas.DownVotes,
    uas.TotalPosts,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.CommentCount,
    uas.BadgeCount,
    uas.TotalScore,
    uas.AvgScore,
    uas.LastPostDate,
    ta.TagName,
    ta.TagCount,
    ta.ExcerptPostId,
    ta.WikiPostId,
    ta.PopularityLevel,
    ta.PopularityRank,
    phs.PostId,
    phs.HistoryCount,
    phs.UniqueActionTypes,
    phs.LastActionDate,
    phs.AllComments,
    phs.ActionTypes;