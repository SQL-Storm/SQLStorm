-- {"query": "4871.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1384} 

WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.FavoriteCount,
    pt.Name AS PostTypeName,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts AS p
  JOIN PostTypes AS pt
    ON p.PostTypeId = pt.Id
  WHERE
    p.OwnerUserId IS NOT NULL AND p.Score > 0
), PostAggregates AS (
  SELECT
    p.Id AS PostId,
    COUNT(c.Id) AS CommentCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
    MAX(p.CreationDate) AS LastPostActivity,
    AVG(p.Score) AS AveragePostScore
  FROM Posts AS p
  LEFT JOIN Comments AS c
    ON p.Id = c.PostId
  LEFT JOIN Votes AS v
    ON p.Id = v.PostId
  GROUP BY
    p.Id
), UserEngagement AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    COUNT(DISTINCT ph.Id) AS PostHistoryEntries,
    SUM(CASE WHEN ph.PostHistoryTypeId = 2 THEN 1 ELSE 0 END) AS BodyEdits,
    SUM(CASE WHEN ph.PostHistoryTypeId IN (1, 4, 7) THEN 1 ELSE 0 END) AS TitleEdits,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS QuestionCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS AnswerCount,
    CASE WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN 1 ELSE 0 END AS HasWebsite
  FROM Users AS u
  LEFT JOIN PostHistory AS ph
    ON u.Id = ph.UserId
  LEFT JOIN Badges AS b
    ON u.Id = b.UserId
  LEFT JOIN Posts AS p
    ON u.Id = p.OwnerUserId
  GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.WebsiteUrl
), LatestQuestions AS (
  SELECT
    PostId,
    PostTypeId,
    OwnerUserId,
    PostCreationDate,
    PostScore,
    FavoriteCount,
    PostTypeName,
    rn
  FROM RankedPosts
  WHERE
    rn <= 50
), UserPostPerformance AS (
  SELECT
    pa.PostId,
    pa.CommentCount,
    pa.UpVoteCount,
    pa.DownVoteCount,
    pa.LastPostActivity,
    pa.AveragePostScore,
    rp.PostTypeName,
    rp.PostScore AS OriginalPostScore,
    CASE
      WHEN pa.UpVoteCount > pa.DownVoteCount * 2 THEN 'Positive Feedback'
      WHEN pa.DownVoteCount > pa.UpVoteCount * 2 THEN 'Negative Feedback'
      ELSE 'Neutral Feedback'
    END AS FeedbackSentiment,
    CONCAT(rp.PostTypeName, ' - Score: ', rp.PostScore) AS PostDetails
  FROM PostAggregates AS pa
  JOIN RankedPosts AS rp
    ON pa.PostId = rp.PostId
  WHERE
    rp.PostTypeId = 1 /* Questions only */
)
SELECT
  lq.PostId,
  lq.PostTypeName,
  lq.PostCreationDate,
  lq.PostScore,
  lq.FavoriteCount,
  ue.DisplayName AS OwnerDisplayName,
  ue.Reputation AS OwnerReputation,
  ue.UserCreationDate AS OwnerCreationDate,
  ue.PostHistoryEntries,
  ue.BadgeCount,
  ue.QuestionCount,
  ue.AnswerCount,
  ue.HasWebsite,
  up.CommentCount,
  up.UpVoteCount,
  up.DownVoteCount,
  up.FeedbackSentiment,
  up.PostDetails,
  CASE
    WHEN up.AveragePostScore > 50 THEN 'High Performance'
    WHEN up.AveragePostScore BETWEEN 10 AND 50 THEN 'Medium Performance'
    ELSE 'Low Performance'
  END AS PerformanceTier
FROM LatestQuestions AS lq
LEFT JOIN UserEngagement AS ue
  ON lq.OwnerUserId = ue.UserId
LEFT JOIN UserPostPerformance AS up
  ON lq.PostId = up.PostId
WHERE
  lq.PostTypeName IS NOT NULL AND ue.DisplayName IS NOT NULL AND up.PostId IS NOT NULL
UNION
SELECT
  NULL,
  'Summary',
  MIN(lq.PostCreationDate),
  AVG(lq.PostScore),
  AVG(lq.FavoriteCount),
  'N/A',
  AVG(ue.Reputation),
  MIN(ue.UserCreationDate),
  AVG(ue.PostHistoryEntries),
  AVG(ue.BadgeCount),
  AVG(ue.QuestionCount),
  AVG(ue.AnswerCount),
  AVG(ue.HasWebsite),
  AVG(up.CommentCount),
  AVG(up.UpVoteCount),
  AVG(up.DownVoteCount),
  'Overall',
  'Performance Summary'
FROM LatestQuestions AS lq
LEFT JOIN UserEngagement AS ue
  ON lq.OwnerUserId = ue.UserId
LEFT JOIN UserPostPerformance AS up
  ON lq.PostId = up.PostId
WHERE
  lq.PostTypeName IS NOT NULL AND ue.DisplayName IS NOT NULL AND up.PostId IS NOT NULL;
