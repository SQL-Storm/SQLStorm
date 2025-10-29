-- {"query": "5265.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 716} 
WITH recent_question_activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    -- total upvotes minus downvotes per post (approx by summing votes)
    SUM(CASE WHEN vvt.Id = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS UpVotes,
    SUM(CASE WHEN vvt.Id = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS DownVotes
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN VoteTypes vvt ON v.VoteTypeId = vvt.Id
  WHERE p.PostTypeId = 1 -- questions
    AND p.ClosedDate IS NULL
),
popular_tags AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagQuestionCount,
    AVG(rqa.ViewCount) AS AvgViewCount,
    AVG(rqa.Score) AS AvgScore
  FROM recent_question_activity rqa
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substr(rqa.Tags, 2, length(rqa.Tags) - 2), '><')) AS TagName
  ) AS t
  GROUP BY t.TagName
),
dual AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerDisplayName,
    p.OwnerUserId,
    p.Tags,
    p.ViewCount,
    p.Score,
    'Q' AS Kind
  FROM Posts p
  WHERE p.PostTypeId = 1
),
corr AS (
  SELECT
    d.PostId,
    d.Title,
    d.CreationDate,
    d.LastActivityDate,
    d.OwnerDisplayName,
    d.OwnerUserId,
    d.Tags,
    d.ViewCount,
    d.Score,
    rqa.UpVotes,
    rqa.DownVotes,
    pc.TagName AS MostUsedTag,
    pc.TagQuestionCount
  FROM dual d
  LEFT JOIN recent_question_activity rqa ON rqa.PostId = d.PostId
  LEFT JOIN (
    SELECT
      TagName,
      MAX(TagQuestionCount) AS TagQuestionCount
    FROM popular_tags
    GROUP BY TagName
  ) pc ON true
),
ranked AS (
  SELECT
    c.*,
    ROW_NUMBER() OVER (
      PARTITION BY c.MostUsedTag
      ORDER BY c.ViewCount * 1.0 / NULLIF(c.Score,0) DESC,
               c.CreationDate DESC
    ) AS rn
  FROM corr c
)
SELECT
  r.PostId,
  r.Title,
  r.CreationDate,
  r.LastActivityDate,
  r.OwnerDisplayName,
  r.OwnerUserId,
  r.Tags,
  r.ViewCount,
  r.Score,
  r.UpVotes,
  r.DownVotes,
  r.MostUsedTag,
  r.TagQuestionCount
FROM ranked r
WHERE r.rn = 1
ORDER BY r.MostUsedTag NULLS LAST, r.ViewCount DESC
LIMIT 100;