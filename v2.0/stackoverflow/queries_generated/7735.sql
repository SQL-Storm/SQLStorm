-- {"query": "7735.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1778} 
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
        DATEDIFF(CURRENT_TIMESTAMP, MAX(p.CreationDate)) as DaysSinceLastPost,
        DATEDIFF(CURRENT_TIMESTAMP, MAX(c.CreationDate)) as DaysSinceLastComment
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostRankings AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.ViewCount DESC) as ViewRank,
        RANK() OVER (ORDER BY p.Score DESC) as GlobalScoreRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as GlobalViewRank,
        CASE 
            WHEN p.Score >= 100 THEN 'High'
            WHEN p.Score >= 50 THEN 'Medium'
            WHEN p.Score >= 10 THEN 'Low'
            ELSE 'Very Low'
        END as ScoreCategory,
        CASE 
            WHEN p.ViewCount >= 1000 THEN 'High View'
            WHEN p.ViewCount >= 500 THEN 'Medium View'
            WHEN p.ViewCount >= 100 THEN 'Low View'
            ELSE 'Very Low View'
        END as ViewCategory
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
),
UserPostStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(p.Id) as TotalPosts,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) as Questions,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) as Answers,
        COUNT(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 END) as QuestionsWithAcceptedAnswer
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName
),
TopTags AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Very Popular'
            WHEN t.Count > 500 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Less Popular'
        END as PopularityLevel
    FROM Tags t
    WHERE t.Count > 100
),
ComplexPostHistory AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.UserDisplayName,
        ph.Comment,
        CASE 
            WHEN ph.PostHistoryTypeId = 10 THEN 
                (SELECT cr.Name FROM CloseReasonTypes cr WHERE cr.Id = CAST(ph.Comment AS INT))
            ELSE NULL
        END as CloseReason,
        CASE 
            WHEN ph.PostHistoryTypeId IN (1, 4, 7) THEN 'Title Change'
            WHEN ph.PostHistoryTypeId IN (2, 5, 8) THEN 'Body Change'
            WHEN ph.PostHistoryTypeId IN (3, 6, 9) THEN 'Tags Change'
            WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN 'Post Status Change'
            WHEN ph.PostHistoryTypeId IN (14, 15) THEN 'Moderation Action'
            ELSE 'Other'
        END as ChangeCategory,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as RecentChangeRank
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)
)
SELECT 
    'Combined Analysis Report' as ReportTitle,
    COUNT(DISTINCT uas.UserId) as TotalActiveUsers,
    COUNT(DISTINCT pr.Id) as TotalPostsProcessed,
    SUM(CASE WHEN pr.PostTypeId = 1 THEN 1 ELSE 0 END) as TotalQuestions,
    SUM(CASE WHEN pr.PostTypeId = 2 THEN 1 ELSE 0 END) as TotalAnswers,
    AVG(pr.Score) as AveragePostScore,
    AVG(pr.ViewCount) as AverageViewCount,
    COUNT(DISTINCT tt.TagName) as PopularTagsCount,
    COUNT(DISTINCT CASE WHEN upss.QuestionsWithAcceptedAnswer > 0 THEN upss.UserId END) as UsersWithAcceptedAnswers,
    COUNT(DISTINCT CASE WHEN ph.ChangeCategory = 'Title Change' THEN ph.PostId END) as PostsWithTitleChanges,
    COUNT(DISTINCT CASE WHEN ph.ChangeCategory = 'Body Change' THEN ph.PostId END) as PostsWithBodyChanges,
    COUNT(DISTINCT CASE WHEN ph.ChangeCategory = 'Tags Change' THEN ph.PostId END) as PostsWithTagChanges,
    (
        SELECT COUNT(*) FROM Posts p 
        WHERE p.Score >= 100 AND p.PostTypeId = 1
    ) as HighScoreQuestions,
    (
        SELECT COUNT(*) FROM Posts p 
        WHERE p.PostTypeId = 2 AND p.Score >= 10
    ) as HighScoreAnswers,
    (
        SELECT AVG(Reputation) FROM Users u 
        WHERE u.Views > 1000
    ) as AvgReputationOfHighViewers,
    (
        SELECT COUNT(*) FROM Posts p 
        WHERE p.CreationDate > DATEADD(DAY, -30, CURRENT_TIMESTAMP)
    ) as RecentPostsLast30Days,
    (
        SELECT COUNT(*) FROM Posts p 
        WHERE p.ClosedDate IS NOT NULL
    ) as ClosedPostsCount,
    (
        SELECT COUNT(*) FROM Badges b 
        WHERE b.Date > DATEADD(YEAR, -1, CURRENT_TIMESTAMP)
    ) as RecentBadgesCount
FROM UserActivityStats uas
FULL OUTER JOIN PostRankings pr ON 1=1
LEFT JOIN TopTags tt ON 1=1
LEFT JOIN UserPostStats upss ON uas.UserId = upss.UserId
LEFT JOIN ComplexPostHistory ph ON ph.PostId = pr.Id
WHERE 
    (uas.UserId IS NOT NULL OR pr.Id IS NOT NULL OR tt.TagName IS NOT NULL)
    AND (
        pr.GlobalScoreRank <= 10 
        OR pr.GlobalViewRank <= 10 
        OR tt.Count >= 1000
        OR upss.TotalPosts >= 100
        OR uas.Reputation >= 10000
    )
    AND (
        (pr.Score >= 100 OR pr.ViewCount >= 1000 OR tt.Count >= 1000)
        OR (ph.RecentChangeRank <= 3 AND ph.PostHistoryTypeId IN (1, 2, 3, 10))
    )
ORDER BY 
    (
        CASE WHEN pr.GlobalScoreRank <= 10 THEN pr.GlobalScoreRank ELSE 1000 END
    ),
    (
        CASE WHEN pr.GlobalViewRank <= 10 THEN pr.GlobalViewRank ELSE 1000 END
    ),
    tt.Count DESC
LIMIT 5000;