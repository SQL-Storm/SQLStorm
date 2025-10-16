-- {"query": "24079.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2768} 
WITH question_stats AS (
   SELECT p.Id AS QuestionId,
          p.Title,
          p.Tags,
          COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0) AS upvotes,
          COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END),0) AS downvotes,
          COUNT(a.Id) AS answer_count,
          MAX(a.Score) AS max_answer_score,
          AVG(a.Score) AS avg_answer_score,
          MIN(p.CreationDate) AS first_post_date
   FROM Posts p
   LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2,3)
   LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
   WHERE p.PostTypeId = 1
   GROUP BY p.Id, p.Title, p.Tags
),
tag_rank AS (
   SELECT t.TagName, t.Count,
          ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
   FROM Tags t
),
question_tags AS (
   SELECT qs.QuestionId, t.TagName
   FROM question_stats qs
   CROSS JOIN LATERAL unnest(regexp_split_to_array(qs.Tags, '[<>]+')) AS t(TagName)
   WHERE t.TagName <> ''
),
filtered_tags AS (
   SELECT qt.QuestionId, MIN(tr.rn) AS highest_tag_rank
   FROM question_tags qt
   JOIN tag_rank tr ON tr.TagName = qt.TagName
   GROUP BY qt.QuestionId
)
SELECT qs.QuestionId,
       qs.Title,
       qs.Tags,
       qs.upvotes,
       qs.downvotes,
       qs.answer_count,
       qs.max_answer_score,
       qs.avg_answer_score,
       qs.first_post_date,
       CASE
          WHEN EXISTS (
               SELECT 1 FROM PostLinks pl
               WHERE pl.PostId = qs.QuestionId AND pl.LinkTypeId = 3
          ) THEN 1 ELSE 0
       END AS is_duplicate,
       COALESCE(ft.highest_tag_rank, 0) AS highest_tag_rank
FROM question_stats qs
LEFT JOIN filtered_tags ft ON ft.QuestionId = qs.QuestionId
ORDER BY qs.first_post_date DESC
LIMIT 100;