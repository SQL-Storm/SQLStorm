-- {"query": "15097.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 228830, "output_tokens": 67568} 
WITH TopUserTags AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        t.TagName,
        DENSE_RANK() OVER (PARTITION BY u.Id ORDER BY COUNT(p.Id) DESC) AS TagRank,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN (SELECT Id, unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName FROM Posts) pt ON pt.Id = p.Id
    JOIN Tags t ON t.TagName = pt.TagName
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, t.TagName
),
RankedUserActivity AS (
    SELECT 
        UserId,
        DisplayName,
        TagName,
        PostCount,
        AvgScore,
        LastPostDate,
        PERCENT_RANK() OVER (PARTITION BY UserId ORDER BY PostCount DESC) AS PostCountPercentile
    FROM TopUserTags
    WHERE TagRank <= 3
),
PostInteractions AS (
    SELECT 
        p.Id AS PostId,
        p.Tags,
        v.VoteTypeId,
        COUNT(*) AS VoteCount,
        CASE 
            WHEN AVG(u.Reputation) > 10000 THEN 'High-Rep Voters'
            WHEN AVG(u.Reputation) BETWEEN 1000 AND 10000 THEN 'Mid-Rep Voters'
            ELSE 'Low-Rep Voters'
        END AS VoterRepGroup
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Users u ON v.UserId = u.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Tags, v.VoteTypeId
)
SELECT 
    rua.DisplayName,
    rua.TagName,
    rua.PostCount,
    rua.AvgScore,
    rua.LastPostDate,
    pi.VoterRepGroup,
    pi.VoteCount,
    COALESCE(c.CommentCount, 0) AS PostCommentCount,
    CASE 
        WHEN rua.PostCountPercentile < 0.1 THEN 'Top Contributor'
        WHEN rua.PostCountPercentile < 0.5 THEN 'Active Contributor'
        ELSE 'Occasional Contributor'
    END AS ContributorTier
FROM RankedUserActivity rua
JOIN PostInteractions pi ON POSITION(rua.TagName IN pi.Tags) > 0
LEFT JOIN (
    SELECT PostId, COUNT(*) AS CommentCount 
    FROM Comments 
    GROUP BY PostId
) c ON pi.PostId = c.PostId
WHERE rua.PostCount > 10
    AND pi.VoteCount > 5
ORDER BY rua.PostCount DESC, rua.AvgScore DESC
LIMIT 100;