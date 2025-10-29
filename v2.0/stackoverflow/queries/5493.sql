-- {"query": "5493.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 781}
WITH
RecentQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days'
),
TopTags AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
    p.Id AS PostId
  FROM Posts p
  WHERE p.PostTypeId = 1
),
TagPopularity AS (
  SELECT
    t.TagName,
    COUNT(*) AS QCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.CreationDate) AS LatestQuestion
  FROM TopTags t
  JOIN Posts p ON p.Id = t.PostId
  GROUP BY t.TagName
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT qc.Id) AS ReqAnswered,
    COUNT(DISTINCT v.Id) AS VotedPosts
  FROM Users u
  LEFT JOIN Posts qc ON qc.OwnerUserId = u.Id AND qc.PostTypeId = 1
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
ComplexBench AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    rq.OwnerDisplayName,
    rq.CommentCount,
    rq.AnswerCount,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = rq.PostId) AS ChildAnswers,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rq.PostId) AS LinkedCount,
    (SELECT MIN(v.CreationDate) FROM Votes v WHERE v.PostId = rq.PostId AND v.VoteTypeId = 2) AS FirstUpVoteDate,
    (SELECT COUNT(*) FROM Votes v3 WHERE v3.PostId = rq.PostId AND v3.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v4 WHERE v4.PostId = rq.PostId AND v4.VoteTypeId = 3) AS DownVotes,
    rq.OwnerUserId
  FROM RecentQuestions rq
)
SELECT
  br.TagName,
  br.QCount,
  br.AvgScore,
  br.TotalViews,
  br.LatestQuestion,
  ua.UserId,
  ua.DisplayName AS UserDisplayName,
  ua.Reputation,
  ca.ChildAnswers,
  ca.LinkedCount,
  ca.FirstUpVoteDate,
  ca.UpVotes,
  ca.DownVotes,
  ca.Score AS QuestionScore,
  ca.ViewCount AS QuestionViews
FROM TagPopularity br
LEFT JOIN (
  SELECT
    tt.TagName,
    MAX(p.Score) AS MaxScore,
    MAX(tt.PostId) AS MaxPostId
  FROM TopTags tt
  JOIN Posts p ON p.Id = tt.PostId
  GROUP BY tt.TagName
) t ON t.TagName = br.TagName
LEFT JOIN ComplexBench ca ON ca.PostId = t.MaxPostId
LEFT JOIN Users u ON u.Id = ca.OwnerUserId
LEFT JOIN UserActivity ua ON ua.UserId = u.Id
WHERE br.QCount > 5
ORDER BY br.TotalViews DESC, br.AvgScore DESC
LIMIT 100;