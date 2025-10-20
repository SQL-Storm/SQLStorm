-- {"query": "33002.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 294} 
SELECT
    p.PostTypeId,
    pt.Name AS PostTypeName,
    COUNT(*) AS TotalPosts,
    AVG(p.Score) AS AverageScore,
    SUM(p.ViewCount) AS TotalViews,
    COUNT(DISTINCT u.Id) AS UniqueAuthors,
    AVG(DATEDIFF('day', u.CreationDate, p.CreationDate)) AS AvgAuthorAgeAtPosting,
    COUNT(c.Id) AS TotalComments,
    AVG(c.Score) AS AvgCommentScore,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS TotalUpVotes,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS TotalDownVotes,
    COUNT(DISTINCT v.UserId) AS UniqueVoters,
    ARRAY_AGG(DISTINCT t.TagName) AS TopTags
FROM
    Posts p
JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN
    Comments c ON c.PostId = p.Id
LEFT JOIN
    Votes v ON v.PostId = p.Id
LEFT JOIN
    unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS t(TagName)
GROUP BY
    p.PostTypeId, pt.Name
ORDER BY
    TotalPosts DESC
LIMIT 100;