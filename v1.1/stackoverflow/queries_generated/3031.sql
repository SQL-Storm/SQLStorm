-- {"query": "3031.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 743} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.Tags,
        p.PostTypeId,
        p.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate ASC) AS Rank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
PostContribs AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostCount,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesReceived,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesReceived
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName
),
ActiveUsers AS (
    SELECT 
        uc.UserId,
        SUM(CASE WHEN v.VoteTypeId IN (2, 3) THEN 1 ELSE 0 END) AS VotingActivity
    FROM Users uc
    LEFT JOIN Votes v ON v.UserId = uc.UserId
    GROUP BY uc.UserId
)
SELECT 
    rp.Id,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    array_agg(DISTINCT unnest(string_to_array(rp.Tags, '><'))) AS TagList,
    CASE WHEN rp.PostTypeId = 1 THEN 'Question' ELSE 'Answer' END AS PostType,
    u.DisplayName AS OwnerName,
    u.Reputation,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    pc.PostCount,
    pc.AvgScore,
    pc.LastPostDate,
    ac.VotingActivity,
    EXISTS (
        SELECT 1 FROM PostLinks pl
        WHERE pl.PostId = rp.Id AND pl.LinkTypeId = 3
    ) AS IsDuplicateOfAnotherPost,
    (
        SELECT COUNT(*) FROM Comments c
        WHERE c.PostId = rp.Id AND c.Score > 0
    ) AS PositiveCommentCount,
    (
        SELECT COUNT(*) FROM Comments c
        WHERE c.PostId = rp.Id AND c.Score < 0
    ) AS NegativeCommentCount,
    (
        SELECT string_agg(c.Text, ' || ') FROM Comments c WHERE c.PostId = rp.Id
    ) AS AllCommentsText,
    MAX(pl2.CreationDate) FILTER (WHERE pl2.RelatedPostId = rp.Id) AS LastLinkedTagChange
FROM RankedPosts rp
LEFT JOIN Users u ON rp.OwnerUserId = u.Id
LEFT JOIN PostContribs pc ON u.Id = pc.UserId
LEFT JOIN Votes v ON v.PostId = rp.Id
LEFT JOIN PostLinks pl2 ON pl2.PostId = rp.Id
WHERE rp.Rank = 1
GROUP BY 
    rp.Id, 
    rp.Title, 
    rp.CreationDate,
    rp.Score,
    rp.Tags,
    rp.PostTypeId,
    u.DisplayName,
    u.Reputation,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    pc.PostCount,
    pc.AvgScore,
    pc.LastPostDate,
    ac.VotingActivity
ORDER BY rp.CreationDate DESC
LIMIT 100;