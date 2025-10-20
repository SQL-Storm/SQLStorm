-- {"query": "42.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 215} 
WITH recent_posts AS (
    SELECT p.Id, p.ParentId, p.CreationDate, p.Score, p.Title, p.Tags,
           ROW_NUMBER() OVER(PARTITION BY p.ParentId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
    AND p.CreationDate >= '2022-01-01'
), top_answer_count AS (
    SELECT p.ParentId, COUNT(p.Id) AS AnswerCount
    FROM Posts p
    WHERE p.PostTypeId = 2
    AND p.CreationDate >= '2022-01-01'
    GROUP BY p.ParentId
)
SELECT rp.Id AS QuestionId, rp.CreationDate AS QuestionDate, rp.Score AS QuestionScore, 
       rp.Title AS QuestionTitle, rp.Tags AS QuestionTags, tac.AnswerCount AS AnswerCount
FROM recent_posts rp
LEFT JOIN top_answer_count tac ON rp.Id = tac.ParentId
WHERE rp.rn = 1
ORDER BY rp.CreationDate DESC;