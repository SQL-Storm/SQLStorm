-- {"query": "45037.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 682}
WITH ActiveUserTags AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        t.TagName,
        SUM(p.Score) AS TotalTagScore,
        COUNT(p.Id) AS PostCount,
        RANK() OVER (PARTITION BY t.TagName ORDER BY SUM(p.Score) DESC) AS TagRank
    FROM 
        Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN (SELECT unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName FROM Posts) t ON 1=1
    WHERE 
        p.PostTypeId IN (1, 2)
        AND u.Reputation > 1000
        AND p.CreationDate > '2015-01-01'
    GROUP BY 
        u.Id, u.DisplayName, t.TagName
    HAVING 
        COUNT(p.Id) > 5
), 
TagPerformance AS (
    SELECT 
        TagName,
        MAX(TotalTagScore) AS MaxTagScore,
        AVG(PostCount) AS AvgPostsPerUser,
        COUNT(DISTINCT UserId) AS UniqueContributors
    FROM 
        ActiveUserTags
    WHERE 
        TagRank <= 10
    GROUP BY 
        TagName
)
SELECT 
    tp.TagName,
    tp.MaxTagScore,
    tp.AvgPostsPerUser,
    tp.UniqueContributors,
    v.VoteCount,
    c.CommentCount
FROM 
    TagPerformance tp
JOIN (
    SELECT 
        t.TagName,
        COUNT(v.Id) AS VoteCount
    FROM 
        (SELECT unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName FROM Posts) t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    JOIN Votes v ON v.PostId = p.Id
    GROUP BY t.TagName
) v ON tp.TagName = v.TagName
JOIN (
    SELECT 
        t.TagName,
        COUNT(c.Id) AS CommentCount
    FROM 
        (SELECT unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName FROM Posts) t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    JOIN Comments c ON c.PostId = p.Id
    GROUP BY t.TagName
) c ON tp.TagName = c.TagName
ORDER BY 
    tp.UniqueContributors DESC, 
    tp.MaxTagScore DESC
LIMIT 50;
