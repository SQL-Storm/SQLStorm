-- {"query": "33040.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 619} 
SELECT
    p.Id AS PostID,
    p.Title AS PostTitle,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    p.AnswerCount,
    p.CommentCount,
    u.Id AS OwnerUserID,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate AS UserLastAccessDate,
    array_length(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '<>'), 1) AS TagCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,6,7,8,9,10,11,12,13,14,15,16,17)) AS RevisionCount,
    COUNT(DISTINCT t.TagName) AS UniqueTags,
    (SELECT COUNT(*) FROM Posts answers WHERE answers.ParentId = p.Id) AS AnswerCount,
    (SELECT COUNT(*) FROM Posts cposts WHERE cposts.ParentId = p.Id AND cposts.PostTypeId = 2) AS AnswerCommentsCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3)) AS TotalVotes,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVoteCount,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVoteCount
FROM
    Posts p
LEFT JOIN
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN
    (SELECT DISTINCT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '<>')) AS TagName, p.Id as PostId
     FROM Posts p WHERE p.PostTypeId = 1) t ON p.Id = t.PostId
LEFT JOIN
    Votes v ON p.Id = v.PostId
WHERE
    p.PostTypeId = 1 -- Questions only
GROUP BY
    p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount,
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
ORDER BY
    p.CreationDate DESC
LIMIT 100;