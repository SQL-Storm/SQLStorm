-- {"query": "7323.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2289} 
WITH UserStats AS (
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
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LatestPostDate,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 5000 THEN 'Veteran'
            WHEN u.Reputation > 1000 THEN 'Regular'
            ELSE 'Newbie'
        END as ReputationTier,
        COALESCE(
            (SELECT STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ')
             FROM Posts p 
             WHERE p.OwnerUserId = u.Id 
             AND p.PostTypeId = 1 
             AND p.Tags IS NOT NULL
             AND LENGTH(p.Tags) > 2), 
            'No Tags'
        ) as CommonTags,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.AccountId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
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
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank,
        RANK() OVER (ORDER BY p.Score DESC) as GlobalScoreRank,
        NTILE(10) OVER (ORDER BY p.Score DESC) as ScoreQuartile
    FROM Posts p
    WHERE p.Score > 0 
    AND p.CreationDate >= DATEADD(year, -1, GETDATE())
),
PostHistorySummary AS (
    SELECT 
        ph.PostId,
        COUNT(*) as HistoryCount,
        COUNT(DISTINCT ph.PostHistoryTypeId) as UniqueActionTypes,
        MAX(ph.CreationDate) as LastActivity,
        STRING_AGG(ph.PostHistoryTypeId, ', ') WITHIN GROUP (ORDER BY ph.CreationDate) as ActionTypes,
        STRING_AGG(ph.Comment, '; ') WITHIN GROUP (ORDER BY ph.CreationDate) as Comments,
        CASE 
            WHEN MAX(ph.PostHistoryTypeId) IN (10, 11, 12, 13) THEN 'Closed/Reopened/Deleted'
            WHEN MAX(ph.PostHistoryTypeId) = 16 THEN 'Community Owned'
            ELSE 'Other'
        END as MajorAction
    FROM PostHistory ph
    WHERE ph.CreationDate >= DATEADD(month, -6, GETDATE())
    GROUP BY ph.PostId
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > (SELECT AVG(Count) FROM Tags) THEN 'Popular'
            WHEN t.Count > (SELECT AVG(Count) * 0.5 FROM Tags) THEN 'Moderate'
            ELSE 'Rare'
        END as PopularityLevel,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) as PopularityRank,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as RankNo
    FROM Tags t
    WHERE t.Count > 0
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.ReputationTier,
    us.PostCount,
    us.CommentCount,
    us.BadgeCount,
    us.AvgPostScore,
    us.LatestPostDate,
    us.CommonTags,
    us.ReputationRank,
    tp.PostId,
    tp.Title,
    tp.Score,
    tp.ViewCount,
    tp.CreationDate,
    tp.PostType,
    tp.ScoreRank,
    tp.GlobalScoreRank,
    tp.ScoreQuartile,
    phs.HistoryCount,
    phs.UniqueActionTypes,
    phs.LastActivity,
    phs.ActionTypes,
    phs.Comments,
    phs.MajorAction,
    ta.TagName,
    ta.Count as TagCount,
    ta.PopularityLevel,
    ta.PopularityRank,
    CASE 
        WHEN us.PostCount > 0 AND us.CommentCount > 0 THEN 
            CAST((us.CommentCount * 100.0 / us.PostCount) AS DECIMAL(5,2))
        ELSE 0
    END as CommentToPostRatio,
    CASE 
        WHEN tp.AnswerCount IS NOT NULL THEN 
            CAST((tp.AnswerCount * 100.0 / (COALESCE(tp.CommentCount, 0) + 1)) AS DECIMAL(5,2))
        ELSE 0
    END as AnswerToCommentRatio,
    CASE 
        WHEN us.Reputation > 10000 AND us.BadgeCount > 50 THEN 'Highly Active'
        WHEN us.Reputation > 5000 AND us.BadgeCount > 25 THEN 'Active'
        WHEN us.Reputation > 1000 AND us.BadgeCount > 10 THEN 'Regular'
        ELSE 'Casual'
    END as ActivityLevel,
    CASE 
        WHEN tp.Score > 1000 THEN 'Viral'
        WHEN tp.Score > 100 THEN 'Popular'
        WHEN tp.Score > 10 THEN 'Moderate'
        ELSE 'Low'
    END as PostPopularity,
    CASE 
        WHEN us.Reputation > 10000 THEN 'Elite Contributor'
        WHEN us.Reputation > 5000 THEN 'Expert'
        WHEN us.Reputation > 1000 THEN 'Contributor'
        ELSE 'Member'
    END as ContributionStatus,
    CASE 
        WHEN phs.HistoryCount > 10 THEN 'Highly Active'
        WHEN phs.HistoryCount > 5 THEN 'Active'
        WHEN phs.HistoryCount > 0 THEN 'Moderate'
        ELSE 'Inactive'
    END as ActivityStatus,
    COALESCE(
        (SELECT COUNT(*) 
         FROM PostHistory ph 
         WHERE ph.PostId = tp.PostId 
         AND ph.PostHistoryTypeId IN (10, 11, 12)
         AND ph.CreationDate >= DATEADD(year, -1, GETDATE())
        ),
        0
    ) as RecentCloseReopenDeletes,
    CASE 
        WHEN (tp.AnswerCount > 0 OR tp.CommentCount > 0) 
        AND (tp.Score > 50 OR tp.ViewCount > 1000) THEN 'High Engagement'
        WHEN tp.Score > 20 OR tp.ViewCount > 500 THEN 'Moderate Engagement'
        ELSE 'Low Engagement'
    END as EngagementLevel,
    (SELECT COUNT(DISTINCT p.OwnerUserId) 
     FROM Posts p 
     WHERE p.PostTypeId = 1 
     AND p.Tags LIKE '%' + ta.TagName + '%')
    - (SELECT COUNT(DISTINCT p.OwnerUserId) 
       FROM Posts p 
       WHERE p.PostTypeId = 1 
       AND p.Tags LIKE '%' + ta.TagName + '%'
       AND p.OwnerUserId IN (
           SELECT u.Id 
           FROM Users u 
           WHERE u.Reputation < 1000
       )
      ) as ActiveContributors,
    CASE 
        WHEN (SELECT AVG(Count) FROM Tags) > 0 
        THEN CAST((ta.Count * 100.0 / (SELECT AVG(Count) FROM Tags)) AS DECIMAL(5,2))
        ELSE 0
    END as RelativePopularity,
    (SELECT STRING_AGG(
        CASE WHEN EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = tp.PostId AND ph.UserId = us.UserId) 
        THEN 'Self-Edited' 
        ELSE 'Not Self-Edited' 
        END, 
        ', '
    ) FROM Posts p WHERE p.Id = tp.PostId) as EditingStatus,
    NULLIF(
        (SELECT AVG(ph.PostHistoryTypeId) 
         FROM PostHistory ph 
         WHERE ph.PostId = tp.PostId 
         AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
        ), 
        0
    ) as AvgEditType,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = us.UserId AND b.Name = 'Nice Question') 
        THEN 'Has Nice Question'
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = us.UserId AND b.Name = 'Good Question') 
        THEN 'Has Good Question'
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = us.UserId AND b.Name = 'Great Question') 
        THEN 'Has Great Question'
        ELSE 'No Elite Question Badge'
    END as QuestionQuality,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = us.UserId AND p.PostTypeId = 1 AND p.Score >= 10) 
        THEN 'Has High Scoring Questions'
        ELSE 'No High Scoring Questions'
    END as QuestionPerformance,
    CASE 
        WHEN ta.RankNo <= 50 THEN 'Top 50 Tags'
        WHEN ta.RankNo <= 100 THEN 'Top 100 Tags'
        ELSE 'Below Top 100 Tags'
    END as TagPosition
FROM UserStats us
LEFT JOIN TopPosts tp ON us.UserId = tp.OwnerUserId
LEFT JOIN PostHistorySummary phs ON tp.PostId = phs.PostId
LEFT JOIN TagAnalysis ta ON EXISTS (
    SELECT 1 FROM Posts p 
    WHERE p.Id = tp.PostId 
    AND p.Tags LIKE '%' + ta.TagName + '%'
)
WHERE us.PostCount > 0
AND us.Reputation > 100
AND (tp.Score IS NULL OR tp.Score > 0)
AND (tp.PostType = 'Question' OR tp.PostType IS NULL)
ORDER BY us.Reputation DESC, tp.Score DESC, us.ReputationRank ASC
OFFSET 0 ROWS
FETCH NEXT 10000 ROWS ONLY;