-- {"query": "7224.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3213} 
WITH UserPostStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) as TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCount,
        AVG(p.Score) as AvgScore,
        MAX(p.CreationDate) as LastPostDate,
        STRING_AGG(DISTINCT p.Tags, ', ') as AllTags,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews,
        COALESCE(SUM(p.FavoriteCount), 0) as TotalFavorites,
        COUNT(DISTINCT c.Id) as TotalComments,
        COUNT(DISTINCT b.Id) as TotalBadges,
        STRING_AGG(DISTINCT CASE WHEN b.Class = 1 THEN b.Name END, ', ') as GoldBadges,
        STRING_AGG(DISTINCT CASE WHEN b.Class = 2 THEN b.Name END, ', ') as SilverBadges,
        STRING_AGG(DISTINCT CASE WHEN b.Class = 3 THEN b.Name END, ', ') as BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        TotalPosts,
        QuestionCount,
        AnswerCount,
        AvgScore,
        LastPostDate,
        AllTags,
        TotalViews,
        TotalFavorites,
        TotalComments,
        TotalBadges,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY TotalViews DESC, Reputation DESC) as RankByViews,
        ROW_NUMBER() OVER (ORDER BY TotalPosts DESC, Reputation DESC) as RankByPosts,
        ROW_NUMBER() OVER (ORDER BY TotalBadges DESC, Reputation DESC) as RankByBadges
    FROM UserPostStats
),
PostActivity AS (
    SELECT 
        p.Id,
        p.Title,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostType,
        DATEDIFF(day, p.CreationDate, CURRENT_TIMESTAMP) as DaysSinceCreation,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'High'
            WHEN p.ViewCount > 100 THEN 'Medium'
            ELSE 'Low'
        END as ViewCategory,
        CASE 
            WHEN p.Score > 100 THEN 'Popular'
            WHEN p.Score > 20 THEN 'Moderate'
            ELSE 'Low'
        END as Popularity,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) as EngagementCount,
        LEAD(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextPostDate,
        LAG(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousPostDate,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as UserAvgScore,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as UserPostCount
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
),
TagStats AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        CASE 
            WHEN t.Count > 1000 THEN 'Very Popular'
            WHEN t.Count > 100 THEN 'Popular'
            WHEN t.Count > 10 THEN 'Moderate'
            ELSE 'Rare'
        END as PopularityLevel,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as RankByPopularity
    FROM Tags t
),
UserEngagement AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews,
        COALESCE(SUM(p.FavoriteCount), 0) as TotalFavorites,
        COUNT(DISTINCT p.Id) as PostsCreated,
        COUNT(DISTINCT v.Id) as VotesReceived,
        COUNT(DISTINCT c.Id) as CommentsMade,
        COUNT(DISTINCT b.Id) as BadgesEarned,
        AVG(p.Score) as AvgPostScore,
        AVG(COALESCE(v.BountyAmount, 0)) as AvgBountyAwarded,
        CASE 
            WHEN COUNT(DISTINCT p.Id) = 0 THEN 0
            ELSE COUNT(DISTINCT v.Id) * 1.0 / COUNT(DISTINCT p.Id)
        END as VotesPerPost,
        CASE 
            WHEN COUNT(DISTINCT p.Id) = 0 THEN 0
            ELSE COUNT(DISTINCT c.Id) * 1.0 / COUNT(DISTINCT p.Id)
        END as CommentsPerPost,
        CASE 
            WHEN COUNT(DISTINCT v.Id) = 0 THEN 0
            ELSE SUM(COALESCE(v.BountyAmount, 0)) * 1.0 / COUNT(DISTINCT v.Id)
        END as AvgBountyPerVote
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND (v.VoteTypeId IN (2, 3))
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT 
    'Performance Benchmark Report' as ReportTitle,
    COUNT(*) as TotalRecords,
    (SELECT COUNT(*) FROM Users) as TotalUsers,
    (SELECT COUNT(*) FROM Posts) as TotalPosts,
    (SELECT COUNT(*) FROM Tags) as TotalTags,
    (SELECT COUNT(*) FROM Badges) as TotalBadges,
    (SELECT COUNT(*) FROM Comments) as TotalComments,
    (SELECT COUNT(*) FROM Votes) as TotalVotes,
    (SELECT COUNT(*) FROM PostHistory) as TotalHistory,
    (SELECT COUNT(*) FROM PostLinks) as TotalLinks,
    (SELECT COUNT(DISTINCT PostId) FROM PostHistory) as DistinctPostsWithHistory,
    (SELECT COUNT(DISTINCT UserId) FROM Votes WHERE UserId IS NOT NULL) as DistinctVotingUsers,
    (SELECT COUNT(DISTINCT UserId) FROM Comments WHERE UserId IS NOT NULL) as DistinctCommentingUsers,
    (SELECT COUNT(DISTINCT UserId) FROM Badges WHERE UserId IS NOT NULL) as DistinctBadgeUsers,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND Tags IS NOT NULL AND Tags != '') as QuestionsWithTags,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 2 AND ParentId IS NOT NULL) as AnswersWithParents,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND AnswerCount > 0) as QuestionsWithAnswers,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND ClosedDate IS NOT NULL) as ClosedQuestions,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND CommunityOwnedDate IS NOT NULL) as CommunityOwnedQuestions,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND Score > 100) as HighlyRatedQuestions,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 2 AND Score > 50) as HighlyRatedAnswers,
    'Benchmark Complete' as Status,
    CURRENT_TIMESTAMP as ReportTimestamp,
    ROUND(AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END), 2) as AvgPostScore,
    ROUND(AVG(CASE WHEN p.ViewCount IS NOT NULL THEN p.ViewCount ELSE 0 END), 2) as AvgViewCount,
    (
        SELECT COUNT(*) * 100.0 / (SELECT COUNT(*) FROM Posts) 
        FROM Posts 
        WHERE PostTypeId = 1 AND Tags IS NOT NULL AND Tags != ''
    ) as PercentQuestionsWithTags,
    (
        SELECT COUNT(*) * 100.0 / (SELECT COUNT(*) FROM Posts) 
        FROM Posts 
        WHERE PostTypeId = 2 AND ParentId IS NOT NULL
    ) as PercentAnswersWithParents,
    (
        SELECT COUNT(*) * 100.0 / (SELECT COUNT(*) FROM Posts) 
        FROM Posts 
        WHERE PostTypeId = 1 AND AnswerCount > 0
    ) as PercentQuestionsWithAnswers,
    (
        SELECT COUNT(*) * 100.0 / (SELECT COUNT(*) FROM Posts) 
        FROM Posts 
        WHERE PostTypeId = 1 AND ClosedDate IS NOT NULL
    ) as PercentClosedQuestions,
    (
        SELECT COUNT(*) * 100.0 / (SELECT COUNT(*) FROM Posts) 
        FROM Posts 
        WHERE PostTypeId = 1 AND CommunityOwnedDate IS NOT NULL
    ) as PercentCommunityOwnedQuestions,
    (
        SELECT COUNT(*) * 100.0 / (SELECT COUNT(*) FROM Posts) 
        FROM Posts 
        WHERE PostTypeId = 1 AND Score > 100
    ) as PercentHighlyRatedQuestions,
    (
        SELECT COUNT(*) * 100.0 / (SELECT COUNT(*) FROM Posts) 
        FROM Posts 
        WHERE PostTypeId = 2 AND Score > 50
    ) as PercentHighlyRatedAnswers
