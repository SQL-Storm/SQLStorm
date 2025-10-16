-- {"query": "22023.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 650} 
WITH HighReputationUsers AS (
    SELECT Id, Reputation, DisplayName,
           COALESCE(WebsiteUrl, 'No Website') AS Website,
           CASE WHEN AboutMe IS NULL THEN 'No Bio' ELSE SUBSTRING(AboutMe, 1, 50) END AS BioSnippet
    FROM Users
    WHERE Reputation > 1000
),
QuestionStats AS (
    SELECT p.Id, p.Title, p.OwnerUserId, p.Tags,
           p.Score AS QuestionScore,
           p.ViewCount,
           COUNT(c.Id) AS CommentCount,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS VoteNetScore,
           p.AcceptedAnswerId,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS QuestionRank
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.Tags, p.Score, p.ViewCount, p.AcceptedAnswerId
),
AnswerStats AS (
    SELECT a.ParentId AS QuestionId, a.Score AS AnswerScore, a.OwnerUserId AS AnswerUserId,
           RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC) AS AnswerRank
    FROM Posts a
    WHERE a.PostTypeId = 2
),
BadgeCounts AS (
    SELECT b.UserId,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
           COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
           COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT hru.Id AS UserId, hru.DisplayName, hru.Reputation, hru.Website, hru.BioSnippet,
       qs.Title, qs.QuestionScore, qs.ViewCount, qs.CommentCount, qs.VoteNetScore,
       COALESCE(ans.AnswerScore, 0) AS TopAnswerScore,
       CASE WHEN qs.AcceptedAnswerId IS NOT NULL THEN 'Accepted' ELSE 'No Accepted' END AS HasAccepted,
       bc.GoldBadges, bc.SilverBadges, bc.BronzeBadges,
       SUBSTRING(REPLACE(qs.Tags, '<', ''), 1, 100) AS TagList
FROM HighReputationUsers hru
INNER JOIN QuestionStats qs ON hru.Id = qs.OwnerUserId AND qs.QuestionRank <= 5
LEFT JOIN AnswerStats ans ON qs.Id = ans.QuestionId AND ans.AnswerRank = 1
LEFT JOIN BadgeCounts bc ON hru.Id = bc.UserId
WHERE qs.VoteNetScore > 10 OR qs.CommentCount > 5
ORDER BY hru.Reputation DESC, qs.QuestionScore DESC;