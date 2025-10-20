-- {"query": "24090.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3165} 
WITH user_stats AS (
   SELECT u.Id AS UserId,
          u.Reputation,
          u.CreationDate,
          u.Views,
          u.UpVotes,
          u.DownVotes,
          COALESCE(
               (SELECT COUNT(*) FROM Posts p 
                WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1),
               0
          ) AS QuestionCount,
          COALESCE(
               (SELECT COUNT(*) FROM Posts p 
                WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2),
               0
          ) AS AnswerCount
   FROM Users u
),
post_activity AS (
   SELECT p.Id AS PostId,
          p.Title,
          p.Score,
          p.AnswerCount,
          p.AnswerCount + COALESCE(
               (SELECT COUNT(*) FROM Votes v 
                WHERE v.PostId = p.Id AND v.VoteTypeId = 2), 0) AS UpvotePlusAnswers,
          COALESCE(
               (SELECT MAX(v.CreationDate) FROM Votes v 
                WHERE v.PostId = p.Id), '1970-01-01') AS LastVoteDate
   FROM Posts p
   WHERE p.PostTypeId = 1
),
top_comments AS (
   SELECT c.PostId,
          STRING_AGG(c.Text, ' / ') AS CombinedComments
   FROM Comments c
   GROUP BY c.PostId
),
ranked_posts AS (
   SELECT pa.PostId,
          pa.Title,
          pa.Score,
          pa.AnswerCount,
          pa.UpvotePlusAnswers,
          pa.LastVoteDate,
          ROW_NUMBER() OVER (PARTITION BY pa.PostId ORDER BY pa.Score DESC) AS rn
   FROM post_activity pa
   INNER JOIN top_comments tc ON tc.PostId = pa.PostId
   LEFT JOIN PostLinks pl ON pl.PostId = pa.PostId AND pl.LinkTypeId = 1
   LEFT JOIN Posts rpl ON rpl.Id = pl.RelatedPostId
   WHERE pa.Score > 0
),
final AS (
   SELECT us.UserId,
          us.Reputation,
          us.QuestionCount,
          us.AnswerCount AS UserAnswerCount,
          rp.PostId,
          rp.Title,
          rp.Score,
          rp.AnswerCount AS PostAnswerCount,
          rp.UpvotePlusAnswers,
          rp.LastVoteDate,
          rp.rn,
          rp.Title || ' | Score: ' || rp.Score || ' | Answers: ' || rp.AnswerCount AS Summary
   FROM user_stats us
   LEFT JOIN ranked_posts rp ON rp.PostId = us.UserId
   WHERE rp.rn <= 3
)
SELECT * FROM final
UNION ALL
SELECT 0 AS UserId, -1 AS Reputation, NULL AS QuestionCount, NULL AS UserAnswerCount,
       -1 AS PostId, '' AS Title, 0 AS Score, 0 AS PostAnswerCount,
       0 AS UpvotePlusAnswers, '1970-01-01'::timestamp AS LastVoteDate,
       0 AS rn, 'Null Row' AS Summary
ORDER BY UserId, rn;