-- {"query": "5834.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 649} 
WITH recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Body,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.Location,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate AS UserLastAccessDate,
    b.Name AS BadgeName,
    b.Class AS BadgesClass,
    b.Date AS BadgeDate,
    v.TotalUp AS UpVotesFromVotes
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN (
    SELECT
      PostId,
      SUM(CASE WHEN VT.Id = 2 THEN 1 ELSE 0 END) AS TotalUp
    FROM Votes V
    JOIN VoteTypes VT ON V.VoteTypeId = VT.Id
    GROUP BY PostId
  ) v ON v.PostId = p.Id
  WHERE p.PostTypeId IN (1, 2) -- questions and answers
    AND p.CreationDate >= NOW() - INTERVAL '90 days'
),
tag_stats AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagPostCount,
    AVG(p.Score) AS AvgPostScore,
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.LastActivityDate) AS LastActiveTagPost
  FROM Posts p
  CROSS APPLY (SELECT value AS TagName
               FROM string_to_table(p.Tags, '><')) AS t
  GROUP BY t.TagName
),
correlated_extras AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.Tags,
    ra.OwnerUserId,
    ra.Reputation,
    ra.OwnerDisplayName,
    ra.Body,
    ra.ViewCount,
    ra.Score,
    ra.CommentCount,
    ra.AnswerCount,
    ra.FavoriteCount,
    ra.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY ra.OwnerUserId ORDER BY ra.LastActivityDate DESC) AS rn
  FROM recent_activity ra
)
SELECT
  ce.PostId,
  ce.Title,
  ce.Tags,
  ce.OwnerDisplayName,
  ce.Reputation,
  ce.LastActivityDate,
  ce.ViewCount,
  ce.Score,
  ce.CommentCount,
  ce.AnswerCount,
  ce.FavoriteCount,
  ce.Body,
  ce.ContentLicense,
  ts.TagName,
  ts.TagPostCount,
  ts.AvgPostScore,
  ts.TotalViews,
  ts.LastActiveTagPost
FROM correlated_extras ce
LEFT JOIN tag_stats ts ON true
WHERE ce.rn = 1
  OR ce.LastActivityDate = (
    SELECT MAX(LastActivityDate) FROM recent_activity
  )
ORDER BY ce.LastActivityDate DESC
LIMIT 200;