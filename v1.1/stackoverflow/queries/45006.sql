WITH ActiveUserTags AS (
    SELECT u.Id, 
           u.DisplayName, 
           t.TagName, 
           COUNT(p.Id) AS PostCount,
           AVG(p.Score) AS AvgPostScore
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN (
        SELECT DISTINCT tag AS TagName
        FROM (
            SELECT TRIM(BOTH ' ' FROM value) AS tag
            FROM (
                SELECT SUBSTRING(Tags FROM 2 FOR LENGTH(Tags) - 2) AS TagsTrimmed
                FROM Posts
            ) pt,
            LATERAL (
                SELECT value
                FROM regexp_split_to_table(pt.TagsTrimmed, '><') AS value
            ) s
        ) s2
    ) t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, t.TagName
    HAVING COUNT(p.Id) > 10
),
TagPerformance AS (
    SELECT TagName, 
           MAX(PostCount) AS MaxUserPostCount,
           AVG(AvgPostScore) AS OverallTagScore,
           COUNT(DISTINCT Id) AS UniqueActiveUsers
    FROM ActiveUserTags
    GROUP BY TagName
),
PostTagVotes AS (
    SELECT tt.tag AS TagName, COUNT(v.Id) AS VoteCount
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    CROSS JOIN LATERAL (SELECT SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2) AS TagsTrimmed) ct
    CROSS JOIN LATERAL regexp_split_to_table(ct.TagsTrimmed, '><') AS tt(tag)
    GROUP BY tt.tag
),
PostTagViews AS (
    SELECT tt.tag AS TagName, SUM(p.ViewCount) AS ViewCount
    FROM Posts p
    CROSS JOIN LATERAL (SELECT SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2) AS TagsTrimmed) ct
    CROSS JOIN LATERAL regexp_split_to_table(ct.TagsTrimmed, '><') AS tt(tag)
    GROUP BY tt.tag
)
SELECT 
    tp.TagName, 
    tp.MaxUserPostCount, 
    tp.OverallTagScore, 
    tp.UniqueActiveUsers,
    v.VoteCount,
    p.ViewCount
FROM TagPerformance tp
LEFT JOIN PostTagVotes v ON tp.TagName = v.TagName
LEFT JOIN PostTagViews p ON tp.TagName = p.TagName
ORDER BY tp.OverallTagScore DESC, tp.UniqueActiveUsers DESC
LIMIT 50;