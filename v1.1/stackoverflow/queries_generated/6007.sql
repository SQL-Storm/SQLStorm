-- {"query": "6007.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 781} 
WITH RecentPopularQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= NOW() - INTERVAL '30 DAYS'
),
AuthorActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.AccountId,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesReceived,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownvotesReceived,
    COUNT(*) AS TotalVotesCast
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY u.Id
),
TaggedAffinites AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagQuestionCount,
    AVG(p.Score) AS AvgQuestionScore,
    MAX(p.ViewCount) AS MaxQuestionViews
  FROM Tags tg
  JOIN Posts p ON p.Id = tg.ExcerptPostId
  JOIN UNNEST(string_to_array(p.Tags, '><')) AS t ON TRUE
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
HighImpactLinks AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName,
    p.Title AS PostTitle,
    rp.Title AS RelatedPostTitle
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  JOIN Posts p ON p.Id = pl.PostId
  JOIN Posts rp ON rp.Id = pl.RelatedPostId
  WHERE pl.LinkTypeId IN (1,3)
),
WindowedMetrics AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    ROW_NUMBER() OVER (ORDER BY rp.Score DESC, rp.ViewCount DESC, rp.CreationDate DESC) AS rn
  FROM RecentPopularQuestions rp
  WHERE rp.rn <= 50
)
SELECT
  w.PostId,
  w.Title,
  w.CreationDate,
  w.Score,
  w.ViewCount,
  w.Tags,
  a.DisplayName AS Author,
  a.Reputation AS AuthorReputation,
  hl.RelatedPostId,
  hl.LinkTypeName,
  hl.PostTitle AS LinkedPostTitle,
  hl.RelatedPostTitle,
  ta.TagName,
  ta.TagQuestionCount,
  ta.AvgQuestionScore,
  ta.MaxQuestionViews,
  ua.TotalVotesCast,
  ua.UpvotesReceived,
  ua.DownvotesReceived
FROM WindowedMetrics w
LEFT JOIN Posts p ON p.Id = w.PostId
LEFT JOIN Users a ON a.Id = p.OwnerUserId
LEFT JOIN HighImpactLinks hl ON hl.PostId = w.PostId
LEFT JOIN TaggedAffinites ta ON ta.TagName = ANY(string_to_array(p.Tags, '><'))
LEFT JOIN AuthorActivity ua ON ua.UserId = a.Id
WHERE
  (a.Reputation IS NULL OR a.Reputation >= 1000)
  AND (p.LastActivityDate IS NOT NULL)
ORDER BY w.Score DESC, w.ViewCount DESC
LIMIT 100;