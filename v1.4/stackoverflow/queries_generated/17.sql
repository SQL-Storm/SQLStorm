-- {"query": "17.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 410} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  COUNT(DISTINCT p.Id) AS QuestionCount,
  AVG(p.Score) AS AvgQuestionScore,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesOnQuestions,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesOnQuestions,
  AVG(NULLIF(p.ViewCount,0)) AS AvgViewCountPerQuestion,
  STRING_AGG(DISTINCT t.Name, ',') AS TaggedAreas,
  MAX(p.LastActivityDate) AS LastActivity,
  MAX(p.CreationDate) AS CreatedAt,
  MAX(b.Date) FILTER (WHERE b.Class = 1) AS GoldBadgesDate,
  SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
  SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
  SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
FROM
  Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN PostTags pt ON pt.PostId = p.Id
LEFT JOIN Tags t ON t.Id = pt.TagId
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN (
  SELECT DISTINCT p.Id AS PostId, unnest(string_to_array(p.Tags, '''><''')) AS TagName
  FROM Posts p
  WHERE p.PostTypeId = 1
) AS pt ON pt.PostId = p.Id
GROUP BY
  u.Id, u.DisplayName
ORDER BY
  GoldBadges DESC,
  SilverBadges DESC,
  BronzeBadges DESC,
  AVG(p.Score) DESC
LIMIT 100;