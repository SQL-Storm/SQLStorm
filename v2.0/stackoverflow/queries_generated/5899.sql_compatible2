WITH
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS PostsCreated,
    SUM(p.Score) AS ScoreTotal,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpvotesGiven,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownvotesGiven,
    MAX(p.CreationDate) AS LastPostDate,
    COUNT(DISTINCT bh.Id) AS HistoryEvents
  FROM
    Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
      AND v.VoteTypeId IN (2,3)
    LEFT JOIN PostHistory bh ON bh.UserId = u.Id
  GROUP BY
    u.Id, u.DisplayName
),
UserTagInvolvement AS (
  SELECT
    ua.UserId,
    ts.Tag AS TagName,
    COUNT(*) AS TagPostCount
  FROM
    UserActivity ua
    JOIN Posts p ON p.OwnerUserId = ua.UserId
    JOIN Posts pp ON pp.Id = p.Id
    JOIN LATERAL (
      SELECT regexp_split_to_table(p.Tags, '><') AS Tag
    ) ts ON true
  GROUP BY
    ua.UserId, ts.Tag
  ORDER BY
    TagPostCount DESC
  LIMIT 5
),
DerivedMetrics AS (
  SELECT
    ua.*,
    SUM(ua.ScoreTotal) OVER (ORDER BY ua.ScoreTotal DESC ROWS BETWEEN 4 PRECEDING AND CURRENT ROW) AS RunningScoreWindow,
    ROW_NUMBER() OVER (ORDER BY ua.LastPostDate DESC) AS Rn,
    AVG(ua.PostsCreated) OVER () AS AvgPostsPerUser
  FROM UserActivity ua
)
SELECT
  dm.UserId,
  dm.DisplayName,
  dm.PostsCreated,
  dm.ScoreTotal,
  dm.UpvotesGiven,
  dm.DownvotesGiven,
  dm.LastPostDate,
  dm.HistoryEvents,
  dm.RunningScoreWindow,
  dm.AvgPostsPerUser,
  ARRAY_AGG(DISTINCT ut.TagName) FILTER (WHERE ut.TagName IS NOT NULL) AS TopTags
FROM DerivedMetrics dm
LEFT JOIN UserTagInvolvement ut ON ut.UserId = dm.UserId
GROUP BY
  dm.UserId,
  dm.DisplayName,
  dm.PostsCreated,
  dm.ScoreTotal,
  dm.UpvotesGiven,
  dm.DownvotesGiven,
  dm.LastPostDate,
  dm.HistoryEvents,
  dm.RunningScoreWindow,
  dm.AvgPostsPerUser
ORDER BY dm.RunningScoreWindow DESC
LIMIT 100;