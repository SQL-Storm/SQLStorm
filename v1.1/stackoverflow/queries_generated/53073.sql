-- {"query": "53073.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 812} 

WITH UnnestedTags AS (
  SELECT 
    p.Id AS QuestionId, 
    p.Score AS QuestionScore, 
    p.ViewCount, 
    unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS Tag
  FROM Posts p
  WHERE p.PostTypeId = 1
),
PopularTags AS (
  SELECT TagName, Count
  FROM Tags
  WHERE Count > 10000
),
TopQuestionsPerTag AS (
  SELECT 
    ut.Tag, 
    ut.QuestionId, 
    ut.QuestionScore, 
    ut.ViewCount,
    ROW_NUMBER() OVER (PARTITION BY ut.Tag ORDER BY ut.QuestionScore DESC, ut.ViewCount DESC) AS QuestionRank
  FROM UnnestedTags ut
  JOIN PopularTags pt ON pt.TagName = ut.Tag
),
AcceptedAnswers AS (
  SELECT 
    tq.Tag, 
    tq.QuestionId, 
    p.AcceptedAnswerId, 
    aa.Score AS AnswerScore, 
    aa.OwnerUserId,
    COUNT(c.Id) AS CommentCount,
    SUM(v.BountyAmount) AS TotalBounty
  FROM TopQuestionsPerTag tq
  JOIN Posts p ON p.Id = tq.QuestionId
  LEFT JOIN Posts aa ON aa.Id = p.AcceptedAnswerId AND aa.PostTypeId = 2
  LEFT JOIN Comments c ON c.PostId = aa.Id
  LEFT JOIN Votes v ON v.PostId = aa.Id AND v.VoteTypeId IN (8, 9)
  WHERE tq.QuestionRank = 1
  GROUP BY tq.Tag, tq.QuestionId, p.AcceptedAnswerId, aa.Score, aa.OwnerUserId
),
UserDetails AS (
  SELECT 
    aa.Tag, 
    aa.QuestionId, 
    aa.AcceptedAnswerId, 
    aa.AnswerScore, 
    aa.CommentCount, 
    aa.TotalBounty,
    u.DisplayName, 
    u.Reputation,
    COUNT(b.Id) AS GoldBadges,
    MAX(ph.CreationDate) AS LastEditDate
  FROM AcceptedAnswers aa
  JOIN Users u ON u.Id = aa.OwnerUserId
  LEFT JOIN Badges b ON b.UserId = u.Id AND b.Class = 1
  LEFT JOIN PostHistory ph ON ph.PostId = aa.AcceptedAnswerId AND ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
  GROUP BY aa.Tag, aa.QuestionId, aa.AcceptedAnswerId, aa.AnswerScore, aa.CommentCount, aa.TotalBounty, u.DisplayName, u.Reputation
),
VoteAnalysis AS (
  SELECT 
    ud.Tag, 
    ud.AcceptedAnswerId,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS Upvotes,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS Downvotes,
    AVG(v.CreationDate) AS AvgVoteDate
  FROM UserDetails ud
  JOIN Votes v ON v.PostId = ud.AcceptedAnswerId
  GROUP BY ud.Tag, ud.AcceptedAnswerId
)
SELECT 
  ud.Tag, 
  ud.DisplayName, 
  ud.Reputation, 
  ud.GoldBadges, 
  ud.AnswerScore, 
  ud.CommentCount, 
  ud.TotalBounty, 
  va.Upvotes, 
  va.Downvotes, 
  ud.LastEditDate, 
  va.AvgVoteDate,
  RANK() OVER (PARTITION BY ud.Tag ORDER BY ud.AnswerScore DESC) AS RankWithinTag
FROM UserDetails ud
JOIN VoteAnalysis va ON va.AcceptedAnswerId = ud.AcceptedAnswerId AND va.Tag = ud.Tag
ORDER BY ud.Reputation DESC, va.Upvotes DESC
LIMIT 100;
