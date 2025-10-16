-- {"query": "2016.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 551} 

WITH RecursiveActiveUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(p.Id) AS TotalPosts
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        u.CreationDate BETWEEN '2020-01-01' AND '2023-01-01'
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
    HAVING 
        COUNT(p.Id) > 0 
),
BadgeStatistics AS (
    SELECT 
        b.UserId, 
        COUNT(CASE WHEN b.Class = 1 THEN 1 ELSE NULL END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 ELSE NULL END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 ELSE NULL END) AS BronzeBadges
    FROM 
        Badges b
    GROUP BY 
        b.UserId
)
SELECT 
    rau.DisplayName, 
    rau.Reputation, 
    rau.TotalPosts,
    bs.GoldBadges, 
    bs.SilverBadges, 
    bs.BronzeBadges,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    AVG(COALESCE(v.BountyAmount, 0)) AS AverageBounty,
    STRING_AGG(DISTINCT t.TagName, ', ') AS TagsUsed
FROM 
    RecursiveActiveUsers rau
LEFT JOIN 
    BadgeStatistics bs ON rau.Id = bs.UserId
LEFT JOIN 
    Posts p ON rau.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    (SELECT PostId, UNNEST(string_to_array(substring(Tags, 2, length(Tags) - 2), '><')) AS TagName FROM Posts) pt ON p.Id = pt.PostId
LEFT JOIN 
    Tags t ON pt.TagName = t.TagName
GROUP BY 
    rau.DisplayName, 
    rau.Reputation, 
    rau.TotalPosts, 
    bs.GoldBadges, 
    bs.SilverBadges, 
    bs.BronzeBadges
ORDER BY 
    rau.Reputation DESC, 
    bs.GoldBadges DESC
LIMIT 100;
