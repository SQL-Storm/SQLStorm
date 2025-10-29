-- {"query": "7698.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1339} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT b.Id) as Badges,
    COALESCE(SUM(p.Score), 0) as TotalScore,
    COALESCE(AVG(p.Score), 0) as AverageScore,
    MAX(p.CreationDate) as LatestPostDate,
    STRING_AGG(DISTINCT t.TagName, ', ') as TagsUsed,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
        THEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) * 100.0 / COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END)
        ELSE 0 
    END as AnswerRate,
    (SELECT COUNT(*) 
     FROM Posts p2 
     WHERE p2.OwnerUserId = u.Id 
     AND p2.PostTypeId = 1 
     AND p2.CreationDate >= DATEADD(YEAR, -1, GETDATE())) as QuestionsLastYear,
    (SELECT COUNT(*) 
     FROM Posts p3 
     WHERE p3.OwnerUserId = u.Id 
     AND p3.PostTypeId = 2 
     AND p3.CreationDate >= DATEADD(YEAR, -1, GETDATE())) as AnswersLastYear,
    (SELECT TOP 1 p4.Title 
     FROM Posts p4 
     WHERE p4.OwnerUserId = u.Id 
     AND p4.PostTypeId = 1 
     AND p4.Score > 100 
     ORDER BY p4.Score DESC) as HighestScoringQuestion,
    (SELECT COUNT(*) 
     FROM Votes v 
     WHERE v.UserId = u.Id 
     AND v.VoteTypeId = 2) as UpvotesReceived,
    (SELECT COUNT(*) 
     FROM Votes v 
     WHERE v.UserId = u.Id 
     AND v.VoteTypeId = 3) as DownvotesReceived,
    (SELECT COUNT(*) 
     FROM Comments c 
     WHERE c.UserId = u.Id) as CommentsMade,
    (SELECT COUNT(*) 
     FROM Posts p5 
     WHERE p5.OwnerUserId = u.Id 
     AND p5.ViewCount > 1000) as PopularPosts,
    CASE 
        WHEN MAX(p.CreationDate) >= DATEADD(DAY, -30, GETDATE()) THEN 'Active'
        WHEN MAX(p.CreationDate) >= DATEADD(DAY, -90, GETDATE()) THEN 'Inactive'
        ELSE 'Very Inactive' 
    END as ActivityLevel,
    PERCENT_RANK() OVER (ORDER BY COALESCE(SUM(p.Score), 0)) as ScorePercentile,
    LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation) as PreviousReputation,
    LEAD(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation) as NextReputation,
    ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC) as RankByScore,
    RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as RankByPostCount,
    DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT b.Id) DESC) as RankByBadgeCount,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Badges b2 WHERE b2.UserId = u.Id AND b2.Class = 1) THEN 'Gold'
        WHEN EXISTS (SELECT 1 FROM Badges b3 WHERE b3.UserId = u.Id AND b3.Class = 2) THEN 'Silver'
        WHEN EXISTS (SELECT 1 FROM Badges b4 WHERE b4.UserId = u.Id AND b4.Class = 3) THEN 'Bronze'
        ELSE 'No Badges'
    END as BadgeTier,
    ISNULL(u.WebsiteUrl, 'No Website') as Website,
    ISNULL(u.Location, 'Unknown Location') as Location,
    CASE 
        WHEN u.AccountId IS NOT NULL THEN 'Account Linked' 
        ELSE 'Account Unlinked' 
    END as AccountStatus
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 3
LEFT JOIN Posts p2 ON pl.RelatedPostId = p2.Id
LEFT JOIN (
    SELECT 
        p3.Id,
        STRING_AGG(t2.TagName, ', ') as Tags
    FROM Posts p3
    INNER JOIN (
        SELECT 
            Id,
            unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) as TagId
        FROM Posts 
        WHERE Tags IS NOT NULL AND Tags != ''
    ) t1 ON p3.Id = t1.Id
    INNER JOIN Tags t2 ON t1.TagId = t2.Id
    WHERE p3.PostTypeId = 1
    GROUP BY p3.Id
) tag_summary ON p.Id = tag_summary.Id
LEFT JOIN Tags t ON p.Id = t.ExcerptPostId OR p.Id = t.WikiPostId
WHERE u.Id IN (
    SELECT Id FROM Users 
    WHERE Reputation > (
        SELECT AVG(Reputation) FROM Users
    )
    AND LastAccessDate > DATEADD(MONTH, -6, GETDATE())
    AND DisplayName IS NOT NULL
    AND (AccountId IS NOT NULL OR EmailHash IS NOT NULL)
)
GROUP BY 
    u.Id, 
    u.DisplayName, 
    u.Reputation, 
    u.WebsiteUrl, 
    u.Location, 
    u.AccountId
HAVING 
    COUNT(DISTINCT p.Id) > 0
    AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) >= 1
    AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) >= 0
ORDER BY 
    TotalScore DESC,
    TotalPosts DESC,
    Reputation DESC
OFFSET 10 ROWS
FETCH NEXT 50 ROWS ONLY;