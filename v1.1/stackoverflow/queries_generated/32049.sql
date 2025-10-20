-- {"query": "32049.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 315} 

SELECT
    u.DisplayName,
    u.Reputation,
    COUNT(p.Id) AS TotalPosts,
    SUM(p.Score) AS TotalScore,
    COUNT(c.Id) AS TotalComments,
    COUNT(v.Id) AS TotalVotes,
    (SELECT COUNT(DISTINCT b.Name)
     FROM Badges b
     WHERE b.UserId = u.Id
       AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(DISTINCT b.Name)
     FROM Badges b
     WHERE b.UserId = u.Id
       AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(DISTINCT b.Name)
     FROM Badges b
     WHERE b.UserId = u.Id
       AND b.Class = 3) AS BronzeBadges,
    t.PostCounts AS PostsPerYear
FROM
    Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN Votes v ON u.Id = v.UserId
LEFT JOIN (
    SELECT
        OwnerUserId,
        EXTRACT(YEAR FROM CreationDate) AS Year,
        COUNT(Id) AS PostCounts
    FROM
        Posts
    GROUP BY OwnerUserId, EXTRACT(YEAR FROM CreationDate)
) t ON u.Id = t.OwnerUserId
WHERE
    u.Reputation > 1000
GROUP BY
    u.Id, t.PostCounts
ORDER BY
    TotalScore DESC
LIMIT 100;
