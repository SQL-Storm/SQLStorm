-- {"query": "7756.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2182} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT b.Id) as Badges,
    AVG(CAST(p.Score as FLOAT)) as AvgScore,
    MAX(p.ViewCount) as MaxViews,
    STRING_AGG(DISTINCT p.Title, ', ') as PostTitles,
    STRING_AGG(DISTINCT t.TagName, ', ') as Tags,
    COALESCE(
        (SELECT STRING_AGG(CAST(ph.PostHistoryTypeId as VARCHAR), ', ')
         FROM PostHistory ph
         WHERE ph.PostId = p.Id
         AND ph.CreationDate > '2023-01-01'
         AND ph.CreationDate < '2024-01-01'
         AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)),
        'No recent edits'
    ) as RecentEdits,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
        THEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) * 100.0 / COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END)
        ELSE 0 
    END as AnswerToQuestionRatio,
    (SELECT COUNT(*) 
     FROM Votes v 
     WHERE v.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) 
     AND v.VoteTypeId IN (2, 3)
     AND v.CreationDate > '2023-01-01') as NetVotes,
    (SELECT COUNT(*) 
     FROM Comments c 
     WHERE c.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)) as CommentCount,
    (SELECT COUNT(DISTINCT ph.PostId) 
     FROM PostHistory ph 
     WHERE ph.UserId = u.Id 
     AND ph.PostHistoryTypeId = 14) as PostLockedCount,
    (SELECT STRING_AGG(CONCAT('Q', p1.Id, ':', p1.Title), ' | ') 
     FROM Posts p1 
     INNER JOIN PostLinks pl ON p1.Id = pl.PostId 
     WHERE pl.RelatedPostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)
     AND pl.LinkTypeId = 1) as LinkedQuestions,
    LAG(COUNT(DISTINCT p.Id)) OVER (ORDER BY u.CreationDate) as PrevUserPosts,
    DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
    NTILE(100) OVER (ORDER BY u.Reputation) as ReputationPercentile,
    ROW_NUMBER() OVER (PARTITION BY u.AccountId ORDER BY u.CreationDate) as AccountUserRank,
    CASE 
        WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl != ''
        THEN 'Has Website'
        ELSE 'No Website'
    END as WebsiteStatus,
    CASE 
        WHEN u.Location IS NOT NULL AND u.Location != '' AND u.Location != ' '
        THEN 'Has Location'
        ELSE 'No Location'
    END as LocationStatus,
    (SELECT COUNT(*) 
     FROM Badges b2 
     WHERE b2.UserId = u.Id 
     AND b2.Date > '2023-01-01') as RecentBadges,
    (SELECT STRING_AGG(DISTINCT bt.Name, ', ') 
     FROM Badges b3 
     INNER JOIN Posts p2 ON b3.Id = p2.Id 
     WHERE b3.UserId = u.Id 
     AND b3.Date > '2023-01-01'
     AND p2.PostTypeId = 1) as RecentQuestionBadges,
    (SELECT AVG(Score) 
     FROM Posts p3 
     WHERE p3.OwnerUserId = u.Id 
     AND p3.PostTypeId = 1
     AND p3.CreationDate > '2023-01-01') as RecentQuestionAvgScore,
    (SELECT STRING_AGG(
        CASE 
            WHEN c.Comment LIKE '%help%' THEN 'Help Request'
            WHEN c.Comment LIKE '%thanks%' THEN 'Thanks'
            ELSE 'Other'
        END, ', ')
     FROM Comments c
     WHERE c.UserId = u.Id
     AND c.CreationDate > '2023-01-01') as CommentCategoryTrends,
    (SELECT COUNT(DISTINCT p4.Id) 
     FROM Posts p4 
     INNER JOIN PostLinks pl2 ON p4.Id = pl2.PostId 
     WHERE pl2.RelatedPostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)
     AND pl2.LinkTypeId = 3) as DuplicateLinkCount,
    (SELECT COUNT(*) 
     FROM Votes v2 
     WHERE v2.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) 
     AND v2.VoteTypeId = 5) as FavoriteCount,
    (SELECT COUNT(DISTINCT ph2.PostId) 
     FROM PostHistory ph2 
     WHERE ph2.UserId = u.Id 
     AND ph2.PostHistoryTypeId IN (10, 11, 12, 13)) as PostActionCount,
    CASE 
        WHEN u.Reputation > 10000 AND u.Views > 5000 THEN 'High Engagement'
        WHEN u.Reputation > 5000 AND u.Views > 2000 THEN 'Moderate Engagement'
        ELSE 'Low Engagement'
    END as EngagementLevel,
    (SELECT COUNT(DISTINCT c2.PostId) 
     FROM Comments c2 
     WHERE c2.UserId = u.Id 
     AND c2.CreationDate > '2023-01-01'
     AND c2.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)) as UserCommentsOnOwnPosts,
    (SELECT STRING_AGG(p5.Title, ' | ') 
     FROM Posts p5 
     WHERE p5.OwnerUserId = u.Id 
     AND p5.CreationDate > '2023-01-01'
     AND p5.PostTypeId = 1
     ORDER BY p5.Score DESC
     LIMIT 5) as Top5RecentQuestions,
    (SELECT COUNT(DISTINCT p6.Id) 
     FROM Posts p6 
     WHERE p6.OwnerUserId = u.Id 
     AND p6.CreationDate > '2023-01-01'
     AND (p6.CommentCount > 10 OR p6.ViewCount > 1000)) as HighTrafficPosts,
    (SELECT MAX(ph3.CreationDate) 
     FROM PostHistory ph3 
     WHERE ph3.UserId = u.Id 
     AND ph3.PostHistoryTypeId IN (1, 2, 3)) as LastActivityDate,
    (SELECT COUNT(DISTINCT p7.Id) 
     FROM Posts p7 
     INNER JOIN Votes v3 ON p7.Id = v3.PostId 
     WHERE p7.OwnerUserId = u.Id 
     AND v3.VoteTypeId = 2 
     AND v3.CreationDate > '2023-01-01') as UpvotesReceivedCount,
    (SELECT AVG(v4.BountyAmount) 
     FROM Votes v4 
     WHERE v4.UserId = u.Id 
     AND v4.VoteTypeId = 8 
     AND v4.CreationDate > '2023-01-01') as AvgBountyAmount,
    (SELECT COUNT(DISTINCT p8.Id) 
     FROM Posts p8 
     WHERE p8.OwnerUserId = u.Id 
     AND p8.ParentId IS NULL
     AND p8.PostTypeId = 1
     AND p8.CreationDate > '2023-01-01') as NewQuestionsCount,
    (SELECT COUNT(DISTINCT pl3.Id) 
     FROM PostLinks pl3 
     WHERE pl3.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)
     AND pl3.LinkTypeId = 3
     AND pl3.CreationDate > '2023-01-01') as DuplicateLinkCountRecent,
    (SELECT STRING_AGG(CONCAT('Tag:', t2.TagName, ' Count:', t2.Count), ' | ') 
     FROM Tags t2 
     WHERE t2.Id IN (
         SELECT DISTINCT p9.Id 
         FROM Posts p9 
         WHERE p9.OwnerUserId = u.Id 
         AND p9.Tags IS NOT NULL 
         AND p9.Tags != ''
     )) as AssociatedTags,
    (SELECT COUNT(DISTINCT p10.Id) 
     FROM Posts p10 
     WHERE p10.OwnerUserId = u.Id 
     AND p10.CreationDate > '2023-01-01'
     AND p10.PostTypeId IN (1, 2)
     AND p10.Score > 10) as HighScorePosts
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN Tags t ON t.Id IN (
    SELECT DISTINCT p11.Id 
    FROM Posts p11 
    WHERE p11.OwnerUserId = u.Id 
    AND p11.Tags IS NOT NULL 
    AND p11.Tags != ''
)
WHERE u.CreationDate >= '2022-01-01'
AND u.CreationDate < '2024-01-01'
AND (u.Reputation > 500 OR u.Views > 100)
GROUP BY u.Id, u.DisplayName, u.Reputation, u.WebsiteUrl, u.Location, u.AccountId, u.CreationDate, u.Views
HAVING COUNT(DISTINCT p.Id) > 0
ORDER BY u.Reputation DESC, COUNT(DISTINCT p.Id) DESC
LIMIT 1000;