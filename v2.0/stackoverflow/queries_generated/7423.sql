-- {"query": "7423.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1630} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Score > 0 THEN p.Id END) as HighScoreQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 0 THEN p.Id END) as HighScoreAnswers,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) as TotalQuestionViews,
    SUM(CASE WHEN p.PostTypeId = 2 THEN p.ViewCount ELSE 0 END) as TotalAnswerViews,
    MAX(p.Score) as MaxPostScore,
    AVG(p.Score) as AvgPostScore,
    COUNT(DISTINCT b.Id) as BadgesCount,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
    AVG(CAST(DATEDIFF(day, u.CreationDate, u.LastAccessDate) AS FLOAT)) as AvgDaysSinceRegistration,
    COUNT(DISTINCT c.Id) as CommentCount,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 
            AVG(CAST(p.Score AS FLOAT) * (CAST(p.ViewCount AS FLOAT) / CAST(NULLIF(p.ViewCount, 0) AS FLOAT)))
        ELSE 0 
    END as EngagementScore,
    STRING_AGG(DISTINCT t.TagName, ', ') as UserTags,
    FIRST_VALUE(p.Id) OVER (PARTITION BY u.Id ORDER BY p.CreationDate ASC) as FirstPostId,
    LAST_VALUE(p.Id) OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as LastPostId,
    DENSE_RANK() OVER (ORDER BY SUM(p.Score) DESC) as ReputationalRank,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 100 AND COUNT(DISTINCT p.Id) < 500 THEN 'Medium Contributor'
        WHEN COUNT(DISTINCT p.Id) >= 500 AND COUNT(DISTINCT p.Id) < 1000 THEN 'High Contributor'
        WHEN COUNT(DISTINCT p.Id) >= 1000 THEN 'Elite Contributor'
        ELSE 'Regular Contributor'
    END as ContributionTier,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Posts p2 
         WHERE p2.OwnerUserId = u.Id 
         AND p2.PostTypeId = 1 
         AND p2.ClosedDate IS NOT NULL), 0) as ClosedQuestions,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.UserId = u.Id 
         AND v.VoteTypeId IN (2,3) 
         AND v.PostId IN (
             SELECT p3.Id 
             FROM Posts p3 
             WHERE p3.OwnerUserId = u.Id 
             AND p3.PostTypeId = 1
         )), 0) as TotalVotesOnOwnQuestions,
    (SELECT COUNT(*) 
     FROM PostHistory ph 
     WHERE ph.UserId = u.Id 
     AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
     AND ph.PostId IN (
         SELECT p4.Id 
         FROM Posts p4 
         WHERE p4.OwnerUserId = u.Id
     )) as EditActivity,
    (SELECT AVG(CAST(p5.ViewCount AS FLOAT)) 
     FROM Posts p5 
     WHERE p5.OwnerUserId = u.Id 
     AND p5.PostTypeId = 1
    ) as AvgQuestionViewCount,
    COALESCE(
        (SELECT AVG(CAST(p6.Score AS FLOAT)) 
         FROM Posts p6 
         WHERE p6.OwnerUserId = u.Id 
         AND p6.PostTypeId = 2), 0) as AvgAnswerScore,
    RANK() OVER (ORDER BY COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) DESC) as QuestionRank,
    RANK() OVER (ORDER BY COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) DESC) as AnswerRank,
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM Posts p7 
            WHERE p7.OwnerUserId = u.Id 
            AND p7.PostTypeId = 1 
            AND p7.Score > 1000
        ) THEN 'HighlyVotedQuestionAuthor'
        ELSE 'RegularQuestionAuthor'
    END as QuestionAuthorStatus,
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM Badges b2 
            WHERE b2.UserId = u.Id 
            AND b2.Class = 1
        ) THEN 'HasGoldBadge'
        ELSE NULL
    END as HasGoldBadgeIndicator,
    (SELECT COUNT(*) 
     FROM PostHistory ph2 
     WHERE ph2.UserId = u.Id 
     AND ph2.PostHistoryTypeId = 15
    ) as ModerationActivity,
    (SELECT COUNT(*) 
     FROM Posts p8 
     WHERE p8.OwnerUserId = u.Id 
     AND p8.PostTypeId = 1 
     AND p8.AnswerCount > 0
    ) as QuestionsWithAnswers,
    (SELECT AVG(CAST(p9.ViewCount AS FLOAT)) 
     FROM Posts p9 
     WHERE p9.OwnerUserId = u.Id 
     AND p9.PostTypeId = 2
    ) as AvgAnswerViewCount
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN Comments c ON c.UserId = u.Id
LEFT JOIN PostHistory ph ON ph.UserId = u.Id
LEFT JOIN (
    SELECT DISTINCT PostId, TagName 
    FROM Posts p10 
    JOIN (
        SELECT Id, unnest(string_to_array(Tags, '<>')) as TagName
        FROM Posts 
        WHERE Tags IS NOT NULL
    ) AS t ON t.Id = p10.Id
) AS t ON t.PostId = p.Id
WHERE u.Reputation > 1000 
    AND u.CreationDate > '2010-01-01 00:00:00'
    AND (
        CASE 
            WHEN u.AccountId IS NOT NULL THEN u.AccountId IN (
                SELECT AccountId 
                FROM Users u2 
                WHERE u2.Id = u.Id
            )
            ELSE 1 = 1
        END
    )
    AND u.Id IN (
        SELECT DISTINCT UserId 
        FROM Posts p11 
        WHERE p11.OwnerUserId IS NOT NULL
        GROUP BY UserId 
        HAVING COUNT(DISTINCT Id) > 50
    )
GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.AccountId
HAVING COUNT(DISTINCT p.Id) > 0 
    AND (
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 10
        OR 
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 50
    )
ORDER BY SUM(p.Score) DESC, COUNT(DISTINCT p.Id) DESC
LIMIT 1000;