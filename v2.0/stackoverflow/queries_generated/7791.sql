-- {"query": "7791.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1932} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN p.Id END) as HighlyViewedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 10 THEN p.Id END) as HighScoreAnswers,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END), 0) as TotalQuestionViews,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as TotalAnswerScore,
    COUNT(DISTINCT b.Id) as BadgesEarned,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
    COUNT(DISTINCT c.Id) as CommentsMade,
    COUNT(DISTINCT CASE WHEN c.Score > 5 THEN c.Id END) as HighScoreComments,
    COUNT(DISTINCT ph.Id) as PostHistoryEntries,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN ph.Id END) as ModerationActions,
    AVG(CAST(p.Score AS FLOAT)) as AvgPostScore,
    MAX(p.CreationDate) as LatestPostDate,
    MIN(p.CreationDate) as EarliestPostDate,
    DATEDIFF(day, MIN(p.CreationDate), MAX(p.CreationDate)) as DaysActive,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 1000 THEN 'Elite'
        WHEN COUNT(DISTINCT p.Id) > 500 THEN 'Veteran'
        WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Experienced'
        WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Active'
        ELSE 'Beginner'
    END as ActivityLevel,
    STRING_AGG(DISTINCT t.TagName, ', ') as TagsUsed,
    COALESCE((
        SELECT TOP 1 v.VoteTypeId
        FROM Votes v
        WHERE v.UserId = u.Id
        GROUP BY v.VoteTypeId
        ORDER BY COUNT(*) DESC
    ), 0) as MostFrequentVoteType,
    COUNT(DISTINCT CASE WHEN p.LastActivityDate >= DATEADD(month, -6, GETDATE()) THEN p.Id END) as RecentActivity,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.CreationDate >= DATEADD(year, -1, GETDATE())) as PostsLastYear,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
        THEN ROUND(CAST(COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS FLOAT) / 
                  CAST(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS FLOAT) * 100, 2)
        ELSE 0 
    END as AnswerToQuestionRatio,
    ISNULL(
        (SELECT TOP 1 pt.Name 
         FROM PostTypes pt 
         WHERE pt.Id = (
             SELECT TOP 1 p3.PostTypeId 
             FROM Posts p3 
             WHERE p3.OwnerUserId = u.Id 
             GROUP BY p3.PostTypeId 
             ORDER BY COUNT(*) DESC
         )
        ), 'None'
    ) as MostFrequentPostType,
    ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostRank,
    RANK() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
    DENSE_RANK() OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC) as ScoreRank,
    NTILE(10) OVER (ORDER BY u.Reputation DESC) as ReputationDecile,
    LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) as PreviousReputation,
    LEAD(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) as NextReputation,
    ABS(u.Reputation - LAG(u.Reputation, 1, u.Reputation) OVER (ORDER BY u.Reputation DESC)) as ReputationChange,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
        AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) = 0 
        THEN 'PureQuestioner'
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0 
        AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) = 0 
        THEN 'PureAnswerer'
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
        AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0 
        THEN 'Balanced'
        ELSE 'Inactive'
    END as UserRole,
    (
        SELECT COUNT(*)
        FROM (
            SELECT DISTINCT p1.Id
            FROM Posts p1
            INNER JOIN PostLinks pl ON p1.Id = pl.PostId
            INNER JOIN Posts p2 ON pl.RelatedPostId = p2.Id
            WHERE p1.OwnerUserId = u.Id
            AND pl.LinkTypeId = 3
            AND p2.OwnerUserId != u.Id
        ) AS DuplicateAnswers
    ) as DuplicateAnswersFound,
    (
        SELECT COUNT(*)
        FROM (
            SELECT DISTINCT p1.Id
            FROM Posts p1
            INNER JOIN PostLinks pl ON p1.Id = pl.PostId
            INNER JOIN Posts p2 ON pl.RelatedPostId = p2.Id
            WHERE p1.OwnerUserId = u.Id
            AND pl.LinkTypeId = 1
            AND p2.OwnerUserId != u.Id
        ) AS ExternalLinks
    ) as ExternalLinks,
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM Posts p3 
            WHERE p3.OwnerUserId = u.Id 
            AND p3.ClosedDate IS NOT NULL
        ) THEN 'HasClosedPosts'
        ELSE 'NoClosedPosts'
    END as ClosedPostStatus,
    COALESCE(
        (SELECT TOP 1 p4.Title 
         FROM Posts p4 
         WHERE p4.OwnerUserId = u.Id 
         AND p4.PostTypeId = 1 
         ORDER BY p4.Score DESC
        ), 'No Questions'
    ) as TopQuestionTitle,
    COALESCE(
        (SELECT TOP 1 p5.Body 
         FROM Posts p5 
         WHERE p5.OwnerUserId = u.Id 
         AND p5.PostTypeId = 2 
         ORDER BY p5.Score DESC 
         OPTION (MAXDOP 1)
        ), 'No Answers'
    ) as TopAnswerBody,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 10000 THEN 'Legend'
        WHEN COUNT(DISTINCT p.Id) > 5000 THEN 'Master'
        WHEN COUNT(DISTINCT p.Id) > 1000 THEN 'Expert'
        WHEN COUNT(DISTINCT p.Id) > 500 THEN 'Professional'
        WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Enthusiast'
        ELSE 'Member'
    END as UserStatus,
    ROUND(
        CAST(SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS FLOAT) /
        NULLIF(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END), 0), 2
    ) as AvgQuestionViews
FROM Users u
LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
LEFT OUTER JOIN Badges b ON u.Id = b.UserId
LEFT OUTER JOIN Comments c ON u.Id = c.UserId
LEFT OUTER JOIN PostHistory ph ON u.Id = ph.UserId
LEFT OUTER JOIN Tags t ON u.Id IN (
    SELECT DISTINCT p1.OwnerUserId 
    FROM Posts p1 
    WHERE CHARINDEX(t.TagName, p1.Tags) > 0
)
WHERE u.Id > 0
GROUP BY 
    u.Id, 
    u.DisplayName, 
    u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) >= 10 OR COUNT(DISTINCT b.Id) >= 5 OR COUNT(DISTINCT c.Id) >= 20
ORDER BY 
    u.Reputation DESC,
    COUNT(DISTINCT p.Id) DESC,
    COALESCE(SUM(p.Score), 0) DESC;