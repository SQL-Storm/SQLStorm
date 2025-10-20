SELECT
    p.Id AS PostId,
    u.DisplayName,
    t.TagName,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    COUNT(DISTINCT c.Id) AS CommentCount,
    AVG(p.Score) AS AveragePostScore,
    MAX(u.Reputation) AS UserMaxReputation,
    (
        SELECT COUNT(*)
        FROM PostLinks pl
        WHERE pl.PostId = p.Id OR pl.RelatedPostId = p.Id
    ) AS TotalLinkedPosts
FROM
    Posts p
JOIN
    Users u ON p.OwnerUserId = u.Id
JOIN
    Tags t ON t.TagName IN (
        SELECT TRIM(x) FROM UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags)-2)), '><')) AS x
    )
LEFT JOIN
    Votes v ON v.PostId = p.Id
LEFT JOIN
    Comments c ON c.PostId = p.Id
WHERE
    p.PostTypeId = 1
    AND u.Reputation > 1000
    AND p.CreationDate > DATE '2015-01-01'
GROUP BY
    p.Id, u.DisplayName, t.TagName
HAVING
    COUNT(DISTINCT v.Id) > 10
ORDER BY
    TotalVotes DESC, UserMaxReputation DESC
LIMIT 500;