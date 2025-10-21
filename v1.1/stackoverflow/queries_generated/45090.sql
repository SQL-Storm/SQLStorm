-- {"query": "45090.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 407}
WITH TopTags AS (
    SELECT Tags, COUNT(*) as TagCount,
           AVG(Score) as AvgScore,
           SUM(ViewCount) as TotalViews,
           MAX(CreationDate) as LatestPost
    FROM Posts
    CROSS JOIN LATERAL string_to_array(substring(Tags, 2, length(Tags)-2), '><') AS tag
    WHERE PostTypeId = 1
    GROUP BY Tags
    ORDER BY TagCount DESC
    LIMIT 100
),
UserContribution AS (
    SELECT 
        u.Id, 
        u.Reputation,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT v.Id) as VoteCount,
        AVG(p.Score) as AvgPostScore,
        MAX(p.LastActivityDate) as LastActive
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.Reputation
)
SELECT 
    t.Tags,
    t.TagCount,
    t.AvgScore as TagAvgScore,
    t.TotalViews,
    uc.Reputation as TopUserRep,
    uc.PostCount,
    uc.VoteCount,
    EXTRACT(YEAR FROM t.LatestPost) as LatestPostYear
FROM TopTags t
JOIN UserContribution uc ON 1=1
WHERE t.TagCount > 50 AND uc.PostCount > 10
ORDER BY t.TagCount * uc.Reputation DESC
LIMIT 25;
