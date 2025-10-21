-- {"query": "48083.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 676} 
WITH RankedPosts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.CreationDate,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) as score_rank,
        ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC, p.CreationDate DESC) as view_rank,
        ROW_NUMBER() OVER (ORDER BY p.AnswerCount DESC, p.Score DESC, p.CreationDate DESC) as answer_rank,
        ROW_NUMBER() OVER (ORDER BY p.CommentCount DESC, p.Score DESC, p.CreationDate DESC) as comment_rank,
        ROW_NUMBER() OVER (ORDER BY p.FavoriteCount DESC, p.Score DESC, p.CreationDate DESC) as favorite_rank
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
),
TopUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) as reputation_rank
    FROM Users u
    WHERE u.Id IS NOT NULL AND u.Id > 0
)
SELECT
    rp.Id AS PostId,
    rp.score_rank,
    rp.view_rank,
    rp.answer_rank,
    rp.comment_rank,
    rp.favorite_rank,
    tu.Id AS UserId,
    tu.DisplayName,
    tu.reputation_rank,
    tu.Reputation,
    tu.Views,
    tu.UpVotes,
    tu.DownVotes,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ClosedDate,
    rp.CreationDate AS PostCreationDate,
    tu.CreationDate AS UserCreationDate
FROM RankedPosts rp
JOIN TopUsers tu ON rp.OwnerUserId = tu.Id
WHERE rp.score_rank <= 100
  AND rp.view_rank <= 100
  AND rp.answer_rank <= 100
  AND rp.comment_rank <= 100
  AND rp.favorite_rank <= 100
  AND tu.reputation_rank <= 100
ORDER BY
    rp.score_rank,
    rp.view_rank,
    rp.answer_rank,
    rp.comment_rank,
    rp.favorite_rank,
    tu.reputation_rank;