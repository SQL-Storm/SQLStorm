-- {"query": "24027.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 4134} 
WITH
    UserPostCounts AS (
        SELECT OwnerUserId,
               SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QCount,
               SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS ACount
        FROM Posts
        GROUP BY OwnerUserId
    ),
    VoteStats AS (
        SELECT p.OwnerUserId,
               COUNT(v.Id) AS TotalVotes,
               SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
               SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Posts p
        JOIN Votes v ON v.PostId = p.Id
        GROUP BY p.OwnerUserId
    ),
    EditCounts AS (
        SELECT p.OwnerUserId,
               COUNT(*) AS EditCount
        FROM Posts p
        JOIN PostHistory ph ON ph.PostId = p.Id
        WHERE ph.PostHistoryTypeId = 5
        GROUP BY p.OwnerUserId
    ),
    TagUses AS (
        SELECT p.OwnerUserId,
               t.TagName,
               COUNT(*) AS TagUses
        FROM Posts p
        JOIN Tags t ON POSITION(t.TagName IN p.Tags) > 0
        WHERE p.PostTypeId = 1
        GROUP BY p.OwnerUserId, t.TagName
    ),
    TagRank AS (
        SELECT OwnerUserId,
               TagName,
               TagUses,
               ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY TagUses DESC, TagName) AS rn
        FROM TagUses
    )
SELECT
    u.Id AS UserId,
    COALESCE(u.DisplayName, 'Anonymous') AS DisplayName,
    CONCAT(COALESCE(u.DisplayName, 'Anonymous'),'#',u.Id) AS UserTag,
    COALESCE(upc.QCount,0) + COALESCE(upc.ACount,0) AS TotalPosts,
    COALESCE(vc.TotalVotes,0) AS TotalVotes,
    COALESCE(ec.EditCount,0) AS TotalEdits,
    ROUND(
        COALESCE(vc.TotalVotes,0) * 1.0 /
        NULLIF((COALESCE(upc.QCount,0)+COALESCE(upc.ACount,0)),0),
    2) AS VotePerPost,
    COALESCE(tr.TagName,'None') AS TopTag,
    COALESCE(vc.UpVotes,0) AS UpVotes
FROM Users u
LEFT JOIN UserPostCounts upc ON upc.OwnerUserId = u.Id
LEFT JOIN VoteStats vc ON vc.OwnerUserId = u.Id
LEFT JOIN EditCounts ec ON ec.OwnerUserId = u.Id
LEFT JOIN TagRank tr ON tr.OwnerUserId = u.Id AND tr.rn = 1
WHERE (COALESCE(upc.QCount,0)+COALESCE(upc.ACount,0)) > 0
ORDER BY VotePerPost DESC, u.Reputation DESC
LIMIT 10;