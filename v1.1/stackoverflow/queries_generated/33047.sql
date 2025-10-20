-- {"query": "33047.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 449} 
SELECT
    p.Id AS PostId,
    p.Title AS PostTitle,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    array_to_string(p.Tags, ',') AS Tags,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    ARRAY_AGG(DISTINCT c.UserDisplayName) FILTER (WHERE c.UserDisplayName IS NOT NULL) AS Commenters,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesCount,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesCount,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 12) AS SpamVotesCount,
    MIN(c.CreationDate) AS EarliestCommentDate,
    MAX(c.CreationDate) AS LatestCommentDate,
    bo.BadgeCount AS TotalBadges,
    (SELECT COUNT(*) FROM Posts p_answers WHERE p_answers.ParentId = p.Id AND p_answers.PostTypeId = 2) AS AnswerCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1) AS LinkedPostsCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateCount
FROM
    Posts p
LEFT JOIN
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN
    Comments c ON c.PostId = p.Id
LEFT JOIN
    Votes v ON v.PostId = p.Id
LEFT JOIN
    (
        SELECT
            OwnerUserId,
            COUNT(*) AS BadgeCount
        FROM
            Badges
        GROUP BY
            OwnerUserId
    ) bo ON bo.OwnerUserId = p.OwnerUserId
WHERE
    p.PostTypeId = 1
GROUP BY
    p.Id, u.DisplayName, u.Reputation, bo.BadgeCount
ORDER BY
    p.CreationDate DESC
LIMIT 50;