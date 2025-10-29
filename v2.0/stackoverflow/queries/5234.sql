-- {"query": "5234.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 858}
WITH RankedPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.Tags,
    p.Body,
    p.FavoriteCount,
    p.CommentCount,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.Score DESC,
        p.ViewCount * 0.5 + COALESCE(p.FavoriteCount,0) * 2 +
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - p.CreationDate)) * 0.0
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.ClosedDate IS NULL
    AND p.PostTypeId IN (1,2)
),
TopQuestions AS (
  SELECT
    rp.Id,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerUserId,
    rp.Tags,
    rp.LastActivityDate,
    rp.Body
  FROM RankedPosts rp
  WHERE rp.PostTypeId = 1 AND rp.rn <= 20
),
TagUsage AS (
  SELECT
    dt.TagName,
    COUNT(*) AS TagCount,
    SUM(p.ViewCount) AS TotalViews,
    AVG(p.Score) AS AvgScore
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT UNNEST(string_to_array(SUBSTR(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS TagName
  ) AS dt
  WHERE p.PostTypeId = 1
  GROUP BY dt.TagName
),
RecentActivity AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.LastActivityDate,
    v.VoteTypeId,
    v.CreationDate AS VoteDate,
    u.Reputation
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.LastActivityDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
    AND p.PostTypeId = 1
),
Composite AS (
  SELECT
    tq.Id AS QuestionId,
    tq.Title,
    tq.CreationDate,
    tq.Score AS QuestionScore,
    ta.LastActivityDate AS ActivityDate,
    ta.OwnerUserId AS OwnerId,
    u.Reputation,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = tq.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = tq.Id) AS AnswerCount,
    ARRAY_AGG(DISTINCT tt.TagName) AS Tags
  FROM TopQuestions tq
  LEFT JOIN RecentActivity ta ON ta.Id = tq.Id
  LEFT JOIN Users u ON tq.OwnerUserId = u.Id
  LEFT JOIN LATERAL (
    SELECT UNNEST(string_to_array(SUBSTR(tq.Tags, 2, LENGTH(tq.Tags)-2), '><')) AS TagName
  ) tt ON true
  GROUP BY tq.Id, tq.Title, tq.CreationDate, tq.Score, ta.LastActivityDate, ta.OwnerUserId, u.Reputation
)
SELECT
  c.QuestionId,
  c.Title,
  c.CreationDate,
  c.ActivityDate,
  c.QuestionScore,
  c.OwnerId,
  c.Reputation,
  c.CommentCount,
  c.AnswerCount,
  c.Tags,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = c.QuestionId AND pl.LinkTypeId = 1) AS LinkedCount,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = c.QuestionId AND v.VoteTypeId = 2) AS UpVotes,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = c.QuestionId AND v.VoteTypeId = 3) AS DownVotes
FROM Composite c
ORDER BY c.QuestionScore DESC, c.ActivityDate DESC
LIMIT 100;