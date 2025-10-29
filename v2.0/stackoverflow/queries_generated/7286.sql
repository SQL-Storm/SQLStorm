-- {"query": "7286.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3289} 
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
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id END) as Wikis,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 4 THEN p.Id END) as TagWikiExcerpts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 5 THEN p.Id END) as TagWikis,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as TotalQuestionScore,
    SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as TotalAnswerScore,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) as AvgQuestionScore,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) as AvgAnswerScore,
    MAX(p.CreationDate) as LatestActivity,
    STRING_AGG(DISTINCT b.Name, ', ') as Badges,
    COUNT(DISTINCT c.Id) as CommentCount,
    COUNT(DISTINCT pl.Id) as LinkCount,
    COUNT(DISTINCT ph.Id) as HistoryCount,
    COUNT(DISTINCT v.Id) as VoteCount,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) as Upvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) as Downvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) as Favorites,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 6 THEN v.Id END) as CloseVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 7 THEN v.Id END) as ReopenVotes,
    STRING_AGG(DISTINCT COALESCE(p.Title, p.Tags), ' | ') as PostInfo,
    CONCAT('UserRank_', 
        CASE 
            WHEN u.Reputation >= 1000000 THEN 'Legendary'
            WHEN u.Reputation >= 100000 THEN 'Epic'
            WHEN u.Reputation >= 10000 THEN 'Master'
            WHEN u.Reputation >= 1000 THEN 'Expert'
            WHEN u.Reputation >= 100 THEN 'Novice'
            ELSE 'Beginner'
        END
    ) as UserRank,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 100 THEN 'HighlyActive'
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 50 THEN 'Active'
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 10 THEN 'Moderate'
        ELSE 'Occasional'
    END as ActivityLevel,
    DATEDIFF('day', u.CreationDate, u.LastAccessDate) as DaysSinceLastAccess,
    DATEDIFF('day', u.CreationDate, CURRENT_TIMESTAMP) as AccountAgeDays,
    (SELECT COUNT(*) 
     FROM Posts p2 
     WHERE p2.OwnerUserId = u.Id 
       AND p2.PostTypeId IN (1,2) 
       AND p2.Score > 0
    ) as PositiveScoredPosts,
    (SELECT MAX(p3.Score) 
     FROM Posts p3 
     WHERE p3.OwnerUserId = u.Id 
       AND p3.PostTypeId = 1
    ) as MaxQuestionScore,
    (SELECT SUM(p4.Score) 
     FROM Posts p4 
     WHERE p4.OwnerUserId = u.Id 
       AND p4.PostTypeId = 2 
       AND p4.CreationDate > DATEADD('year', -1, CURRENT_TIMESTAMP)
    ) as RecentAnswerScore,
    COALESCE((SELECT AVG(p5.Score) 
              FROM Posts p5 
              WHERE p5.OwnerUserId = u.Id 
                AND p5.PostTypeId = 2 
                AND p5.Score IS NOT NULL
             ), 0) as AvgAnswerScoreRecent,
    (SELECT COUNT(*) 
     FROM Votes v2 
     WHERE v2.UserId = u.Id 
       AND v2.VoteTypeId IN (2,3) 
       AND v2.CreationDate > DATEADD('month', -3, CURRENT_TIMESTAMP)
    ) as RecentVotes,
    (SELECT STRING_AGG(DISTINCT pt.Name, ', ') 
     FROM Posts p6 
     JOIN PostTypes pt ON p6.PostTypeId = pt.Id 
     WHERE p6.OwnerUserId = u.Id 
       AND p6.CreationDate > DATEADD('week', -2, CURRENT_TIMESTAMP)
    ) as RecentPostTypes,
    (SELECT COUNT(DISTINCT p7.ParentId) 
     FROM Posts p7 
     WHERE p7.OwnerUserId = u.Id 
       AND p7.PostTypeId = 2 
       AND p7.ParentId IS NOT NULL
    ) as AnsweredQuestions,
    COUNT(DISTINCT CASE WHEN (p.PostTypeId = 1 AND p.AnswerCount > 0) THEN p.Id END) as QuestionsWithAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.Id END) as ClosedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.FavoriteCount > 0 THEN p.Id END) as FavoritedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN p.Id END) as HighlyViewedQuestions,
    ROUND(AVG(CASE WHEN p.PostTypeId = 2 THEN p.ViewCount ELSE NULL END), 2) as AvgAnswerViews,
    ROUND(AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END), 2) as AvgQuestionViews,
    CASE 
        WHEN MAX(p.CreationDate) > DATEADD('week', -1, CURRENT_TIMESTAMP) THEN 'RecentlyActive'
        WHEN MAX(p.CreationDate) > DATEADD('month', -1, CURRENT_TIMESTAMP) THEN 'ActiveLastMonth'
        WHEN MAX(p.CreationDate) > DATEADD('year', -1, CURRENT_TIMESTAMP) THEN 'ActiveLastYear'
        ELSE 'Inactive'
    END as RecentActivityStatus,
    (SELECT COUNT(*) 
     FROM Badges b2 
     WHERE b2.UserId = u.Id 
       AND b2.Date > DATEADD('month', -6, CURRENT_TIMESTAMP)
    ) as RecentBadges,
    (SELECT COUNT(*) 
     FROM PostHistory ph2 
     WHERE ph2.UserId = u.Id 
       AND ph2.CreationDate > DATEADD('week', -4, CURRENT_TIMESTAMP)
    ) as RecentHistory,
    (SELECT STRING_AGG(CONCAT('Post_', p8.Id, ':', p8.Score), '; ') 
     FROM Posts p8 
     WHERE p8.OwnerUserId = u.Id 
       AND p8.Score > 10
    ) as HighScorePosts,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
    DENSE_RANK() OVER (PARTITION BY CASE WHEN u.Reputation > 10000 THEN 'HighReputation' ELSE 'LowReputation' END ORDER BY u.Views DESC) as ReputationPartitionRank,
    LAG(u.Reputation) OVER (ORDER BY u.Reputation DESC) as PreviousReputation,
    LEAD(u.Reputation) OVER (ORDER BY u.Reputation DESC) as NextReputation,
    NTILE(100) OVER (ORDER BY u.Reputation) as RepPercentile,
    PERCENT_RANK() OVER (ORDER BY u.Reputation) as RepPercentileRank,
    SUM(u.Reputation) OVER (ORDER BY u.Reputation ROWS UNBOUNDED PRECEDING) as CumulativeRep,
    AVG(u.Reputation) OVER (ORDER BY u.Reputation ROWS BETWEEN 5 PRECEDING AND 5 FOLLOWING) as MovingAvgRep,
    (COUNT(DISTINCT p.Id) * COALESCE(AVG(p.Score), 0)) as ProductivityScore,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN (COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) * 100.0 / COUNT(DISTINCT p.Id))
        ELSE 0 
    END as AnswerPercentage,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN COALESCE(ROUND((COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) * 100.0 / COUNT(DISTINCT p.Id)), 2), 0)
        ELSE 0 
    END as AnswerRatio,
    (SELECT COUNT(DISTINCT t.Id) 
     FROM Tags t 
     WHERE t.TagName IN (
         SELECT TRIM(SUBSTRING(p9.Tags, pos, 
             CASE WHEN pos2 > 0 THEN pos2 - pos ELSE LENGTH(p9.Tags) - pos + 1 END)) 
         FROM Posts p9 
         CROSS JOIN (VALUES (1), (2), (3), (4), (5)) AS nums(n)
         WHERE p9.OwnerUserId = u.Id 
           AND p9.PostTypeId = 1 
           AND p9.Tags IS NOT NULL
           AND pos = CASE WHEN pos = 1 THEN 1 ELSE POSITION('><' IN p9.Tags) + 2 END
     )
    ) as TaggedTopics,
    (SELECT COUNT(*) 
     FROM PostLinks pl2 
     WHERE (pl2.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) OR pl2.RelatedPostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id))
       AND pl2.CreationDate > DATEADD('month', -2, CURRENT_TIMESTAMP)
    ) as RecentLinkActivity,
    (
        SELECT COUNT(DISTINCT p10.Id) 
        FROM Posts p10 
        WHERE p10.OwnerUserId = u.Id 
          AND p10.PostTypeId IN (1,2)
          AND p10.Score IS NOT NULL
          AND p10.Score > (
              SELECT AVG(p11.Score) 
              FROM Posts p11 
              WHERE p11.OwnerUserId = u.Id 
                AND p11.PostTypeId IN (1,2)
          )
    ) as AboveAveragePosts,
    CONCAT(
        'Rank_', 
        CASE 
            WHEN ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) BETWEEN 1 AND 10 THEN 'Top10'
            WHEN ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) BETWEEN 11 AND 100 THEN 'Top100'
            WHEN ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) BETWEEN 101 AND 1000 THEN 'Top1k'
            ELSE 'Below1k'
        END
    ) as RankingGroup,
    (SELECT COUNT(*) 
     FROM Posts p12 
     WHERE p12.OwnerUserId = u.Id 
       AND p12.PostTypeId IN (1,2)
       AND p12.Score < 0
    ) as NegativeScoringPosts,
    (SELECT MAX(p13.Score) 
     FROM Posts p13 
     WHERE p13.OwnerUserId = u.Id 
       AND p13.PostTypeId IN (1,2)
       AND p13.Score IS NOT NULL
    ) as TopPostScore,
    (SELECT MIN(p14.Score) 
     FROM Posts p14 
     WHERE p14.OwnerUserId = u.Id 
       AND p14.PostTypeId IN (1,2)
       AND p14.Score IS NOT NULL
    ) as BottomPostScore,
    (SELECT COUNT(*) 
     FROM Posts p15 
     WHERE p15.OwnerUserId = u.Id 
       AND p15.PostTypeId = 1 
       AND p15.Tags LIKE '%<%'
    ) as TaggedQuestions,
    (SELECT COUNT(*) 
     FROM Comments c2 
     WHERE c2.UserId = u.Id 
       AND c2.CreationDate > DATEADD('month', -3, CURRENT_TIMESTAMP)
    ) as RecentComments,
    (SELECT STRING_AGG(CONCAT('Badge_', b3.Name, '(', b3.Date, ')'), ' | ') 
     FROM Badges b3 
     WHERE b3.UserId = u.Id 
       AND b3.Date > DATEADD('month', -1, CURRENT_TIMESTAMP)
    ) as RecentBadgesString,
    (SELECT COUNT(*) 
     FROM Votes v3 
     WHERE v3.UserId = u.Id 
       AND v3.CreationDate > DATEADD('month', -1, CURRENT_TIMESTAMP)
       AND v3.VoteTypeId IN (2,3,5)
    ) as MonthlyVotes,
    (SELECT COUNT(DISTINCT p16.ParentId) 
     FROM Posts p16 
     WHERE p16.OwnerUserId = u.Id 
       AND p16.PostTypeId = 2 
       AND p16.ParentId IS NOT NULL
       AND p16.Score > 0
    ) as HighScoringAnswers,
    (SELECT AVG(p17.ViewCount) 
     FROM Posts p17 
     WHERE p17.OwnerUserId = u.Id 
       AND p17.PostTypeId = 1
    ) as AvgQuestionViewsRecent,
    (SELECT STRING_AGG(CONCAT(p18.Title, ':', p18.Score), ' | ')
     FROM Posts p18 
     WHERE p18.OwnerUserId = u.Id 
       AND p18.PostTypeId = 1 
       AND p18.Score > 5
     ORDER BY p18.Score DESC
     LIMIT 5
    ) as TopQuestions,
    (SELECT COUNT(*) 
     FROM PostHistory ph3 
     WHERE ph3.UserId = u.Id 
       AND ph3.PostHistoryTypeId IN (1,2,3,4,5,6)
       AND ph3.CreationDate > DATEADD('month', -1, CURRENT_TIMESTAMP)
    ) as RecentEdits,
    (SELECT AVG(p19.Score) 
     FROM Posts p19 
     WHERE p19.OwnerUserId = u.Id 
       AND p19.PostTypeId = 2 
       AND p19.ViewCount > 100
    ) as AvgScoreHighViewAnswers
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostLinks pl ON (pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) OR pl.RelatedPostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id))
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN Votes v ON u.Id = v.UserId
WHERE u.Reputation > 0
  AND u.CreationDate > '2008-01-01'
GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate, u.LastAccessDate
HAVING COUNT(DISTINCT p.Id) > 0
ORDER BY u.Reputation DESC
LIMIT 5000