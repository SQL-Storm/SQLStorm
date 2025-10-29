-- {"query": "5899.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 621} 
WITH
-- sample aggregated activity window per user
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
      AND v.VoteTypeId IN (2,3) -- up and down votes
    LEFT JOIN PostHistory bh ON bh.UserId = u.Id
  GROUP BY
    u.Id, u.DisplayName
),
-- correlation subquery: top 5 tags by involvement in posts created by each user
UserTagInvolvement AS (
  SELECT
    ua.UserId,
    t.TagName,
    COUNT(*) AS TagPostCount
  FROM
    UserActivity ua
    JOIN Posts p ON p.OwnerUserId = ua.UserId
    JOIN Posts pp ON pp.Id = p.Id
    CROSS APPLY (SELECT unnest(string_to_array(p.Tags, '><')) AS Tag) AS TagSplit -- placeholder for portability
  GROUP BY
    ua.UserId, t.TagName
  ORDER BY
    TagPostCount DESC
  LIMIT 5
),
-- compute a complex derived metric using window functions
DerivedMetrics AS (
  SELECT
    ua.*,
    SUM(ua.ScoreTotal) OVER (ORDER BY ua.ScoreTotal DESC ROWS BETWEEN 4 PRECEDING AND CURRENT_ROW) AS RunningScoreWindow,
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