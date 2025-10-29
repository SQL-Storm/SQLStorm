WITH
RecentTopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.AnswerCount,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    COUNT(DISTINCT c.Id) AS CommentCountLast30,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGivenLast30,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGivenLast30
  FROM Users u
  LEFT JOIN Comments c ON c.UserId = u.Id AND c.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
  LEFT JOIN Votes v ON v.UserId = u.Id AND v.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostLinksAgg AS (
  SELECT
    pl.PostId,
    COUNT(CASE WHEN lt.Name ILIKE '%duplicate%' THEN 1 END) AS DuplicateLinks,
    COUNT(*) AS TotalLinks
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  GROUP BY pl.PostId
),
TagStats AS (
  SELECT
    t.TagName,
    t.Count,
    COALESCE(p.ViewCount, 0) AS PlaceholderViewCount
  FROM Tags t
  LEFT JOIN Posts p ON p.Id = t.WikiPostId
),
ExpandedRecent AS (
  SELECT
    rtp.PostId,
    rtp.Title,
    rtp.OwnerUserId,
    rtp.CreationDate,
    rtp.ViewCount,
    rtp.Score,
    rtp.AnswerCount,
    rtp.Tags,
    COALESCE(ups.UpvotesLast30, 0) AS UpvotesLast30
  FROM RecentTopPosts rtp
  LEFT JOIN (
    SELECT
      p.OwnerUserId,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesLast30
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
    GROUP BY p.OwnerUserId
  ) ups ON ups.OwnerUserId = rtp.OwnerUserId
  WHERE rtp.rn <= 5
),
PostComments30 AS (
  SELECT
    p.Id AS PostId,
    COUNT(c.Id) AS CommentCountLast30
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id AND c.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
  GROUP BY p.Id
)
SELECT
  er.PostId,
  er.Title,
  er.OwnerUserId,
  er.CreationDate,
  er.ViewCount,
  er.Score,
  er.AnswerCount,
  er.Tags,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  ua.CommentCountLast30 AS UserCommentCountLast30,
  ua.UpvotesGivenLast30 AS UserUpvotesGivenLast30,
  ua.DownvotesGivenLast30 AS UserDownvotesGivenLast30,
  COALESCE(pla.DuplicateLinks, 0) AS DuplicateLinks,
  COALESCE(pla.TotalLinks, 0) AS TotalLinks,
  ts.TagName,
  ts.Count AS TagCount,
  CASE
    WHEN er.Score > 0 THEN 'Positive'
    WHEN er.Score = 0 THEN 'Neutral'
    ELSE 'Negative'
  END AS ScoreTrend,
  ARRAY_AGG(DISTINCT v2.VoteTypeId) AS VoteTypesOnPost,
  COALESCE(pc30.CommentCountLast30, 0) AS PostCommentCountLast30,
  er.UpvotesLast30
FROM ExpandedRecent er
JOIN Users u ON u.Id = er.OwnerUserId
LEFT JOIN UserActivity ua ON ua.UserId = er.OwnerUserId
LEFT JOIN PostLinksAgg pla ON pla.PostId = er.PostId
LEFT JOIN Votes v2 ON v2.PostId = er.PostId
LEFT JOIN LATERAL (
  SELECT t2.TagName
  FROM UNNEST(STRING_TO_ARRAY(REPLACE(REPLACE(er.Tags, '<', ''), '>', ''), '><')) AS t2(TagName)
) taglist ON true
LEFT JOIN Tags t ON t.TagName = taglist.TagName
LEFT JOIN TagStats ts ON ts.TagName = t.TagName
LEFT JOIN PostComments30 pc30 ON pc30.PostId = er.PostId
GROUP BY
  er.PostId, er.Title, er.OwnerUserId, er.CreationDate, er.ViewCount, er.Score, er.AnswerCount,
  er.Tags, u.DisplayName, u.Reputation, ua.CommentCountLast30, ua.UpvotesGivenLast30,
  ua.DownvotesGivenLast30, pla.DuplicateLinks, pla.TotalLinks, ts.TagName, ts.Count,
  CASE
    WHEN er.Score > 0 THEN 'Positive'
    WHEN er.Score = 0 THEN 'Neutral'
    ELSE 'Negative'
  END,
  pc30.CommentCountLast30, er.UpvotesLast30
ORDER BY er.Score DESC NULLS LAST, er.ViewCount DESC
LIMIT 20;