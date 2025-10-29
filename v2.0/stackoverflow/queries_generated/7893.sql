-- {"query": "7893.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2286} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT b.Id) as Badges,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) as UpVotes,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) as DownVotes,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END), 0) as Favorites,
    AVG(COALESCE(p.Score, 0)) as AvgPostScore,
    MAX(p.CreationDate) as LatestPostDate,
    STRING_AGG(DISTINCT t.TagName, ', ' ORDER BY t.TagName) as TagList,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1 AND Score > 100) as HighScoringQuestions,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 2 AND Score > 100) as HighScoringAnswers,
    (SELECT COUNT(*) FROM Comments WHERE UserId = u.Id) as TotalComments,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)) as EditCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (10, 11, 12, 13)) as ModActionCount,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 
            COALESCE(SUM(p.Score), 0) / COUNT(DISTINCT p.Id)
        ELSE 0 
    END as ScorePerPost,
    ROW_NUMBER() OVER (ORDER BY SUM(COALESCE(p.Score, 0)) DESC) as RankByScore,
    NTILE(100) OVER (ORDER BY SUM(COALESCE(p.Score, 0)) DESC) as Percentile,
    LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) - u.Reputation as ReputationDelta,
    DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostRank,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM Posts p2 
            WHERE p2.OwnerUserId = u.Id 
            AND p2.CreationDate > u.CreationDate 
            AND p2.Score > 0
        ) THEN 'Active' 
        ELSE 'Inactive' 
    END as UserStatus,
    CONCAT(
        'User #', 
        u.Id, 
        ' (', 
        COALESCE(u.DisplayName, 'Anonymous'), 
        ') with ', 
        COUNT(DISTINCT p.Id), 
        ' posts, ', 
        COUNT(DISTINCT b.Id), 
        ' badges, and ', 
        COALESCE(SUM(p.Score), 0), 
        ' total score'
    ) as UserProfileSummary
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Votes v ON u.Id = v.UserId
LEFT JOIN (
    SELECT DISTINCT PostId, TagName 
    FROM Posts p2 
    JOIN UNNEST(string_to_array(SUBSTRING(p2.Tags, 2, LENGTH(p2.Tags) - 2), '><')) AS TagName
    WHERE p2.Tags IS NOT NULL AND p2.Tags != ''
) t ON t.PostId = p.Id
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
WHERE 
    u.CreationDate >= '2010-01-01' 
    AND u.CreationDate <= '2023-12-31'
    AND (
        p.PostTypeId IN (1, 2) 
        OR p IS NULL
    )
    AND (
        (p.CreationDate >= '2020-01-01' AND p.CreationDate <= '2023-12-31')
        OR p.CreationDate IS NULL
    )
GROUP BY 
    u.Id, 
    u.DisplayName, 
    u.Reputation,
    u.CreationDate
HAVING 
    COUNT(DISTINCT p.Id) > 0
    AND COALESCE(SUM(p.Score), 0) >= 0
    AND COUNT(DISTINCT b.Id) >= 0
    AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) >= 0
    AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) >= 0
ORDER BY 
    SUM(COALESCE(p.Score, 0)) DESC,
    COUNT(DISTINCT p.Id) DESC,
    u.Reputation DESC
