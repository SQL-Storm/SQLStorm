WITH UserTagActivity AS (
    SELECT 
        u.Id AS UserId,
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(v.VoteCount) AS TotalVotes
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    JOIN 
        (SELECT PostId, COUNT(*) AS VoteCount FROM Votes GROUP BY PostId) v ON p.Id = v.PostId
    CROSS JOIN 
        (SELECT DISTINCT unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName FROM Posts) t
    WHERE 
        p.PostTypeId = 1
        AND u.Reputation > 1000
        AND p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '3 years'
    GROUP BY 
        u.Id, t.TagName
    HAVING 
        COUNT(DISTINCT p.Id) > 5
)
SELECT 
    uta.UserId,
    uta.TagName,
    uta.PostCount,
    uta.AvgPostScore,
    uta.TotalVotes,
    r.TagRank
FROM (
    SELECT
        UserId,
        TagName,
        PostCount,
        AvgPostScore,
        TotalVotes,
        RANK() OVER (PARTITION BY TagName ORDER BY PostCount DESC) AS TagRank
    FROM UserTagActivity
) r
JOIN UserTagActivity uta
  ON r.UserId = uta.UserId
 AND r.TagName = uta.TagName
WHERE 
    r.TagRank <= 10
GROUP BY
    uta.UserId,
    uta.TagName,
    uta.PostCount,
    uta.AvgPostScore,
    uta.TotalVotes,
    r.TagRank
ORDER BY 
    uta.TotalVotes DESC,
    uta.PostCount DESC
LIMIT 500;