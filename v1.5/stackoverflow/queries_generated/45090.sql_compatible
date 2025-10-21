WITH TopTags AS (
    SELECT 
        Tags,
        COUNT(*) AS TagCount,
        AVG(Score) AS AvgScore,
        SUM(ViewCount) AS TotalViews,
        MAX(CreationDate) AS LatestPost
    FROM Posts
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(SUBSTRING(Tags FROM 2 FOR LENGTH(Tags) - 2), '><')) AS tag
    ) AS t
    WHERE PostTypeId = 1
    GROUP BY Tags
    ORDER BY COUNT(*) DESC
    LIMIT 100
),
UserContribution AS (
    SELECT 
        u.Id, 
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.LastActivityDate) AS LastActive
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.Reputation
)
SELECT 
    t.Tags,
    t.TagCount,
    t.AvgScore AS TagAvgScore,
    t.TotalViews,
    uc.Reputation AS TopUserRep,
    uc.PostCount,
    uc.VoteCount,
    EXTRACT(YEAR FROM t.LatestPost) AS LatestPostYear
FROM TopTags t
JOIN UserContribution uc ON TRUE
WHERE t.TagCount > 50 AND uc.PostCount > 10
ORDER BY t.TagCount * uc.Reputation DESC
LIMIT 25;