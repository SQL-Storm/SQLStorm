-- {"query": "55097.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1548} 
WITH TaggedQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1
),
Answers AS (
    SELECT 
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate
    FROM Posts a
    WHERE a.PostTypeId = 2
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesReceived,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesReceived
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
AnswerMetrics AS (
    SELECT 
        a.OwnerUserId,
        COUNT(*) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        MIN(a.Score) AS MinAnswerScore,
        COUNT(CASE WHEN a.Score >= 10 THEN 1 END) AS HighScoringAnswers
    FROM Answers a
    GROUP BY a.OwnerUserId
),
TagPerformance AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.UpVotesReceived,
        us.DownVotesReceived,
        am.AnswerCount,
        am.AvgAnswerScore,
        am.MaxAnswerScore,
        am.MinAnswerScore,
        am.HighScoringAnswers,
        COUNT(DISTINCT tq.Tag) AS DistinctTagsAnswered,
        SUM(CASE WHEN tq.Tag = ANY(ARRAY['python','java','c#','javascript']) THEN 1 ELSE 0 END) AS PopularTagAnswers
    FROM UserStats us
    LEFT JOIN AnswerMetrics am ON am.OwnerUserId = us.UserId
    LEFT JOIN Answers a ON a.OwnerUserId = us.UserId
    LEFT JOIN TaggedQuestions tq ON tq.QuestionId = a.QuestionId
    GROUP BY 
        us.UserId, us.DisplayName, us.Reputation,
        us.GoldBadges, us.SilverBadges, us.BronzeBadges,
        us.UpVotesReceived, us.DownVotesReceived,
        am.AnswerCount, am.AvgAnswerScore, am.MaxAnswerScore,
        am.MinAnswerScore, am.HighScoringAnswers
)
SELECT 
    tp.*,
    ROW_NUMBER() OVER (ORDER BY tp.Reputation DESC, tp.AvgAnswerScore DESC) AS RankByRepAndScore
FROM TagPerformance tp
WHERE tp.AnswerCount >= 50
ORDER BY tp.Reputation DESC, tp.AvgAnswerScore DESC
LIMIT 100;