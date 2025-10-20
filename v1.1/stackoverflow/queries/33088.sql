-- {"query": "33088.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 339} 
SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesGiven,
    COUNT(DISTINCT p.Id) AS TotalQuestionsPosted,
    AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
    AVG(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionViews,
    COUNT(DISTINCT a.Id) AS TotalAnswersGiven,
    AVG(a.Score) AS AvgAnswerScore,
    COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
    COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
    COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
FROM Users u
LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
LEFT JOIN Badges b ON u.Id = b.UserId
WHERE u.Reputation > 1000
GROUP BY u.Id, u.DisplayName
HAVING COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) > 50
ORDER BY TotalQuestionsPosted DESC, AvgQuestionScore DESC
LIMIT 100;