-- {"query": "24080.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 5937} 
WITH
tagged_questions AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.AcceptedAnswerId,
    p.Tags,
    UNNEST(regexp_split_to_array(substring(p.Tags FROM 2 FOR length(p.Tags)-2), '><')) AS Tag
  FROM Posts p
  WHERE p.PostTypeId = 1
),
tag_summary AS (
  SELECT
    QuestionId,
    STRING_AGG(DISTINCT Tag, ', ') AS TagList,
    COUNT(DISTINCT Tag) AS NumTags
  FROM tagged_questions
  GROUP BY QuestionId
),
vote_counts AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCnt,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCnt
  FROM Votes v
  GROUP BY v.PostId
),
dup_info AS (
  SELECT
    dl.PostId,
    dl.RelatedPostId
  FROM PostLinks dl
  WHERE dl.LinkTypeId = 3
),
question_stats AS (
  SELECT
    q.QuestionId,
    q.Title,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.AcceptedAnswerId,
    ts.TagList,
    ts.NumTags,
    COALESCE(vc.UpVoteCnt,0) AS Ups,
    COALESCE(vc.DownVoteCnt,0) AS Downs,
    (SELECT AVG(a.CreationDate - q.CreationDate)::float
     FROM Posts a
     WHERE a.ParentId = q.QuestionId AND a.PostTypeId = 2) AS AvgAnswerAgeSeconds,
    (SELECT COUNT(*) FROM dup_info d WHERE d.RelatedPostId = q.QuestionId) AS BannedDuplicates,
    (SELECT COUNT(*) FROM dup_info d WHERE d.PostId = q.QuestionId) AS IsDuplicate
  FROM tag_summary ts
  JOIN tagged_questions q ON q.QuestionId = ts.QuestionId
  LEFT JOIN vote_counts vc ON vc.PostId = q.QuestionId
  WHERE q.Score > 0
    AND q.CreationDate > now() - interval '365 days'
    AND ts.TagList ILIKE '%sql%'
)
SELECT
  *,
  RANK() OVER (ORDER BY Score DESC, ViewCount DESC) AS RankByScoreView,
  CASE WHEN IsDuplicate > 0 THEN 'YES' ELSE 'NO' END AS IsDuplicateFlag
FROM question_stats
WHERE BannedDuplicates = 0
ORDER BY RankByScoreView
LIMIT 2000;