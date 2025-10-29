-- {"query": "5829.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 587}
WITH RankedQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.ContentLicense,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    COUNT(DISTINCT a.Id) AS AnswerCountLive
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
  GROUP BY
    p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score, p.Tags, p.OwnerUserId,
    p.LastActivityDate, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.Body,
    p.ContentLicense, u.DisplayName, u.Reputation
),
TagStats AS (
  SELECT
    t.TagName,
    t.Count AS TagCount,
    (
      SELECT MAX(p2.CreationDate)
      FROM Posts p2
      WHERE p2.Tags LIKE '%' || t.TagName || '%'
    ) AS LatestPostDate
  FROM Tags t
  WHERE t.TagName IS NOT NULL
),
RecentTopTags AS (
  SELECT
    t.TagName,
    t.TagCount,
    ROW_NUMBER() OVER (ORDER BY t.TagCount DESC, t.TagName ASC) AS rn
  FROM TagStats t
  WHERE t.LatestPostDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days'
)
SELECT
  rq.PostId,
  rq.Title,
  rq.OwnerDisplayName,
  rq.Reputation AS OwnerReputation,
  rq.CreationDate,
  rq.LastActivityDate,
  rq.ViewCount,
  rq.Score,
  rq.AnswerCountLive AS LiveAnswerCount,
  rq.Tags,
  rq.Body,
  rq.ContentLicense,
  rgm.TagName AS MostUsedTag,
  rgm.TagCount AS TagFrequency,
  CASE WHEN rq.Score > 0 THEN 'Positive' WHEN rq.Score < 0 THEN 'Negative' ELSE 'Neutral' END AS ScoreCategory,
  (
    SELECT COUNT(*)
    FROM Posts p3
    WHERE p3.OwnerUserId = rq.OwnerUserId
      AND p3.PostTypeId = 1
  ) AS QuestionsByUser
FROM RankedQuestions rq
LEFT JOIN (
  SELECT rtt.TagName, rtt.TagCount
  FROM RecentTopTags rtt
  WHERE rtt.rn = 1
) rgm ON 1 = 1
ORDER BY rq.LastActivityDate DESC
LIMIT 100;