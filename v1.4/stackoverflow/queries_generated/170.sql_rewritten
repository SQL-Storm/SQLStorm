-- {"query": "170.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1813} 
WITH
-- Base set of questions from the last year
recent_questions AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
    AND p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '365 days')
),

-- For each question, compute number of answers and average answer score
answers_by_question AS (
  SELECT
    a.ParentId AS QuestionId,
    COUNT(a.Id) AS AnswerCount,
    AVG(a.Score) AS AvgAnswerScore
  FROM Posts a
  WHERE a.PostTypeId = 2
  GROUP BY a.ParentId
),

-- Aggregate up-to-date metadata, including a correlated check for an accepted answer
question_metadata AS (
  SELECT
    rq.QuestionId,
    rq.Title,
    rq.OwnerUserId,
    rq.CreationDate,
    rq.LastActivityDate,
    rq.Score,
    rq.ViewCount,
    rq.Tags,
    COALESCE(abq.AnswerCount, 0) AS AnswerCount,
    COALESCE(abq.AvgAnswerScore, 0) AS AvgAnswerScore,
    (SELECT vt.VoteTypeId
     FROM Votes vt
     WHERE vt.PostId = rq.QuestionId
       AND vt.VoteTypeId = 1
     ORDER BY vt.CreationDate DESC
     LIMIT 1) IS NOT NULL AS HasAcceptedAnswer
  FROM recent_questions rq
  LEFT JOIN answers_by_question abq ON abq.QuestionId = rq.QuestionId
),

-- Split and resolve tag names for the visual tag list (best-effort parsing of <tag>...</tag> string)
resolved_tags AS (
  SELECT
    qm.QuestionId,
    string_agg(tt.TagName, ',') AS TagList
  FROM question_metadata qm
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substr(qm.Tags, 2, length(qm.Tags) - 2), '><')) AS TagName
  ) AS t ON TRUE
  LEFT JOIN Tags tt ON tt.TagName = t.TagName
  GROUP BY qm.QuestionId
),

-- Enrich with owner details and moderation-related flags
owner_enrichment AS (
  SELECT
    qm.*,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.CreationDate AS OwnerCreationDate,
    u.LastAccessDate AS OwnerLastAccessDate
  FROM question_metadata qm
  LEFT JOIN Users u ON u.Id = qm.OwnerUserId
),

-- Final ranking with window function and complex predicates
ranked AS (
  SELECT
    oe.QuestionId,
    oe.Title,
    oe.OwnerUserId,
    oe.OwnerDisplayName,
    oe.Reputation,
    oe.CreationDate,
    oe.LastActivityDate,
    oe.Score,
    oe.ViewCount,
    oe.AnswerCount,
    oe.AvgAnswerScore,
    oe.HasAcceptedAnswer,
    rr.TagList,
    ROW_NUMBER() OVER (
      PARTITION BY 1
      ORDER BY
        oe.LastActivityDate DESC NULLS LAST,
        oe.Score DESC NULLS LAST,
        oe.ViewCount DESC NULLS LAST,
        oe.AnswerCount DESC NULLS LAST,
        oe.AvgAnswerScore DESC NULLS LAST
    ) AS rn
  FROM owner_enrichment oe
  LEFT JOIN resolved_tags rr ON rr.QuestionId = oe.QuestionId
)

SELECT
  r.QuestionId,
  r.Title,
  r.OwnerDisplayName AS Owner,
  r.Reputation,
  r.CreationDate,
  r.LastActivityDate,
  r.Score,
  r.ViewCount,
  r.AnswerCount,
  r.AvgAnswerScore,
  r.HasAcceptedAnswer,
  r.TagList
FROM ranked r
WHERE r.rn <= 200
ORDER BY r.LastActivityDate DESC NULLS LAST, r.Score DESC NULLS LAST;