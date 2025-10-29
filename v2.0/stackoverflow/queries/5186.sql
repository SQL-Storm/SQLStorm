-- {"query": "5186.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 749}
WITH RecentHotQuestions AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.OwnerDisplayName,
    AVG(v.BountyAmount) OVER (PARTITION BY p.Id) AS AvgBounty
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
),
TopTags AS (
  SELECT
    tag.Tag AS Tag,
    SUM(CASE WHEN p.OwnerUserId IS NOT NULL THEN 1 ELSE 0 END) AS PostCount,
    MAX(p.Score) AS MaxScore
  FROM Posts p,
       LATERAL (
         SELECT TRIM(value) AS Tag
         FROM (
           SELECT UNNEST(STRING_TO_ARRAY(COALESCE(p.Tags, ''), ',')) AS value
         ) s
       ) tag
  GROUP BY tag.Tag
),
DifficultyWindow AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.OwnerDisplayName,
    ROW_NUMBER() OVER (
      PARTITION BY CAST(p.CreationDate AS DATE)
      ORDER BY p.Score DESC, p.ViewCount DESC
    ) AS DayRank
  FROM Posts p
  WHERE p.PostTypeId = 1
),
CorrelatedComments AS (
  SELECT
    c.PostId,
    c.Id AS CommentId,
    c.Score,
    c.Text,
    c.CreationDate,
    c.UserDisplayName,
    c.UserId,
    ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.Score DESC, c.CreationDate DESC) AS CommentRank
  FROM Comments c
),
Aggregated AS (
  SELECT
    r.QuestionId,
    r.Title,
    r.CreationDate,
    r.LastActivityDate,
    r.Score,
    r.ViewCount,
    r.Tags,
    r.OwnerUserId,
    r.OwnerDisplayName,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = r.QuestionId AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = r.QuestionId AND v.VoteTypeId = 3) AS DownVotes,
    (SELECT COUNT(*) FROM Comments co WHERE co.PostId = r.QuestionId) AS CommentCount,
    (SELECT AVG(v2.BountyAmount) FROM Votes v2 WHERE v2.PostId = r.QuestionId AND v2.BountyAmount IS NOT NULL) AS AvgBounty
  FROM RecentHotQuestions r
)
SELECT
  a.QuestionId,
  a.Title,
  a.CreationDate,
  a.LastActivityDate,
  a.Score,
  a.ViewCount,
  a.Tags,
  a.OwnerUserId,
  a.OwnerDisplayName,
  a.UpVotes,
  a.DownVotes,
  a.CommentCount,
  a.AvgBounty,
  (
    SELECT STRING_AGG(t.Tag, ',')
    FROM (
      SELECT TRIM(value) AS Tag
      FROM (
        SELECT UNNEST(STRING_TO_ARRAY(COALESCE(a.Tags, ''), ',')) AS value
      ) s
    ) t
  ) AS TagList,
  (SELECT COUNT(*) FROM CorrelatedComments cc WHERE cc.PostId = a.QuestionId AND cc.CommentRank = 1) AS TopCommentFlag
FROM Aggregated a
ORDER BY a.LastActivityDate DESC, a.Score DESC
OFFSET 0
FETCH NEXT 100 ROWS ONLY;