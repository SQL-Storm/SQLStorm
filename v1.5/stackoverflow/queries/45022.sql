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
    UserId,
    TagName,
    PostCount,
    AvgPostScore,
    TotalVotes,
    RANK() OVER (PARTITION BY TagName ORDER BY PostCount DESC) AS TagRank
FROM (
    SELECT
        *,
        RANK() OVER (PARTITION BY TagName ORDER BY PostCount DESC) AS TagRank
    FROM UserTagActivity
) AS ua
WHERE 
    TagRank <= 10
ORDER BY 
    TotalVotes DESC, PostCount DESC
LIMIT 500;