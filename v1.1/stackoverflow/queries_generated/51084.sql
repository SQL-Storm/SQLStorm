-- {"query": "51084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2129, "output_tokens": 820} 

WITH TopUsers AS (
    SELECT u.Id AS UserId, u.Reputation, u.UpVotes, u.DownVotes,
           COUNT(DISTINCT p.Id) AS QuestionCount,
           SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation, u.UpVotes, u.DownVotes
    HAVING COUNT(DISTINCT p.Id) >= 5
),
TopPosts AS (
    SELECT p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, p.Tags,
           COALESCE(accepted.Id, 0) AS HasAcceptedAnswer,
           ph.close_count,
           ROW_NUMBER() OVER (PARTITION BY SUBSTRING(p.Tags, 2, 100) ORDER BY p.Score DESC) AS tag_rank,
           LAG(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS prev_score
    FROM Posts p
    LEFT JOIN (SELECT PostId, COUNT(*) AS close_count 
               FROM PostHistory WHERE PostHistoryTypeId = 10 GROUP BY PostId) ph ON ph.PostId = p.Id
    LEFT JOIN Posts accepted ON p.AcceptedAnswerId = accepted.Id
    WHERE p.PostTypeId = 1 
      AND p.Score > 0 
      AND p.ViewCount > 100
      AND p.CreationDate > CURRENT_DATE - INTERVAL '1 year'
),
TagStats AS (
    SELECT t.TagName,
           AVG(tp.Score) AS avg_score,
           COUNT(tp.Id) AS post_count,
           SUM(tp.ViewCount) AS total_views,
           PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY tp.ViewCount) AS p90_views
    FROM Tags t
    JOIN TopPosts tp ON POSITION(t.TagName IN tp.Tags) > 0
    WHERE t.Count > 10
    GROUP BY t.TagName
    HAVING COUNT(tp.Id) >= 3
),
VotePatterns AS (
    SELECT v.PostId,
           COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS upvote_count,
           COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS downvote_count,
           AVG(v.CreationDate) AS avg_vote_time,
           COUNT(DISTINCT v.UserId) AS unique_voters
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3)
      AND v.CreationDate > CURRENT_DATE - INTERVAL '6 months'
    GROUP BY v.PostId
)
SELECT 
    tu.UserId,
    tu.Reputation,
    tu.QuestionCount,
    tu.AnswerCount,
    tp.Title,
    tp.Score,
    tp.ViewCount,
    tp.HasAcceptedAnswer,
    ts.TagName AS top_tag,
    ts.avg_score AS tag_avg_score,
    vp.upvote_count,
    vp.downvote_count,
    vp.unique_voters,
    (vp.upvote_count::float / NULLIF(vp.downvote_count, 0)) AS vote_ratio,
    (tp.Score - COALESCE(tp.prev_score, 0)) AS score_change,
    CASE 
        WHEN tp.tag_rank = 1 THEN 'Top'
        WHEN tp.tag_rank <= 3 THEN 'High'
        ELSE 'Other'
    END AS post_rank
FROM TopUsers tu
JOIN TopPosts tp ON tp.OwnerUserId = tu.UserId
JOIN TagStats ts ON POSITION(ts.TagName IN tp.Tags) > 0
LEFT JOIN VotePatterns vp ON vp.PostId = tp.Id
WHERE tp.tag_rank <= 5
  AND ts.total_views > 10000
ORDER BY tu.Reputation DESC, tp.Score DESC, vp.vote_ratio DESC NULLS LAST
LIMIT 1000;
