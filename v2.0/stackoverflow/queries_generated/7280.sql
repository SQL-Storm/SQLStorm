-- {"query": "7280.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2374} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN p.Id END) as HighViewQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 10 THEN p.Id END) as HighScoreAnswers,
    COUNT(DISTINCT b.Id) as BadgesReceived,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
    COUNT(DISTINCT c.Id) as CommentsMade,
    COUNT(DISTINCT CASE WHEN c.Score > 5 THEN c.Id END) as HighScoreComments,
    COUNT(DISTINCT ph.Id) as PostHistoryEntries,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN ph.Id END) as CloseReopenEvents,
    AVG(CAST(p.Score AS FLOAT)) as AvgPostScore,
    MAX(p.CreationDate) as LatestPost,
    MIN(p.CreationDate) as FirstPost,
    DATEDIFF(DAY, MIN(p.CreationDate), MAX(p.CreationDate)) as DaysActive,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 
            (COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) * 100.0 / COUNT(DISTINCT p.Id))
        ELSE 0 
    END as QuestionPercentage,
    COALESCE(
        (SELECT TOP 1 t.TagName 
         FROM Posts p2 
         JOIN STRING_SPLIT(p2.Tags, '><') AS tag ON 1=1
         JOIN Tags t ON t.TagName = TRIM(tag.value) 
         WHERE p2.OwnerUserId = u.Id 
         GROUP BY t.TagName 
         ORDER BY COUNT(*) DESC), 
        'No Tags'
    ) as PrimaryTag,
    CASE 
        WHEN AVG(CAST(p.Score AS FLOAT)) > 50 THEN 'Highly Engaged'
        WHEN AVG(CAST(p.Score AS FLOAT)) > 10 THEN 'Moderately Engaged'
        ELSE 'Low Engagement'
    END as EngagementLevel,
    ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostRank,
    RANK() OVER (ORDER BY AVG(CAST(p.Score AS FLOAT)) DESC) as ScoreRank,
    DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT b.Id) DESC) as BadgeRank,
    PERCENT_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id)) as PostPercentile,
    NTILE(4) OVER (ORDER BY COUNT(DISTINCT p.Id)) as PostQuartile,
    LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation) as PreviousReputation,
    LEAD(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation) as NextReputation,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) OVER (ORDER BY u.Reputation) as CumulativeQuestions,
    AVG(COUNT(DISTINCT p.Id)) OVER (ORDER BY u.Reputation ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) as MovingAvgPosts,
    SIGN(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) - 
         (SELECT AVG(QuestionCount) 
          FROM (SELECT COUNT(DISTINCT p2.Id) as QuestionCount 
                FROM Posts p2 
                WHERE p2.OwnerUserId IS NOT NULL 
                GROUP BY p2.OwnerUserId) avg_q)) as QuestionDeviation,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Tags LIKE '%<c>%<%' THEN p.Id END) as CSharpQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND (p.Title LIKE '%sql%' OR p.Tags LIKE '%<sql>%') THEN p.Id END) as SQLQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) as QuestionWithAcceptedAnswer,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL THEN p.Id END) as AnswerWithParent,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Id END) as QuestionsWithAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommentCount > 0 THEN p.Id END) as QuestionsWithComments,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.FavoriteCount > 0 THEN p.Id END) as QuestionsWithFavorites,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.LastEditDate IS NOT NULL THEN p.Id END) as EditedAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.LastEditDate IS NOT NULL THEN p.Id END) as EditedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.Id END) as ClosedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommunityOwnedDate IS NOT NULL THEN p.Id END) as CommunityOwnedQuestions,
    COUNT(DISTINCT CASE WHEN NOT EXISTS (SELECT 1 FROM Comments c2 WHERE c2.PostId = p.Id) THEN p.Id END) as QuestionsWithoutComments,
    COUNT(DISTINCT CASE WHEN NOT EXISTS (SELECT 1 FROM Votes v2 WHERE v2.PostId = p.Id) THEN p.Id END) as PostsWithoutVotes,
    CONCAT(
        'User ', 
        u.Id, 
        ' (', 
        COALESCE(u.DisplayName, 'Anonymous'), 
        ') - ', 
        CASE WHEN u.WebsiteUrl IS NOT NULL THEN SUBSTRING(u.WebsiteUrl, 1, 20) ELSE 'No Website' END,
        ' - ', 
        COALESCE(UPPER(SUBSTRING(u.Location, 1, 15)), 'Unknown Location'),
        ' - ', 
        CASE WHEN u.Views > 1000 THEN 'High View Count' ELSE 'Regular View Count' END
    ) as UserDescription,
    COALESCE(
        (SELECT TOP 1 p3.Title 
         FROM Posts p3 
         WHERE p3.OwnerUserId = u.Id 
         AND p3.PostTypeId = 1 
         ORDER BY p3.Score DESC),
        'No High Scoring Questions'
    ) as TopQuestionTitle,
    COALESCE(
        (SELECT TOP 1 p4.Body 
         FROM Posts p4 
         WHERE p4.OwnerUserId = u.Id 
         AND p4.PostTypeId = 1 
         ORDER BY p4.CreationDate),
        'No Question Body'
    ) as OldestQuestionBody,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) as UpvotesGiven,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3) as DownvotesGiven,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 5) as FavoritesGiven,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 10) as CloseVotes,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 11) as ReopenVotes,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 12) as DeleteVotes,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 13) as UndeleteVotes,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 14) as LockVotes,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 15) as UnlockVotes,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 19) as ProtectVotes,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 20) as UnprotectVotes,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 22) as UnmergeVotes,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 17) as MigrationVotes,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 25) as TweetVotes,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 31) as ChatMovedVotes,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 33) as NoticeAddedVotes,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 34) as NoticeRemovedVotes,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 35) as MigratedAwayVotes,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 36) as MigratedHereVotes
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN Comments c ON c.UserId = u.Id
LEFT JOIN PostHistory ph ON ph.UserId = u.Id
WHERE u.CreationDate >= '2010-01-01'
GROUP BY 
    u.Id, 
    u.DisplayName, 
    u.Reputation, 
    u.WebsiteUrl, 
    u.Location,
    u.Views
HAVING 
    COUNT(DISTINCT p.Id) > 0
    AND (COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
         OR COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0)
    AND COUNT(DISTINCT CASE WHEN b.Id IS NOT NULL THEN b.Id END) >= 0
    AND (COALESCE(SUM(p.Score), 0) BETWEEN -1000 AND 100000)
ORDER BY 
    COUNT(DISTINCT p.Id) DESC,
    AVG(CAST(p.Score AS FLOAT)) DESC,
    COUNT(DISTINCT b.Id) DESC
OFFSET 0 ROWS
FETCH NEXT 1000 ROWS ONLY