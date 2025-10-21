-- {"query": "24083.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1594} 
WITH cte_questions AS (
    SELECT p.Id, p.Title, p.Tags, p.CreationDate, p.Score,
           COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
           CASE WHEN p.Tags LIKE '%sql%' THEN 1 ELSE 0 END AS HasSqlTag
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Score >= 5
      AND p.CreationDate >= '2015-01-01'
),
cte_answers AS (
    SELECT a.Id, a.ParentId, a.Score, a.CreationDate,
           a.OwnerUserId,
           ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS rn
    FROM Posts a
    WHERE a.PostTypeId = 2
),
cte_comment_counts AS (
    SELECT pc.PostId,
           COUNT(*) FILTER (WHERE c.Score > 0) AS up_comments,
           COUNT(*) FILTER (WHERE c.Score = 0) AS neutral_comments,
           COUNT(*) FILTER (WHERE c.Score < 0) AS down_comments
    FROM Posts pc
    LEFT JOIN Comments c ON c.PostId = pc.Id
    GROUP BY pc.Id
),
cte_related_links AS (
    SELECT pl.PostId, COUNT(*) FILTER (WHERE pl.LinkTypeId = 3) AS duplicate_links,
           COUNT(*) FILTER (WHERE pl.LinkTypeId = 1) AS other_links
    FROM PostLinks pl
    GROUP BY pl.PostId
),
cte_badges AS (
    SELECT b.UserId,
           MAX(b.Class = 1) AS has_gold,
           MAX(b.Class = 2) AS has_silver,
           MAX(b.Class = 3) AS has_bronze,
           SUM(CASE WHEN b.Class = 1 AND b.TagBased = 1 THEN 1 END) AS gold_tag_badges
    FROM Badges b
    GROUP BY b.UserId
),
cte_user_stats AS (
    SELECT u.Id,
           u.Reputation,
           u.Views,
           u.UpVotes,
           u.DownVotes,
           uc.badges
    FROM Users u
    JOIN cte_badges uc ON uc.UserId = u.Id
),
final AS (
    SELECT q.Id AS QuestionId,
           q.Title,
           q.Tags,
           q.CreationDate AS QuestionDate,
           q.Score AS QuestionScore,
           ca.Id AS AnswerId,
           ca.Score AS AnswerScore,
           ca.OwnerUserId AS AnswerUser,
           uc.badges,
           cc.up_comments, cc.neutral_comments, cc.down_comments,
           rl.duplicate_links, rl.other_links,
           CASE WHEN (q.HasSqlTag = 1 AND q.Score > 10) THEN 'High SQL Q' ELSE 'Other' END AS Category
    FROM cte_questions q
    LEFT JOIN cte_answers ca ON ca.ParentId = q.Id AND ca.rn = 1
    LEFT JOIN cte_comment_counts cc ON cc.PostId = COALESCE(ca.Id, q.Id)
    LEFT JOIN cte_related_links rl ON rl.PostId = COALESCE(ca.Id, q.Id)
    LEFT JOIN cte_user_stats uc ON uc.Id = ca.OwnerUserId
)
SELECT *
FROM final
WHERE (QuestionScore + AnswerScore) > 20
  AND (duplicate_links < 3 OR other_links > 5)
  AND (up_comments - down_comments) >= 5
  AND (badges.gold_tag_badges > 0 OR badges.has_gold = true)
ORDER BY QuestionDate DESC
LIMIT 1000;