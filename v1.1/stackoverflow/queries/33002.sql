SELECT
    p.PostTypeId,
    pt.Name AS PostTypeName,
    COUNT(*) AS TotalPosts,
    AVG(p.Score) AS AverageScore,
    SUM(p.ViewCount) AS TotalViews,
    COUNT(DISTINCT u.Id) AS UniqueAuthors,
    AVG(EXTRACT(epoch FROM (p.CreationDate - u.CreationDate)) / 86400) AS AvgAuthorAgeAtPosting,
    COUNT(c.Id) AS TotalComments,
    AVG(c.Score) AS AvgCommentScore,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
    COUNT(DISTINCT v.UserId) AS UniqueVoters,
    STRING_AGG(DISTINCT t.TagName, ',') AS TopTags
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
    (
      SELECT p2.Id AS post_id, TRIM(value) AS TagName
      FROM Posts p2
      CROSS JOIN LATERAL (
        SELECT regexp_split_to_table(
          SUBSTRING(p2.Tags FROM 2 FOR (CHAR_LENGTH(p2.Tags) - 2)),
          '><'
        ) AS value
      ) s
    ) t ON t.post_id = p.Id
GROUP BY
    p.PostTypeId,
    pt.Name,
    p.Score,
    p.ViewCount,
    u.Id,
    u.CreationDate,
    c.Id,
    c.Score,
    v.UserId
ORDER BY
    TotalPosts DESC
LIMIT 100;