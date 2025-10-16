-- {"query": "28037.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1603} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.Reputation,
        EXTRACT(YEAR FROM u.CreationDate) AS JoinYear,
        RANK() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC) AS RankInYear,
        COALESCE(u.WebsiteUrl, 'No Website') AS Website,
        (u.UpVotes - u.DownVotes) AS NetVotes,
        AVG(p.Score) OVER (PARTITION BY u.Id) AS AvgPostScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
),
PostData AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Tags,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS Upvotes,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'CommunityWiki'
            ELSE 'Active'
        END AS PostStatus
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
)
SELECT 
    us.JoinYear,
    us.RankInYear,
    us.Website,
    STRING_AGG(DISTINCT SUBSTRING(b.Name FROM 1 FOR 15), '; ') AS BadgeNames,
    COUNT(DISTINCT pd.Id) FILTER (WHERE pd.PostStatus = 'Closed') AS ClosedPosts,
    AVG(pd.AnswerCount)::DECIMAL(5,2) AS AvgAnswers,
    MAX(pd.Upvotes) AS MaxPostUpvotes,
    SUM(CASE WHEN pd.FavoriteCount > 0 THEN 1 ELSE 0 END) AS FavoritedPosts,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY us.NetVotes) AS MedianNetVotes,
    COALESCE(STRING_AGG(DISTINCT NULLIF(REPLACE(SUBSTRING(pd.Tags FROM 2 FOR LENGTH(pd.Tags)-2), '><', ', '), ''), ', '), 'No Tags') AS TagList
FROM UserStats us
LEFT JOIN Badges b ON us.Id = b.UserId AND b.Class = 1
LEFT JOIN PostData pd ON us.Id = pd.OwnerUserId
LEFT JOIN Votes v ON pd.Id = v.PostId AND v.VoteTypeId IN (2, 8)
WHERE us.Reputation > (SELECT AVG(Reputation) FROM Users WHERE JoinYear = us.JoinYear)
    AND EXISTS (SELECT 1 FROM Posts p2 WHERE p2.OwnerUserId = us.Id AND p2.Score > 100)
GROUP BY us.JoinYear, us.RankInYear, us.Website
HAVING AVG(pd.AnswerCount) > 1 OR MAX(pd.Upvotes) > 10
ORDER BY us.JoinYear DESC, us.RankInYear ASC
LIMIT 100;
