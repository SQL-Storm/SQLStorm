-- {"query": "39010.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2700} 
WITH
RecentQuestions AS (
  SELECT
    p.Id,
    p.Title,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate BETWEEN cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year' AND cast('2024-10-01 12:34:56' as timestamp)
),
TagPairs AS (
  SELECT
    rq.Id   AS QuestionId,
    tag     AS Tag
  FROM RecentQuestions rq
  CROSS JOIN LATERAL
    unnest(
      string_to_array(
        substring(rq.Tags, 2, length(rq.Tags) - 2),
        '><'
      )
    ) AS t(tag)
),
AnswerScores AS (
  SELECT
    ap.ParentId            AS QuestionId,
    COUNT(*) FILTER (WHERE ap.Score > 0) AS PositiveAnswerCount,
    AVG(ap.Score)          AS AvgAnswerScore
  FROM Posts ap
  WHERE ap.PostTypeId = 2
    AND ap.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
  GROUP BY ap.ParentId
),
VoteStats AS (
  SELECT
    v.PostId  AS QuestionId,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes
  FROM Votes v
  GROUP BY v.PostId
),
EditorStats AS (
  SELECT
    ph.PostId             AS QuestionId,
    COUNT(DISTINCT ph.UserId)
      FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS EditorCount
  FROM PostHistory ph
  WHERE ph.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
  GROUP BY ph.PostId
),
BadgeStats AS (
  SELECT
    p.ParentId            AS QuestionId,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldAwards,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverAwards,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeAwards
  FROM Posts p
  JOIN Badges b ON b.UserId = p.OwnerUserId
  WHERE p.PostTypeId = 2
    AND b.Date >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
  GROUP BY p.ParentId
),
LinkStats AS (
  SELECT
    pl.PostId            AS QuestionId,
    COUNT(*) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateLinks
  FROM PostLinks pl
  GROUP BY pl.PostId
),
Aggregated AS (
  SELECT
    tp.Tag,
    rq.Id                 AS QuestionId,
    rq.Title,
    rq.Score,
    rq.ViewCount,
    COALESCE(rs.PositiveAnswerCount, 0) AS PositiveAnswerCount,
    COALESCE(rs.AvgAnswerScore, 0)       AS AvgAnswerScore,
    COALESCE(vs.UpVotes, 0)              AS UpVotes,
    COALESCE(vs.DownVotes, 0)            AS DownVotes,
    COALESCE(es.EditorCount, 0)          AS EditorCount,
    COALESCE(bs.GoldAwards, 0)           AS GoldAwards,
    COALESCE(bs.SilverAwards, 0)         AS SilverAwards,
    COALESCE(bs.BronzeAwards, 0)         AS BronzeAwards,
    COALESCE(ls.DuplicateLinks, 0)       AS DuplicateLinks,
    ROW_NUMBER() OVER (PARTITION BY tp.Tag ORDER BY rq.ViewCount DESC) AS TagRank
  FROM TagPairs tp
  JOIN RecentQuestions rq ON rq.Id = tp.QuestionId
  LEFT JOIN AnswerScores rs ON rs.QuestionId = tp.QuestionId
  LEFT JOIN VoteStats vs      ON vs.QuestionId = tp.QuestionId
  LEFT JOIN EditorStats es    ON es.QuestionId = tp.QuestionId
  LEFT JOIN BadgeStats bs     ON bs.QuestionId = tp.QuestionId
  LEFT JOIN LinkStats ls      ON ls.QuestionId = tp.QuestionId
),
TopQuestions AS (
  SELECT * 
  FROM Aggregated
  WHERE TagRank <= 5
)
SELECT
  Tag,
  QuestionId,
  Title,
  Score,
  ViewCount,
  PositiveAnswerCount,
  AvgAnswerScore,
  UpVotes,
  DownVotes,
  EditorCount,
  GoldAwards,
  SilverAwards,
  BronzeAwards,
  DuplicateLinks
FROM TopQuestions
ORDER BY Tag, ViewCount DESC;