WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90 days'
),
top_tags AS (
  SELECT
    unn.unnest_tag AS TagName,
    COUNT(*) AS QuestionCount
  FROM Tags tg
  JOIN Posts p ON p.Id = tg.ExcerptPostId
  CROSS JOIN LATERAL (
    SELECT unnest_tag
    FROM UNNEST(string_to_array(tg.TagName, '><')) AS t(unnest_tag)
  ) AS unn(unnest_tag)
  GROUP BY unn.unnest_tag
  ORDER BY QuestionCount DESC
  LIMIT 20
),
user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreation,
    MAX(p.LastActivityDate) AS LastPostActivity,
    COUNT(p.Id) AS PostCount,
    AVG(p.Score) AS AvgPostScore
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
complex_metrics AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.CreationDate,
    rq.OwnerUserId,
    rq.ViewCount,
    rq.Score,
    rq.Tags,
    (rq.Score * 1.0 / NULLIF(rq.ViewCount,0)) AS ScorePerView,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rq.PostId) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rq.PostId AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rq.PostId AND v.VoteTypeId = 3) AS DownVotes,
    CASE
      WHEN rq.LastActivityDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '7 days' THEN true
      ELSE false
    END AS RecentlyActive,
    rq.LastActivityDate
  FROM recent_questions rq
)
SELECT
  cm.PostId,
  cm.Title,
  cm.CreationDate,
  cm.OwnerUserId,
  cm.ViewCount,
  cm.Score,
  cm.Tags,
  cm.ScorePerView,
  cm.CommentCount,
  cm.UpVotes,
  cm.DownVotes,
  cm.RecentlyActive,
  ua.UserId AS AuthorUserId,
  ua.DisplayName AS AuthorDisplayName,
  ua.Reputation AS AuthorReputation,
  ua.LastPostActivity,
  ua.PostCount,
  ua.AvgPostScore,
  tt.TagName
FROM complex_metrics cm
LEFT JOIN user_activity ua ON cm.OwnerUserId = ua.UserId
LEFT JOIN LATERAL (
  SELECT tg.TagName
  FROM Tags tg
  JOIN Posts p ON p.Id = tg.ExcerptPostId
  WHERE p.Id = cm.PostId
  LIMIT 1
) AS tt ON TRUE
LEFT JOIN top_tags tt2 ON TRUE
GROUP BY
  cm.PostId,
  cm.Title,
  cm.CreationDate,
  cm.OwnerUserId,
  cm.ViewCount,
  cm.Score,
  cm.Tags,
  cm.ScorePerView,
  cm.CommentCount,
  cm.UpVotes,
  cm.DownVotes,
  cm.RecentlyActive,
  cm.LastActivityDate,
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.LastPostActivity,
  ua.PostCount,
  ua.AvgPostScore,
  tt.TagName
ORDER BY cm.ScorePerView DESC NULLS LAST, cm.Score DESC, cm.ViewCount DESC
LIMIT 100;