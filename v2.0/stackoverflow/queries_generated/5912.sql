-- {"query": "5912.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 797} 
WITH 
TopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.LastActivityDate,
    p.PostTypeId,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC, p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
),
TagStats AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
    COUNT(*) AS QuestionCount,
    AVG(p.ViewCount) AS AvgViews,
    AVG(p.Score) AS AvgScore
  FROM Posts p
  JOIN TopQuestions tq ON p.Id = tq.PostId
  GROUP BY unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><'))
),
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.LastActivityDate,
    v.VoteTypeId,
    v.UserId AS VoterId,
    v.CreationDate AS VoteDate
  FROM Posts p
  LEFT JOIN Votes v ON p.Id = v.PostId
  WHERE p.LastActivityDate > NOW() - INTERVAL '30 days'
),
CorrelatedSummary AS (
  SELECT
    tq.PostId,
    tq.Title,
    tq.OwnerUserId,
    tq.LastActivityDate,
    COALESCE(r1.Score, 0) AS LatestScore,
    COALESCE(vc.UpVotes, 0) AS UpVotesLast30Days
  FROM TopQuestions tq
  LEFT JOIN (
    SELECT PostId, MAX(Score) AS Score
    FROM Posts
    GROUP BY PostId
  ) r1 ON tq.PostId = r1.PostId
  LEFT JOIN (
    SELECT PostId, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes
    FROM Votes v
    GROUP BY PostId
  ) vc ON tq.PostId = vc.PostId
)
SELECT
  cq.PostId,
  cq.Title,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  u.CreationDate AS OwnerSince,
  cq.LastActivityDate,
  cq.LatestScore,
  cq.UpVotesLast30Days,
  (SELECT COUNT(*) FROM Comments cm WHERE cm.PostId = cq.PostId) AS CommentCount,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = cq.PostId) AS LinkCount,
  (SELECT COUNT(*) FROM Votes vv WHERE vv.PostId = cq.PostId AND vv.VoteTypeId = 2) AS UpVotesTotal,
  STRING_AGG(DISTINCT tt.TagName, ',') AS TagsUsed,
  (SELECT COUNT(*) FROM Votes vv WHERE vv.PostId = cq.PostId AND vv.VoteTypeId IN (2,7,8)) AS EngagementScore
FROM CorrelatedSummary cq
JOIN Users u ON cq.OwnerUserId = u.Id
LEFT JOIN TopQuestions tq ON cq.PostId = tq.PostId
LEFT JOIN (
  SELECT
    p.OwnerUserId,
    STRING_AGG(DISTINCT t.TagName, ',') AS TagNames
  FROM Posts p
  JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
  WHERE p.PostTypeId = 1
  GROUP BY p.OwnerUserId
) usrTags ON u.Id = usrTags.OwnerUserId
ORDER BY cq.LatestScore DESC, cq.UpVotesLast30Days DESC
LIMIT 100;