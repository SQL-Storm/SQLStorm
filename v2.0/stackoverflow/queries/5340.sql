-- {"query": "5340.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 863}
WITH
RecentViews AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
),
AuthorStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.CreationDate AS UserCreationDate,
    COUNT(p.Id) FILTER (WHERE p.Id IS NOT NULL) AS QuestionCount,
    AVG(p.Score) AS AvgQuestionScore,
    MAX(p.LastActivityDate) AS LastActiveQuestionDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  WHERE u.Id IS NOT NULL
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
TagPopularity AS (
  SELECT
    tags.TagName,
    COUNT(*) AS TagCount,
    SUM(p.Score) AS TotalScore
  FROM Posts p
  JOIN (
    SELECT p2.Id,
           -- split tags like '<tag1><tag2>' into rows in a dialect-neutral way
           -- using a simple recursive split for compatibility
           unnest_tags.tag AS TagName
    FROM Posts p2,
    LATERAL (
      SELECT value AS tag
      FROM (
        SELECT trim(both '<>' FROM regexp_split_to_table(p2.Tags, '><')) AS value
      ) t
    ) AS unnest_tags
  ) AS tags ON tags.Id = p.Id
  JOIN Tags tt ON tt.TagName = tags.TagName
  GROUP BY tags.TagName
),
ActivityTrend AS (
  SELECT
    p.OwnerUserId,
    DATE_TRUNC('month', p.CreationDate) AS MonthKey,
    COUNT(*) AS QCount,
    SUM(p.ViewCount) AS TotalViews
  FROM Posts p
  GROUP BY p.OwnerUserId, DATE_TRUNC('month', p.CreationDate)
),
ComplexQuery AS (
  SELECT
    r.PostId,
    r.Title,
    r.Tags,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    a.UserId AS AuthorId,
    a.DisplayName AS AuthorName,
    a.Reputation,
    a.AvgQuestionScore,
    a.LastActiveQuestionDate,
    EXISTS (
      SELECT 1
      FROM Votes v
      JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
      WHERE v.PostId = r.PostId
        AND vt.Name ILIKE '%UpMod%'
        AND v.CreationDate > (r.LastActivityDate - INTERVAL '30 days')
    ) AS HadRecentUpvote,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = r.PostId) AS LinkCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = r.PostId) AS CommentCount,
    CASE
      WHEN r.Tags LIKE '%<python>%' THEN 'Python'
      WHEN r.Tags LIKE '%<sql>%' THEN 'SQL'
      ELSE 'Other'
    END AS PrimaryTag,
    r.OwnerUserId,
    r.LastActivityDate,
    r.rn
  FROM RecentViews r
  JOIN AuthorStats a ON a.UserId = r.OwnerUserId
  WHERE r.rn = 1
)
SELECT
  cq.PostId,
  cq.Title,
  cq.Tags,
  cq.CreationDate,
  cq.Score,
  cq.ViewCount,
  cq.AuthorId,
  cq.AuthorName,
  cq.Reputation,
  cq.AvgQuestionScore,
  cq.LastActiveQuestionDate,
  cq.HadRecentUpvote,
  cq.LinkCount,
  cq.CommentCount,
  cq.PrimaryTag,
  (SELECT MAX(at.TotalViews) FROM ActivityTrend at WHERE at.OwnerUserId = cq.AuthorId) AS MaxMonthlyViews,
  (SELECT SUM(at.TotalViews) FROM ActivityTrend at WHERE at.OwnerUserId = cq.AuthorId) AS TotalViewsByAuthor
FROM ComplexQuery cq
ORDER BY cq.Reputation DESC NULLS LAST, cq.Score DESC, cq.ViewCount DESC
LIMIT 100;