-- {"query": "7861.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1144} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT b.Id) as Badges,
    COALESCE(SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN v.VoteTypeId ELSE 0 END), 0) as TotalVotes,
    STRING_AGG(DISTINCT t.TagName, ',') as UserTags,
    AVG(p.Score) as AvgPostScore,
    MAX(p.ViewCount) as MaxViews,
    COUNT(DISTINCT ph.Id) as EditHistoryCount,
    COUNT(DISTINCT c.Id) as Comments,
    (SELECT COUNT(*) 
     FROM Posts p2 
     WHERE p2.OwnerUserId = u.Id 
     AND p2.PostTypeId = 1 
     AND p2.ClosedDate IS NOT NULL) as ClosedQuestions,
    ROW_NUMBER() OVER (ORDER BY SUM(p.Score) DESC) as UserRank,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 1000 THEN 'Elite'
        WHEN COUNT(DISTINCT p.Id) > 500 THEN 'Veteran'
        WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Regular'
        ELSE 'Newbie'
    END as UserLevel,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Posts p3 
         WHERE p3.OwnerUserId = u.Id 
         AND p3.PostTypeId = 1 
         AND p3.Score > 100), 0) as HighScoreQuestions,
    LAG(u.Reputation, 1, 0) OVER (ORDER BY u.CreationDate) as PreviousReputation,
    (u.Reputation - LAG(u.Reputation, 1, 0) OVER (ORDER BY u.CreationDate)) as ReputationChange,
    DENSE_RANK() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) as ReputationRankByLocation,
    PERCENT_RANK() OVER (ORDER BY u.Reputation) as ReputationPercentile,
    NTILE(10) OVER (ORDER BY u.Reputation) as ReputationDecile,
    CONCAT('User_', u.Id) as UserIdentifier,
    CASE WHEN u.WebsiteUrl IS NOT NULL THEN 'HasWebsite' ELSE 'NoWebsite' END as WebsiteStatus,
    COALESCE(
        (SELECT AVG(Score) 
         FROM Posts p4 
         WHERE p4.OwnerUserId = u.Id 
         AND p4.PostTypeId = 1), 0) as AvgQuestionScore
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Votes v ON u.Id = v.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN (
    SELECT 
        u2.Id as UserId,
        STRING_AGG(t2.TagName, ',') as TagName
    FROM Users u2
    JOIN Posts p2 ON u2.Id = p2.OwnerUserId
    JOIN (
        SELECT DISTINCT PostId, unnest(string_to_array(Tags, '><')) as TagName
        FROM Posts 
        WHERE Tags IS NOT NULL AND Tags != ''
    ) t2 ON p2.Id = t2.PostId
    WHERE p2.PostTypeId = 1
    GROUP BY u2.Id
) t ON u.Id = t.UserId
WHERE u.CreationDate >= '2010-01-01'
AND (u.Reputation > 100 OR u.Id IN (SELECT DISTINCT UserId FROM Badges WHERE Date >= '2010-01-01'))
GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, u.WebsiteUrl
HAVING COUNT(DISTINCT p.Id) > 0
ORDER BY SUM(p.Score) DESC
LIMIT 1000
UNION ALL
SELECT 
    0 as UserId,
    'TOTAL' as DisplayName,
    SUM(Reputation) as Reputation,
    COUNT(*) as TotalPosts,
    COUNT(*) as Questions,
    COUNT(*) as Answers,
    COUNT(*) as Badges,
    COUNT(*) as TotalVotes,
    STRING_AGG(DISTINCT TagName, ',') as UserTags,
    AVG(Reputation) as AvgPostScore,
    MAX(Reputation) as MaxViews,
    COUNT(*) as EditHistoryCount,
    COUNT(*) as Comments,
    COUNT(*) as ClosedQuestions,
    0 as UserRank,
    'SUMMARY' as UserLevel,
    COUNT(*) as HighScoreQuestions,
    0 as PreviousReputation,
    0 as ReputationChange,
    0 as ReputationRankByLocation,
    0 as ReputationPercentile,
    0 as ReputationDecile,
    'TOTAL' as UserIdentifier,
    'AllUsers' as WebsiteStatus,
    AVG(Reputation) as AvgQuestionScore
FROM Users u
LEFT JOIN (
    SELECT DISTINCT PostId, unnest(string_to_array(Tags, '><')) as TagName
    FROM Posts 
    WHERE Tags IS NOT NULL AND Tags != ''
) t ON TRUE
WHERE u.CreationDate >= '2010-01-01'