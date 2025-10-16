WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.CommunityOwnedDate,
    ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
),
tag_stats AS (
  SELECT
    t.tag,
    COUNT(*) AS post_count,
    AVG(p.Score) AS avg_score,
    SUM(p.ViewCount) AS total_views
  FROM Posts p
  JOIN recent_questions rq ON rq.PostId = p.Id
  CROSS JOIN LATERAL (
    SELECT TRIM(BOTH '<>' FROM part_text) AS tag
    FROM (
      SELECT unnest(string_to_array(p.Tags, '><')) AS part_text
    ) AS derived
  ) t
  WHERE p.Tags IS NOT NULL
  GROUP BY t.tag
),
top_tags AS (
  SELECT
    tag,
    post_count,
    avg_score,
    total_views
  FROM tag_stats
  ORDER BY post_count DESC, avg_score DESC
  LIMIT 20
),
author_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesGiven,
    MAX(CASE WHEN p.OwnerUserId = u.Id THEN p.CreationDate END) AS LastOwnPostDate,
    AVG(p.ViewCount) AS AvgPostViews
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
activity_with_ranks AS (
  SELECT
    a.UserId,
    a.DisplayName,
    a.UpVotesGiven,
    a.DownVotesGiven,
    a.LastOwnPostDate,
    a.AvgPostViews,
    ROW_NUMBER() OVER (ORDER BY (a.UpVotesGiven - a.DownVotesGiven) DESC NULLS LAST, a.AvgPostViews DESC NULLS LAST) AS rank
  FROM author_activity a
)
SELECT
  rq.PostId,
  rq.Title AS QuestionTitle,
  rq.Tags,
  rq.CreationDate AS QuestionCreated,
  rq.Score AS QuestionScore,
  rq.ViewCount AS QuestionViews,
  u.Id AS AuthorId,
  u.DisplayName AS AuthorName,
  COALESCE(awr.rank, 9999) AS AuthorRank,
  ts.tag AS TagName,
  ts.post_count AS TagPostCount,
  ts.avg_score AS TagAvgScore,
  ts.total_views AS TagTotalViews
FROM recent_questions rq
JOIN Users u ON u.Id = rq.OwnerUserId
LEFT JOIN activity_with_ranks awr ON awr.UserId = u.Id
LEFT JOIN top_tags ts ON 1=1
WHERE (awr.rank = 1) OR (ts.tag IS NOT NULL)
GROUP BY
  rq.PostId,
  rq.Title,
  rq.Tags,
  rq.CreationDate,
  rq.Score,
  rq.ViewCount,
  u.Id,
  u.DisplayName,
  awr.rank,
  ts.tag,
  ts.post_count,
  ts.avg_score,
  ts.total_views
ORDER BY rq.CreationDate DESC
LIMIT 100;