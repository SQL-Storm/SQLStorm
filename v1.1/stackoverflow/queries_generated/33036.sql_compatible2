SELECT
    p.Id AS PostId,
    p.Title AS PostTitle,
    pt.Name AS PostType,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    c.Score AS CommentScore,
    c.Text AS CommentText,
    u.DisplayName AS CommentUser,
    v.VoteTypeId,
    vt.Name AS VoteTypeName,
    COUNT(DISTINCT a.Id) AS AnswerCount,
    COUNT(DISTINCT cl.RelatedPostId) AS LinkCount,
    ARRAY_AGG(DISTINCT t.TagName) AS Tags,
    STRING_AGG(DISTINCT ub.DisplayName, ', ') AS UserBadges,
    p.LastEditDate,
    p.ClosedDate,
    br.Name AS CloseReason,
    p.ContentLicense
FROM
    Posts p
LEFT JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN
    Comments c ON c.PostId = p.Id
LEFT JOIN
    Users u ON c.UserId = u.Id
LEFT JOIN
    Votes v ON v.PostId = p.Id
LEFT JOIN
    VoteTypes vt ON v.VoteTypeId = vt.Id
LEFT JOIN
    Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
LEFT JOIN
    PostLinks cl ON cl.PostId = p.Id
LEFT JOIN
    Posts linkedPost ON cl.RelatedPostId = linkedPost.Id
LEFT JOIN
    Tags t ON t.ExcerptPostId = p.Id OR t.WikiPostId = p.Id
LEFT JOIN
    (
        SELECT DISTINCT uv.UserId, uv.PostId
        FROM Votes uv
    ) uv ON uv.PostId = p.Id
LEFT JOIN
    Users ub ON ub.Id = uv.UserId
LEFT JOIN
    PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 6)
LEFT JOIN
    CloseReasonTypes br ON ph.Comment = CAST(br.Id AS VARCHAR)
WHERE
    p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2' YEAR
GROUP BY
    p.Id,
    p.Title,
    pt.Name,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    c.Score,
    c.Text,
    u.DisplayName,
    v.VoteTypeId,
    vt.Name,
    p.LastEditDate,
    p.ClosedDate,
    br.Name,
    p.ContentLicense
ORDER BY
    p.CreationDate DESC
LIMIT 100;