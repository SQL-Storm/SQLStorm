-- {"query": "6524.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 476}
SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 1 THEN p.Id END) AS TotalQuestions,
    AVG(p.Score) AS AvgScore,
    MAX(p.LastActivityDate) AS LastActive,
    MAX(CASE WHEN p.PostTypeId = 1 THEN p.LastEditDate END) AS LastQuestionEdit,
    SUM(v.BountyAmount) AS TotalBounty,
    MAX(b.Date) AS LastBadgeEarned,
    MAX(CASE WHEN p.PostTypeId = 1 THEN p.ClosedDate END) AS LastClosedQuestion,
    MAX(CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.LastEditDate END) AS LastAnsweredQuestion,
    MAX(CASE WHEN pl.LinkTypeId = 3 THEN p.Id END) AS DuplicatePostId,
    MAX(CASE WHEN pl.LinkTypeId = 1 THEN p.Id END) AS LinkedPostId,
    -- use ordered aggregation without DISTINCT; remove DISTINCT to avoid dialect errors
    STRING_AGG(p.Tags, ',' ORDER BY p.Tags) AS TopTags
FROM
    Users u
LEFT JOIN
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN
    Votes v ON p.Id = v.PostId
LEFT JOIN
    Badges b ON u.Id = b.UserId
LEFT JOIN
    PostLinks pl ON p.Id = pl.PostId
WHERE
    u.Reputation > 10000
    AND (p.CreationDate IS NULL OR p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR))
    AND (ph.PostHistoryTypeId IN (1, 2) OR ph.PostHistoryTypeId IS NULL)
GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation
HAVING
    AVG(p.Score) > 100
    OR SUM(v.BountyAmount) > 1000
ORDER BY
    TotalPosts DESC,
    AvgScore DESC;