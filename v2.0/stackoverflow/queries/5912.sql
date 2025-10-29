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
  WHERE p.PostTypeId = 1
),
TagStats AS (
  SELECT
    tname AS TagName,
    COUNT(*) AS QuestionCount,
    AVG(p.ViewCount) AS AvgViews,
    AVG(p.Score) AS AvgScore
  FROM Posts p
  JOIN TopQuestions tq ON p.Id = tq.PostId
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS tname
  ) u
  GROUP BY tname
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
  WHERE p.LastActivityDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days')
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
    SELECT p.Id AS PostId, MAX(p.Score) AS Score
    FROM Posts p
    GROUP BY p.Id
  ) r1 ON tq.PostId = r1.PostId
  LEFT JOIN (
    SELECT v.PostId, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes
    FROM Votes v
    GROUP BY v.PostId
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
LEFT JOIN LATERAL (
  SELECT unnest(string_to_array(substr(tq.Tags,2,length(tq.Tags)-2),'><')) AS TagName
) tt ON TRUE
GROUP BY
  cq.PostId,
  cq.Title,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  cq.LastActivityDate,
  cq.LatestScore,
  cq.UpVotesLast30Days
ORDER BY cq.LatestScore DESC, cq.UpVotesLast30Days DESC
LIMIT 100;