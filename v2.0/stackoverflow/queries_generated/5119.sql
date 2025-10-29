-- {"query": "5119.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1026} 
WITH
RecentQuestionStats AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_owner,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) OVER (PARTITION BY p.Id) AS UpVotesOnPost,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) OVER (PARTITION BY p.Id) AS DownVotesOnPost
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1 -- Questions
),
TopAuthors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.Location,
    u.WebsiteUrl,
    u.AboutMe,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.AccountId,
    SUM(CASE WHEN r.n > 0 THEN 1 ELSE 0 END) AS RecentActivePosts
  FROM Users u
  LEFT JOIN RecentQuestionStats r ON r.OwnerUserId = u.Id
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location,
    u.WebsiteUrl, u.AboutMe, u.Views, u.UpVotes, u.DownVotes, u.ProfileImageUrl, u.AccountId
),
TagActivity AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagQuestionCount,
    AVG(p.ViewCount) AS AvgViewsPerQuestion,
    SUM(p.Score) AS TotalScore
  FROM Posts p
  JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  ) t ON true
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
Combined AS (
  SELECT
    ta.UserId,
    ta.DisplayName,
    ta.Reputation,
    ta.UserCreationDate,
    ta.Location,
    ta.WebsiteUrl,
    ta.AboutMe,
    ta.Views,
    ta.UpVotes,
    ta.DownVotes,
    ta.ProfileImageUrl,
    ta.AccountId,
    ta.RecentActivePosts,
    THV.TotalUpVotes AS TotalPostUpVotes,
    THV.TotalDownVotes AS TotalPostDownVotes,
    MAX(pa.AvgViewsPerQuestion) OVER () AS GlobalAvgViewsPerQuestion,
    MAX(tt.TagQuestionCount) OVER () AS MaxQuestionsForTag
  FROM TopAuthors ta
  LEFT JOIN (
    SELECT
      p.OwnerUserId,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
  ) AS THV ON THV.OwnerUserId = ta.Id
  LEFT JOIN (
    SELECT AVG(p.ViewCount) AS AvgViewsPerQuestion, p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
  ) pa ON pa.OwnerUserId = ta.Id
  LEFT JOIN (
    SELECT t.TagName, COUNT(*) AS TagQuestionCount
    FROM Posts p
    JOIN LATERAL (
      SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    ) t ON true
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
  ) tt ON TRUE
)
SELECT
  c.UserId,
  c.DisplayName,
  c.Reputation,
  c.UserCreationDate,
  c.Location,
  c.WebsiteUrl,
  c.AboutMe,
  c.Views,
  c.UpVotes,
  c.DownVotes,
  c.ProfileImageUrl,
  c.AccountId,
  c.RecentActivePosts,
  COALESCE(c.TotalPostUpVotes, 0) AS TotalPostUpVotes,
  COALESCE(c.TotalPostDownVotes, 0) AS TotalPostDownVotes,
  COALESCE(c.GlobalAvgViewsPerQuestion, 0) AS GlobalAvgViewsPerQuestion,
  COALESCE(c.MaxQuestionsForTag, 0) AS MaxQuestionsForTag
FROM Combined c
ORDER BY c.Reputation DESC NULLS LAST, c.RecentActivePosts DESC
LIMIT 100;