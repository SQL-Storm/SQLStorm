-- {"query": "48029.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 802} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        pt.Name AS PostTypeName,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        (
            SELECT COUNT(*)
            FROM Comments c
            WHERE c.PostId = p.Id
        ) AS CommentCountForPost,
        (
            SELECT COUNT(*)
            FROM PostHistory ph
            WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)
        ) AS EditCountForPost,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate ASC) AS ScoreRank,
        ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC, p.CreationDate ASC) AS ViewRank,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC, p.Score DESC) AS RecentRank
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 -- Filter for Questions
),
HighEngagementQuestions AS (
    SELECT
        rp.PostId,
        rp.Title,
        rp.PostCreationDate,
        rp.PostScore,
        rp.PostViewCount,
        rp.PostTypeName,
        rp.OwnerDisplayName,
        rp.OwnerReputation,
        rp.CommentCountForPost,
        rp.EditCountForPost
    FROM RankedPosts rp
    WHERE rp.ScoreRank <= 500
      AND rp.ViewRank <= 500
      AND rp.RecentRank <= 500
      AND rp.CommentCountForPost > (SELECT AVG(CommentCountForPost) FROM RankedPosts) * 2
      AND rp.EditCountForPost > (SELECT AVG(EditCountForPost) FROM RankedPosts) * 1.5
)
SELECT
    heq.PostId,
    heq.Title,
    heq.PostCreationDate,
    heq.PostScore,
    heq.PostViewCount,
    heq.PostTypeName,
    heq.OwnerDisplayName,
    heq.OwnerReputation,
    heq.CommentCountForPost,
    heq.EditCountForPost,
    (
        SELECT COUNT(v.Id)
        FROM Votes v
        WHERE v.PostId = heq.PostId AND v.VoteTypeId = 2 -- UpVotes
    ) AS TotalUpvotes,
    (
        SELECT COUNT(v.Id)
        FROM Votes v
        WHERE v.PostId = heq.PostId AND v.VoteTypeId = 3 -- DownVotes
    ) AS TotalDownvotes,
    (
        SELECT COUNT(pl.Id)
        FROM PostLinks pl
        WHERE pl.PostId = heq.PostId AND pl.LinkTypeId = 3 -- Duplicate links
    ) AS DuplicateLinkCount,
    (
        SELECT COUNT(ph.Id)
        FROM PostHistory ph
        WHERE ph.PostId = heq.PostId AND ph.PostHistoryTypeId = 10 -- Post Closed
    ) AS CloseVoteCount
FROM HighEngagementQuestions heq
ORDER BY heq.PostScore DESC, heq.PostViewCount DESC;
