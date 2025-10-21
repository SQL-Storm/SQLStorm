SELECT
    p.Id AS PostId,
    pt.Name AS PostTypeName,
    COALESCE(p.Title, '') AS Title,
    COALESCE(p.OwnerDisplayName, u.DisplayName, 'Community') AS OwnerDisplayName,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.CreationDate AS CreationDate,
    p.LastActivityDate AS LastActivityDate,
    COALESCE(p.LastEditDate, p.CreationDate) AS LastEditDate,
    CASE
        WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 THEN
            (STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))[1]
        ELSE NULL
    END AS TopTag,
    CASE
        WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 THEN
            (STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))[2]
        ELSE NULL
    END AS SecondTag,
    (SELECT LEFT(c.Text, 150)
     FROM Comments c
     WHERE c.PostId = p.Id
     ORDER BY c.CreationDate DESC
     LIMIT 1) AS LastCommentPreview,
    (SELECT COUNT(*)
     FROM PostLinks pl
     WHERE pl.PostId = p.Id OR pl.RelatedPostId = p.Id) AS LinkCount,
    (SELECT COUNT(*)
     FROM Votes v
     JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
     WHERE v.PostId = p.Id AND vt.Name = 'UpMod') AS UpVotes,
    (SELECT COUNT(*)
     FROM Votes v
     JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
     WHERE v.PostId = p.Id AND vt.Name = 'DownMod') AS DownVotes,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS TypeRank,
    p.Score * 2.0 + p.ViewCount * 0.5 + p.CommentCount * 3.0 + p.AnswerCount * 4.0 AS EngagementScore,
    (SELECT COUNT(*)
     FROM Badges b
     WHERE b.UserId = p.OwnerUserId) > 0 AS HasBadges
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.LastActivityDate >= CAST('2024-10-01' AS DATE) - INTERVAL '90 day'
  AND p.Score >= 0
UNION ALL
SELECT
    p.Id AS PostId,
    pt.Name AS PostTypeName,
    COALESCE(p.Title, '') AS Title,
    COALESCE(p.OwnerDisplayName, u.DisplayName, 'Community') AS OwnerDisplayName,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.CreationDate AS CreationDate,
    p.LastActivityDate AS LastActivityDate,
    COALESCE(p.LastEditDate, p.CreationDate) AS LastEditDate,
    CASE
        WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 THEN
            (STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))[1]
        ELSE NULL
    END AS TopTag,
    CASE
        WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 THEN
            (STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))[2]
        ELSE NULL
    END AS SecondTag,
    (SELECT LEFT(c.Text, 150)
     FROM Comments c
     WHERE c.PostId = p.Id
     ORDER BY c.CreationDate DESC
     LIMIT 1) AS LastCommentPreview,
    (SELECT COUNT(*)
     FROM PostLinks pl
     WHERE pl.PostId = p.Id OR pl.RelatedPostId = p.Id) AS LinkCount,
    (SELECT COUNT(*)
     FROM Votes v
     JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
     WHERE v.PostId = p.Id AND vt.Name = 'UpMod') AS UpVotes,
    (SELECT COUNT(*)
     FROM Votes v
     JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
     WHERE v.PostId = p.Id AND vt.Name = 'DownMod') AS DownVotes,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS TypeRank,
    p.Score * 2.0 + p.ViewCount * 0.5 + p.CommentCount * 3.0 + p.AnswerCount * 4.0 AS EngagementScore,
    (SELECT COUNT(*)
     FROM Badges b
     WHERE b.UserId = p.OwnerUserId) > 0 AS HasBadges
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.LastActivityDate >= CAST('2024-10-01' AS DATE) - INTERVAL '365 day'
  AND p.Score < 0
ORDER BY LastActivityDate DESC
LIMIT 800;