FROM Posts p
INNER JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
WHERE p.CreationDate >= DATEADD(year, -1, CURRENT_TIMESTAMP)
  AND u.Reputation > 100
  AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
  AND EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1)
  AND (
    EXISTS (SELECT 1 FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1)
    OR EXISTS (SELECT 1 FROM Posts p3 WHERE p3.OwnerUserId = u.Id AND p3.PostTypeId = 2)
  )
  AND (
    (SELECT COUNT(*) FROM Votes v2 WHERE v2.UserId = u.Id AND v2.VoteTypeId = 2) > 0
    OR (SELECT COUNT(*) FROM Comments c2 WHERE c2.UserId = u.Id) > 0
  )
  AND p.ContentLicense IS NOT NULL
  AND p.ContentLicense != ''
  AND COALESCE(p.CreationDate, CURRENT_TIMESTAMP) > '2010-01-01'
  AND COALESCE(u.CreationDate, CURRENT_TIMESTAMP) > '2010-01-01'
  AND (
    SELECT COUNT(*) FROM PostHistory ph 
    WHERE ph.PostId = p.Id 
    AND ph.CreationDate >= DATEADD(month, -6, CURRENT_TIMESTAMP)
  ) > 0
  AND (
    SELECT COUNT(*) FROM Posts p4 
    WHERE p4.OwnerUserId = u.Id 
    AND p4.CreationDate >= DATEADD(year, -1, CURRENT_TIMESTAMP)
  ) >= 1
  AND p.Tags IS NOT NULL
  AND LENGTH(p.Tags) > 0
  AND p.Tags != ''
  AND p.ViewCount IS NOT NULL
  AND p.Score IS NOT NULL
  AND p.OwnerUserId IS NOT NULL
  AND u.Id > 0
  AND u.Reputation > 0
  AND (
    SELECT COUNT(*) FROM Votes v3 
    WHERE v3.UserId = u.Id 
    AND v3.CreationDate >= DATEADD(year, -1, CURRENT_TIMESTAMP)
  ) > 0
  AND (
    SELECT COUNT(*) FROM Comments c3 
    WHERE c3.UserId = u.Id 
    AND c3.CreationDate >= DATEADD(year, -1, CURRENT_TIMESTAMP)
  ) > 0
  AND EXISTS (
    SELECT 1 FROM (
      SELECT p5.Id, p5.PostTypeId, p5.OwnerUserId, p5.Score, p5.ViewCount, p5.CreationDate
      FROM Posts p5
      WHERE p5.OwnerUserId = u.Id
      AND p5.CreationDate >= DATEADD(year, -1, CURRENT_TIMESTAMP)
    ) subquery
    WHERE subquery.OwnerUserId = u.Id
    AND subquery.Score > 0
  )
  AND (
    SELECT SUM(p6.ViewCount) 
    FROM Posts p6 
    WHERE p6.OwnerUserId = u.Id
  ) IS NOT NULL
  AND (
    SELECT AVG(p7.Score) 
    FROM Posts p7 
    WHERE p7.OwnerUserId = u.Id
  ) IS NOT NULL
  AND (
    SELECT COUNT(*) 
    FROM Badges b2 
    WHERE b2.UserId = u.Id 
    AND b2.Date >= DATEADD(year, -1, CURRENT_TIMESTAMP)
  ) >= 0
  AND (
    SELECT COUNT(DISTINCT t2.TagName) 
    FROM Tags t2
    INNER JOIN (
      SELECT DISTINCT TRIM(SUBSTRING(p8.Tags, n.n, CHARINDEX('>', p8.Tags, n.n) - n.n)) as Tag
      FROM Posts p8
      CROSS JOIN (
        SELECT 1 as n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
        UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
      ) n
      WHERE p8.OwnerUserId = u.Id
      AND p8.Tags IS NOT NULL
      AND CHARINDEX('>', p8.Tags, n.n) > 0
      AND n.n <= LEN(p8.Tags)
      AND SUBSTRING(p8.Tags, n.n, 1) = '<'
    ) taglist ON t2.TagName = taglist.Tag
  ) >= 0
  AND (
    SELECT STRING_AGG(DISTINCT p9.Title, ', ')
    FROM Posts p9
    WHERE p9.OwnerUserId = u.Id
    AND p9.CreationDate >= DATEADD(year, -1, CURRENT_TIMESTAMP)
  ) IS NOT NULL
HAVING COUNT(*) > 0
ORDER BY (SELECT 1) -- Ensures we're still doing aggregation
OPTION (MAXDOP 4); -- Force parallel execution for performance testing