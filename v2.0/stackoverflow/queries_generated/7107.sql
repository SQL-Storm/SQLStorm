-- {"query": "7107.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1656} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN p.Id END) as HighViewQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 10 THEN p.Id END) as HighScoreAnswers,
    COUNT(DISTINCT b.Id) as BadgesEarned,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as TotalQuestionScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as TotalAnswerScore,
    ROUND(AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END), 2) as AvgQuestionScore,
    ROUND(AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END), 2) as AvgAnswerScore,
    MAX(p.CreationDate) as LastPostDate,
    MIN(p.CreationDate) as FirstPostDate,
    DATEDIFF(CURRENT_TIMESTAMP, MIN(p.CreationDate)) as DaysSinceFirstPost,
    COUNT(DISTINCT c.Id) as TotalComments,
    COUNT(DISTINCT CASE WHEN c.Score > 5 THEN c.Id END) as HighScoreComments,
    ROUND(AVG(c.Score), 2) as AvgCommentScore,
    COUNT(DISTINCT ph.Id) as PostHistoryEntries,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (1, 4, 6) THEN ph.Id END) as TitleBodyTagEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN ph.Id END) as CloseReopenDeleteActions,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 35 THEN ph.Id END) as MigrationAwayActions,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 36 THEN ph.Id END) as MigrationHereActions,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) as UpvotesReceived,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) as DownvotesReceived,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END), 0) as Favorites,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END), 0) as TotalBountyAmount,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
        THEN CONCAT(
            'Q:', 
            ROUND(AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END), 2),
            ' A:', 
            ROUND(AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END), 2)
        )
        ELSE 'No Posts'
    END as ScoreSummary,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 100 
        THEN 'High Activity'
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 50 
        THEN 'Moderate Activity'
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 10 
        THEN 'Low Activity'
        ELSE 'New User'
    END as ActivityLevel,
    EXISTS(
        SELECT 1 FROM Posts p2 
        WHERE p2.OwnerUserId = u.Id 
        AND p2.PostTypeId = 1 
        AND p2.Score > 100
    ) as HasHighScoreQuestion,
    EXISTS(
        SELECT 1 FROM Posts p3 
        WHERE p3.OwnerUserId = u.Id 
        AND p3.PostTypeId = 2 
        AND p3.Score > 50
    ) as HasHighScoreAnswer,
    COALESCE(
        (SELECT STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') 
         FROM Posts p 
         WHERE p.OwnerUserId = u.Id 
         AND p.PostTypeId = 1 
         AND p.Tags IS NOT NULL 
         AND LENGTH(p.Tags) > 2), 
        'No Tags'
    ) as MostUsedTags,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) = 0 
        THEN NULL
        ELSE (
            SELECT p2.Title 
            FROM Posts p2 
            WHERE p2.OwnerUserId = u.Id 
            AND p2.PostTypeId = 1 
            AND p2.Score = (
                SELECT MAX(p3.Score) 
                FROM Posts p3 
                WHERE p3.OwnerUserId = u.Id 
                AND p3.PostTypeId = 1
            )
            LIMIT 1
        )
    END as HighestScoringQuestion,
    CASE 
        WHEN u.Reputation > 10000 THEN 'Expert'
        WHEN u.Reputation > 5000 THEN 'Advanced'
        WHEN u.Reputation > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END as ReputationLevel,
    COALESCE(
        (SELECT STRING_AGG(CONCAT(b.Name, ' (', b.Date, ')'), '; ') 
         FROM Badges b 
         WHERE b.UserId = u.Id 
         AND b.Class = 1 
         ORDER BY b.Date DESC 
         LIMIT 5),
        'No Gold Badges'
    ) as RecentGoldBadges,
    ROUND(
        (COUNT(DISTINCT b.Id) * 100.0 / NULLIF(
            (SELECT COUNT(*) FROM Badges WHERE UserId = u.Id), 0
        )), 2
    ) as BadgeEfficiency,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 
        THEN COUNT(DISTINCT b.Id) / COUNT(DISTINCT p.Id)
        ELSE 0
    END as BadgesPerPostRatio
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN Votes v ON u.Id = v.UserId
LEFT JOIN Badges b ON u.Id = b.UserId
WHERE u.Id > 0 
    AND u.Reputation > 0
    AND (
        (p.PostTypeId IN (1, 2) AND p.CreationDate >= DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 1 YEAR))
        OR p.Id IS NULL
    )
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) > 0
    OR COUNT(DISTINCT b.Id) > 0
    OR COUNT(DISTINCT c.Id) > 0
ORDER BY 
    CASE WHEN u.Reputation > 10000 THEN 1 ELSE 2 END,
    u.Reputation DESC,
    TotalPosts DESC
LIMIT 1000;