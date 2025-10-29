-- {"query": "7273.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2583} 
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS QuestionsWithAcceptedAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.OwnerUserId = u.Id THEN p.Id END) AS AnswersToOwnQuestions,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Tags END) AS UniqueTagUsage,
    STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Tags END, '; ') AS AllQuestionTags,
    COUNT(DISTINCT b.Id) AS BadgesCount,
    STRING_AGG(DISTINCT b.Name, ', ') AS BadgeNames,
    MAX(CASE WHEN b.Class = 1 THEN b.Date ELSE NULL END) AS LastGoldBadgeDate,
    MAX(CASE WHEN b.Class = 2 THEN b.Date ELSE NULL END) AS LastSilverBadgeDate,
    MAX(CASE WHEN b.Class = 3 THEN b.Date ELSE NULL END) AS LastBronzeBadgeDate,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS Upvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS Downvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) AS Favorites,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 8 THEN v.Id END) AS BountyStarts,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 9 THEN v.Id END) AS BountyCloses,
    COUNT(DISTINCT c.Id) AS CommentsCount,
    STRING_AGG(DISTINCT c.Text, ' || ') AS CommentTexts,
    COUNT(DISTINCT ph.Id) AS PostHistoryEntries,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 12, 14, 16) THEN ph.Id END) AS PostStatusChanges,
    COUNT(DISTINCT pl.Id) AS PostLinks,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.Id END) AS DuplicateLinks,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 1 THEN pl.Id END) AS LinkedPosts,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Posts p2 
         WHERE p2.OwnerUserId = u.Id 
         AND p2.PostTypeId = 1 
         AND p2.CreationDate > '2020-01-01'
         AND p2.Score > 100),
        0
    ) AS HighScoreQuestions2020,
    COALESCE(
        (SELECT AVG(Score) 
         FROM Posts p3 
         WHERE p3.OwnerUserId = u.Id 
         AND p3.PostTypeId = 2 
         AND p3.CreationDate > '2022-01-01'),
        0
    ) AS AvgAnswerScore2022,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Posts p4 
         WHERE p4.OwnerUserId = u.Id 
         AND p4.PostTypeId = 1 
         AND p4.AnswerCount >= 5),
        0
    ) AS QuestionsWithFiveOrMoreAnswers,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Comments c2 
         WHERE c2.UserId = u.Id 
         AND c2.CreationDate > '2021-01-01'),
        0
    ) AS CommentsIn2021,
    RANK() OVER (ORDER BY u.Reputation DESC) AS UserReputationRank,
    PERCENT_RANK() OVER (ORDER BY u.Reputation) AS ReputationPercentile,
    DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostCountRank,
    ROW_NUMBER() OVER (ORDER BY u.CreationDate ASC) AS EarlyUserNumber,
    LAG(u.DisplayName, 1) OVER (ORDER BY u.Reputation DESC) AS NextHigherReputationUser,
    LEAD(u.DisplayName, 1) OVER (ORDER BY u.Reputation DESC) AS NextLowerReputationUser,
    CASE 
        WHEN u.Reputation >= 10000 THEN 'Elite'
        WHEN u.Reputation >= 5000 THEN 'Veteran'
        WHEN u.Reputation >= 1000 THEN 'Contributor'
        ELSE 'Newbie'
    END AS UserTier,
    CASE 
        WHEN u.Reputation >= 10000 AND COUNT(DISTINCT p.Id) >= 500 THEN 'Hall of Fame'
        WHEN u.Reputation >= 1000 AND COUNT(DISTINCT p.Id) >= 100 THEN 'High Achiever'
        ELSE 'Regular'
    END AS UserAchievement,
    (SELECT COUNT(*) 
     FROM Posts p5 
     WHERE p5.OwnerUserId = u.Id 
     AND p5.PostTypeId = 2 
     AND p5.Score > 10 
     AND p5.CreationDate > '2020-01-01') AS HighScoreAnswerCount2020,
    ROUND(
        (COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0)), 2
    ) AS QuestionPercentage,
    ROUND(
        (COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0)), 2
    ) AS AnswerPercentage,
    ROUND(
        (COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) * 100.0 / NULLIF(COUNT(v.Id), 0)), 2
    ) AS UpvotePercentage,
    ROUND(
        (COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) * 100.0 / NULLIF(COUNT(v.Id), 0)), 2
    ) AS DownvotePercentage,
    ROUND(
        (COUNT(CASE WHEN b.Class = 1 THEN 1 END) * 100.0 / NULLIF(COUNT(b.Id), 0)), 2
    ) AS GoldBadgePercentage,
    (SELECT COUNT(DISTINCT ph2.PostHistoryTypeId) 
     FROM PostHistory ph2 
     WHERE ph2.UserId = u.Id 
     AND ph2.CreationDate > '2021-01-01') AS RecentPostHistoryTypesCount,
    (SELECT MAX(Tags) 
     FROM Posts p6 
     WHERE p6.OwnerUserId = u.Id 
     AND p6.PostTypeId = 1 
     AND p6.Tags IS NOT NULL) AS MaxTagString,
    (SELECT COUNT(*) 
     FROM Votes v2 
     WHERE v2.UserId = u.Id 
     AND v2.CreationDate BETWEEN '2020-01-01' AND '2020-12-31' 
     AND v2.VoteTypeId = 2) AS Upvotes2020,
    (SELECT COUNT(*) 
     FROM Votes v3 
     WHERE v3.UserId = u.Id 
     AND v3.CreationDate BETWEEN '2020-01-01' AND '2020-12-31' 
     AND v3.VoteTypeId = 3) AS Downvotes2020,
    (SELECT STRING_AGG('"' || Name || '"', ', ') 
     FROM Badges b2 
     WHERE b2.UserId = u.Id 
     AND b2.Date > '2021-01-01' 
     AND Class = 1) AS RecentGoldBadgesNames,
    (SELECT SUM(Score) 
     FROM Votes v4 
     WHERE v4.UserId = u.Id 
     AND v4.VoteTypeId IN (2, 3)) AS TotalVoteScore,
    (SELECT AVG(Score) 
     FROM Comments c3 
     WHERE c3.UserId = u.Id) AS AvgCommentScore,
    (SELECT COUNT(*) 
     FROM Posts p7 
     WHERE p7.OwnerUserId = u.Id 
     AND p7.PostTypeId = 1 
     AND p7.ViewCount > 1000) AS HighlyViewedQuestions,
    (SELECT COUNT(*) 
     FROM Posts p8 
     WHERE p8.OwnerUserId = u.Id 
     AND p8.PostTypeId = 2 
     AND p8.ViewCount > 500) AS HighlyViewedAnswers,
    (SELECT COUNT(*) 
     FROM PostLinks pl2 
     WHERE pl2.PostId IN (
         SELECT Id 
         FROM Posts p9 
         WHERE p9.OwnerUserId = u.Id 
         AND p9.PostTypeId = 1
     ) 
     AND pl2.LinkTypeId = 3) AS DuplicateLinksFromOwnQuestions,
    (SELECT COUNT(DISTINCT p10.ParentId) 
     FROM Posts p10 
     WHERE p10.OwnerUserId = u.Id 
     AND p10.PostTypeId = 2 
     AND p10.ParentId IS NOT NULL) AS AnswersToOtherUsersQuestions,
    (SELECT COUNT(*) 
     FROM Posts p11 
     WHERE p11.OwnerUserId = u.Id 
     AND p11.PostTypeId = 1 
     AND p11.AnswerCount = 0) AS UnansweredQuestions,
    (SELECT COUNT(*) 
     FROM Posts p12 
     WHERE p12.OwnerUserId = u.Id 
     AND p12.PostTypeId = 2 
     AND p12.AcceptedAnswerId IS NULL) AS UnacceptedAnswers,
    (SELECT STRING_AGG(
        CAST(p13.Id AS VARCHAR) || ':' || p13.Title, 
        ';'
    ) 
     FROM Posts p13 
     WHERE p13.OwnerUserId = u.Id 
     AND p13.PostTypeId = 1 
     AND p13.Tags IS NOT NULL 
     AND LENGTH(p13.Tags) > 100) AS LongTaggedQuestions,
    (SELECT STRING_AGG(
        CAST(b3.Name AS VARCHAR) || ':' || CAST(b3.Date AS VARCHAR), 
        '|'
    ) 
     FROM Badges b3 
     WHERE b3.UserId = u.Id 
     AND b3.Date > '2020-01-01' 
     AND b3.Class = 3) AS RecentBronzeBadgesWithDates
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON c.UserId = u.Id
LEFT JOIN Votes v ON v.UserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN PostHistory ph ON ph.UserId = u.Id
LEFT JOIN PostLinks pl ON pl.PostId IN (
    SELECT Id FROM Posts p14 WHERE p14.OwnerUserId = u.Id
)
WHERE u.Reputation > 100
GROUP BY 
    u.Id, 
    u.DisplayName, 
    u.Reputation,
    u.CreationDate
HAVING 
    COUNT(DISTINCT p.Id) > 0
    OR COUNT(DISTINCT b.Id) > 0
    OR COUNT(DISTINCT c.Id) > 0
    OR COUNT(DISTINCT v.Id) > 0
    OR COUNT(DISTINCT ph.Id) > 0
    OR COUNT(DISTINCT pl.Id) > 0
ORDER BY 
    u.Reputation DESC,
    COUNT(DISTINCT p.Id) DESC
LIMIT 100;