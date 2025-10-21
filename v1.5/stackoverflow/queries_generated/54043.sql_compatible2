WITH
  UserQuestionStats AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(p.Id) AS TotalQuestions,
      SUM(p.Score) AS TotalScore,
      ROUND(AVG(p.Score), 2) AS AvgScore,
      MAX(p.CreationDate) AS LastPost
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName, u.Reputation
  ),
  UserTagFreq AS (
    SELECT
      uqs.UserId,
      tag.TagName,
      COUNT(*) AS TagCount
    FROM UserQuestionStats uqs
    JOIN Posts p ON p.OwnerUserId = uqs.UserId AND p.PostTypeId = 1
    JOIN LATERAL (
      SELECT UNNEST(REGEXP_SPLIT_TO_ARRAY(p.Tags, '<|>')) AS TagName
    ) AS split ON TRUE
    JOIN Tags tag ON tag.TagName = split.TagName
    GROUP BY uqs.UserId, tag.TagName
  ),
  UserTopTags AS (
    SELECT
      UserId,
      STRING_AGG(TagName || ':' || TagCount, ', ' ORDER BY TagCount DESC, TagName ASC) AS TopTags
    FROM UserTagFreq
    GROUP BY UserId
  ),
  UserVotes AS (
    SELECT
      p.OwnerUserId AS UserId,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
    FROM Posts p
    JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
  )
SELECT
  uqs.UserId,
  uqs.DisplayName,
  uqs.Reputation,
  uqs.TotalQuestions,
  uqs.TotalScore,
  uqs.AvgScore,
  uqs.LastPost,
  COALESCE(ut.TopTags, '') AS TopTags,
  COALESCE(uv.TotalUpVotes, 0) AS TotalUpVotes,
  COALESCE(uv.TotalDownVotes, 0) AS TotalDownVotes
FROM UserQuestionStats uqs
LEFT JOIN UserTopTags ut ON ut.UserId = uqs.UserId
LEFT JOIN UserVotes uv ON uv.UserId = uqs.UserId
ORDER BY uqs.AvgScore DESC, uqs.TotalScore DESC
LIMIT 20;