-- {"query": "7015.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2248} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) as QuestionsWithAcceptedAnswers,
    COUNT(DISTINCT b.Id) as Badges,
    COUNT(DISTINCT c.Id) as Comments,
    COUNT(DISTINCT ph.Id) as PostHistoryEntries,
    COUNT(DISTINCT pl.Id) as PostLinks,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as TotalQuestionScore,
    SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as TotalAnswerScore,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) as AvgQuestionScore,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) as AvgAnswerScore,
    MAX(p.CreationDate) as LatestPostDate,
    MIN(p.CreationDate) as FirstPostDate,
    DATEDIFF(CURRENT_TIMESTAMP, MIN(p.CreationDate)) as DaysActive,
    COALESCE(SUBSTRING(p.Title, 1, 50), '') as SampleTitle,
    STRING_AGG(DISTINCT t.TagName, ', ') as UserTags,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Highly Active'
        WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Active'
        WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Regular'
        ELSE 'Newbie'
    END as ActivityLevel,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1 AND Score > 0) as PositiveQuestions,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 2 AND Score > 0) as PositiveAnswers,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1 AND CreationDate >= DATEADD(YEAR, -1, CURRENT_TIMESTAMP)) as RecentQuestions,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 2 AND CreationDate >= DATEADD(YEAR, -1, CURRENT_TIMESTAMP)) as RecentAnswers,
    (SELECT STRING_AGG(Name, ', ') FROM Badges WHERE UserId = u.Id AND Class = 1) as GoldBadges,
    (SELECT STRING_AGG(Name, ', ') FROM Badges WHERE UserId = u.Id AND Class = 2) as SilverBadges,
    (SELECT STRING_AGG(Name, ', ') FROM Badges WHERE UserId = u.Id AND Class = 3) as BronzeBadges,
    ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostRank,
    RANK() OVER (ORDER BY SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) DESC) as QuestionScoreRank,
    DENSE_RANK() OVER (ORDER BY SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) DESC) as AnswerScoreRank,
    PERCENT_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id)) as PostPercentile,
    LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation) as PreviousReputation,
    LEAD(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation) as NextReputation,
    NTILE(100) OVER (ORDER BY u.Reputation) as ReputationQuintile,
    CASE 
        WHEN u.Reputation >= 1000000 THEN 'Millionaire'
        WHEN u.Reputation >= 100000 THEN 'HundredThousander'
        WHEN u.Reputation >= 10000 THEN 'TenThousander'
        WHEN u.Reputation >= 1000 THEN 'Thousander'
        ELSE 'Commoner'
    END as ReputationTier,
    NULLIF(u.WebsiteUrl, '') as WebsiteUrl,
    NULLIF(u.Location, '') as Location,
    NULLIF(u.AboutMe, '') as AboutMe,
    CASE 
        WHEN u.Views > 1000000 THEN 'Viral'
        WHEN u.Views > 100000 THEN 'Popular'
        WHEN u.Views > 10000 THEN 'Notable'
        WHEN u.Views > 1000 THEN 'Recognized'
        ELSE 'Unknown'
    END as UserVisibility,
    (SELECT COUNT(*) FROM Votes WHERE UserId = u.Id AND VoteTypeId IN (2, 3)) as TotalVotes,
    (SELECT COUNT(*) FROM Votes WHERE UserId = u.Id AND VoteTypeId = 2) as Upvotes,
    (SELECT COUNT(*) FROM Votes WHERE UserId = u.Id AND VoteTypeId = 3) as Downvotes,
    (SELECT COUNT(*) FROM Votes WHERE UserId = u.Id AND VoteTypeId = 5) as Favorites,
    (SELECT COUNT(*) FROM PostLinks WHERE PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) AND LinkTypeId = 3) as DuplicateLinks,
    (SELECT COUNT(*) FROM PostLinks WHERE RelatedPostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) AND LinkTypeId = 3) as DuplicateOfLinks,
    CONCAT('User-', u.Id, '-', u.DisplayName) as UserIdentifier,
    CASE 
        WHEN EXISTS(SELECT 1 FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1 AND Score < 0) THEN 'HasNegativeQuestions'
        WHEN EXISTS(SELECT 1 FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 2 AND Score < 0) THEN 'HasNegativeAnswers'
        ELSE 'NoNegativePosts'
    END as NegativePostStatus,
    (SELECT COUNT(*) FROM PostHistory WHERE UserId = u.Id AND PostHistoryTypeId IN (4, 5, 6)) as EditCounts,
    (SELECT COUNT(*) FROM PostHistory WHERE UserId = u.Id AND PostHistoryTypeId IN (10, 11, 12)) as CloseReopenDeleteCounts,
    (SELECT MAX(CreationDate) FROM PostHistory WHERE UserId = u.Id) as LatestActivity,
    (SELECT MIN(CreationDate) FROM PostHistory WHERE UserId = u.Id) as FirstActivity,
    (DATEDIFF(CURRENT_TIMESTAMP, (SELECT MIN(CreationDate) FROM PostHistory WHERE UserId = u.Id))) as ActivityDurationDays,
    (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1) as AvgQuestionScoreWithNULLs,
    (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 2) as AvgAnswerScoreWithNULLs,
    (SELECT MAX(Score) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1) as MaxQuestionScore,
    (SELECT MAX(Score) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 2) as MaxAnswerScore,
    COALESCE((SELECT TOP 1 PostTypeId FROM Posts WHERE OwnerUserId = u.Id ORDER BY CreationDate DESC), 0) as LatestPostType,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND CommentCount > 0) as PostsHavingComments,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND FavoriteCount > 0) as PostsHavingFavorites,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND ViewCount > 100) as HighlyViewedPosts,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND ViewCount > 1000) as VeryHighlyViewedPosts,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND Score BETWEEN 1 AND 5) as LowScorePosts,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND Score BETWEEN 6 AND 50) as MediumScorePosts,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND Score > 50) as HighScorePosts
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN PostLinks pl ON u.Id IN (SELECT OwnerUserId FROM Posts WHERE Id IN (pl.PostId, pl.RelatedPostId))
LEFT JOIN (
    SELECT PostId, STRING_AGG(TagName, ', ') as TagName
    FROM (
        SELECT p.Id as PostId, t.TagName
        FROM Posts p
        INNER JOIN (
            SELECT Id, 
                   LTRIM(RTRIM(value)) as TagName
            FROM Posts p
            CROSS APPLY STRING_SPLIT(p.Tags, '<')
            WHERE p.Tags IS NOT NULL AND p.Tags != ''
        ) t ON p.Id = t.Id
    ) tt
    GROUP BY PostId
) t ON p.Id = t.PostId
WHERE u.CreationDate >= DATEADD(YEAR, -2, CURRENT_TIMESTAMP)
  AND (u.Reputation > 0 OR u.Views > 0 OR u.UpVotes > 0)
  AND NOT EXISTS(
    SELECT 1 
    FROM Posts p2 
    WHERE p2.OwnerUserId = u.Id 
      AND p2.PostTypeId IN (3, 4, 5, 6, 7, 8)
  )
GROUP BY 
    u.Id, 
    u.DisplayName, 
    u.Reputation, 
    u.WebsiteUrl, 
    u.Location, 
    u.AboutMe, 
    u.Views, 
    u.UpVotes, 
    u.DownVotes
HAVING 
    COUNT(DISTINCT p.Id) > 0
    AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0
    AND EXISTS(
        SELECT 1 
        FROM Posts p3 
        WHERE p3.OwnerUserId = u.Id 
          AND p3.Score >= 0
    )
ORDER BY 
    COUNT(DISTINCT p.Id) DESC,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) DESC,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) DESC
OFFSET 0 ROWS
FETCH NEXT 1000 ROWS ONLY;