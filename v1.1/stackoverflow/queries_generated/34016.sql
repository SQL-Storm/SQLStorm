-- {"query": "34016.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 1251} 

WITH RecursiveTagHierarchy AS (
  SELECT
    t.Id,
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    1 as Level
  FROM Tags t
  WHERE t.Count > 1000

  UNION ALL

  SELECT
    t2.Id,
    t2.TagName,
    t2.Count,
    t2.ExcerptPostId,
    rh.Level + 1
  FROM Tags t2
  JOIN Posts p ON p.Id = t2.ExcerptPostId
  JOIN PostLinks pl ON pl.PostId = p.Id
  JOIN RecursiveTagHierarchy rh ON rh.Id = pl.RelatedPostId
  WHERE rh.Level < 3
),
UserPostStats AS (
  SELECT
    u.Id as UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
    AVG(p.Score) AS AvgPostScore,
    SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
    MAX(p.CreationDate) AS LastPostDate
  FROM
    Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate > NOW() - INTERVAL '1 YEAR'
  WHERE 
    u.Reputation > 5000
  GROUP BY u.Id, u.DisplayName
),
UserBadgeRanks AS (
  SELECT
    b.UserId,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    COUNT(*) AS TotalBadges
  FROM Badges b
  GROUP BY b.UserId
),
TopTagsQuestions AS (
  SELECT
    p.Id as QuestionId,
    p.Title,
    p.CreationDate,
    unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) as TagName
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.CreationDate > NOW() - INTERVAL '6 MONTHS'
),
MostActiveUsersInTags AS (
  SELECT
    ut.TagName,
    u.Id AS UserId,
    u.DisplayName,
    COUNT(p.Id) AS PostsInTag
  FROM UserPostStats us
  JOIN Users u ON u.Id = us.UserId
  JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.CreationDate > NOW() - INTERVAL '1 YEAR'
  CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS ut(TagName)
  GROUP BY ut.TagName, u.Id, u.DisplayName
  ORDER BY ut.TagName, PostsInTag DESC
),
TopUserPostVotes AS (
  SELECT
    p.OwnerUserId,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesReceived,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesReceived,
    COUNT(v.Id) AS TotalVotesReceived
  FROM Posts p
  JOIN Votes v ON v.PostId = p.Id
  GROUP BY p.OwnerUserId
),
TagAnswerStats AS (
  SELECT
    t.TagName,
    COUNT(a.Id) AS TotalAnswers,
    AVG(a.Score) AS AvgAnswerScore,
    MAX(a.Score) AS MaxAnswerScore
  FROM Posts q
  JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  CROSS JOIN LATERAL unnest(string_to_array(substring(q.Tags, 2, length(q.Tags) - 2), '><')) AS t(TagName)
  WHERE q.PostTypeId = 1 AND q.CreationDate > NOW() - INTERVAL '1 YEAR'
  GROUP BY t.TagName
)
SELECT
  ut.TagName,
  ts.Count AS TagTotalCount,
  ua.DisplayName AS TopUserDisplayName,
  ua.PostsInTag AS UserPostCountInTag,
  bs.GoldBadges,
  bs.SilverBadges,
  bs.BronzeBadges,
  us.QuestionCount,
  us.AnswerCount,
  us.AvgPostScore,
  COALESCE(tas.TotalAnswers,0) AS TotalAnswersInTagLastYear,
  COALESCE(tas.AvgAnswerScore,0) AS AvgAnswerScoreInTagLastYear,
  COALESCE(tas.MaxAnswerScore,0) AS MaxAnswerScoreInTagLastYear,
  COALESCE(vu.UpVotesReceived,0) AS UserUpVotesReceived,
  COALESCE(vu.DownVotesReceived,0) AS UserDownVotesReceived,
  COALESCE(vu.TotalVotesReceived,0) AS UserTotalVotesReceived
FROM (
  SELECT DISTINCT TagName FROM RecursiveTagHierarchy WHERE Level = 1
) ts
LEFT JOIN Tags t ON t.TagName = ts.TagName
LEFT JOIN (
  SELECT DISTINCT ON (TagName) TagName, UserId, DisplayName, PostsInTag FROM MostActiveUsersInTags ORDER BY TagName, PostsInTag DESC
) ua ON ua.TagName = ts.TagName
LEFT JOIN UserPostStats us ON us.UserId = ua.UserId
LEFT JOIN UserBadgeRanks bs ON bs.UserId = ua.UserId
LEFT JOIN TagAnswerStats tas ON tas.TagName = ts.TagName
LEFT JOIN TopUserPostVotes vu ON vu.OwnerUserId = ua.UserId
ORDER BY ts.TagName
LIMIT 50;