LIMIT 1000
EXCEPT
SELECT 
    u2.Id as UserId,
    u2.DisplayName,
    u2.Reputation,
    COUNT(DISTINCT p2.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p2.PostTypeId = 1 THEN p2.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p2.PostTypeId = 2 THEN p2.Id END) as Answers,
    COUNT(DISTINCT b2.Id) as Badges,
    COALESCE(SUM(CASE WHEN v2.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) as UpVotes,
    COALESCE(SUM(CASE WHEN v2.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) as DownVotes,
    COALESCE(SUM(CASE WHEN v2.VoteTypeId = 5 THEN 1 ELSE 0 END), 0) as Favorites,
    AVG(COALESCE(p2.Score, 0)) as AvgPostScore,
    MAX(p2.CreationDate) as LatestPostDate,
    STRING_AGG(DISTINCT t2.TagName, ', ' ORDER BY t2.TagName) as TagList,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u2.Id AND PostTypeId = 1 AND Score > 100) as HighScoringQuestions,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u2.Id AND PostTypeId = 2 AND Score > 100) as HighScoringAnswers,
    (SELECT COUNT(*) FROM Comments WHERE UserId = u2.Id) as TotalComments,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u2.Id AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)) as EditCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u2.Id AND ph.PostHistoryTypeId IN (10, 11, 12, 13)) as ModActionCount,
    CASE 
        WHEN COUNT(DISTINCT p2.Id) > 0 THEN 
            COALESCE(SUM(p2.Score), 0) / COUNT(DISTINCT p2.Id)
        ELSE 0 
    END as ScorePerPost,
    ROW_NUMBER() OVER (ORDER BY SUM(COALESCE(p2.Score, 0)) DESC) as RankByScore,
    NTILE(100) OVER (ORDER BY SUM(COALESCE(p2.Score, 0)) DESC) as Percentile,
    LAG(u2.Reputation, 1, 0) OVER (ORDER BY u2.Reputation DESC) - u2.Reputation as ReputationDelta,
    DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p2.Id) DESC) as PostRank,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM Posts p3 
            WHERE p3.OwnerUserId = u2.Id 
            AND p3.CreationDate > u2.CreationDate 
            AND p3.Score > 0
        ) THEN 'Active' 
        ELSE 'Inactive' 
    END as UserStatus,
    CONCAT(
        'User #', 
        u2.Id, 
        ' (', 
        COALESCE(u2.DisplayName, 'Anonymous'), 
        ') with ', 
        COUNT(DISTINCT p2.Id), 
        ' posts, ', 
        COUNT(DISTINCT b2.Id), 
        ' badges, and ', 
        COALESCE(SUM(p2.Score), 0), 
        ' total score'
    ) as UserProfileSummary
FROM Users u2
LEFT JOIN Posts p2 ON u2.Id = p2.OwnerUserId
LEFT JOIN Badges b2 ON u2.Id = b2.UserId
LEFT JOIN Votes v2 ON u2.Id = v2.UserId
LEFT JOIN (
    SELECT DISTINCT PostId, TagName 
    FROM Posts p4 
    JOIN UNNEST(string_to_array(SUBSTRING(p4.Tags, 2, LENGTH(p4.Tags) - 2), '><')) AS TagName
    WHERE p4.Tags IS NOT NULL AND p4.Tags != ''
) t2 ON t2.PostId = p2.Id
LEFT JOIN PostHistory ph2 ON u2.Id = ph2.UserId
WHERE 
    u2.CreationDate >= '2010-01-01' 
    AND u2.CreationDate <= '2023-12-31'
    AND (
        p2.PostTypeId IN (1, 2) 
        OR p2 IS NULL
    )
    AND (
        (p2.CreationDate >= '2020-01-01' AND p2.CreationDate <= '2023-12-31')
        OR p2.CreationDate IS NULL
    )
GROUP BY 
    u2.Id, 
    u2.DisplayName, 
    u2.Reputation,
    u2.CreationDate
HAVING 
    COUNT(DISTINCT p2.Id) > 0
    AND COALESCE(SUM(p2.Score), 0) >= 0
    AND COUNT(DISTINCT b2.Id) >= 0
    AND COUNT(DISTINCT CASE WHEN p2.PostTypeId = 1 THEN p2.Id END) >= 0
    AND COUNT(DISTINCT CASE WHEN p2.PostTypeId = 2 THEN p2.Id END) >= 0
ORDER BY 
    SUM(COALESCE(p2.Score, 0)) DESC,
    COUNT(DISTINCT p2.Id) DESC,
    u2.Reputation DESC
LIMIT 1000;