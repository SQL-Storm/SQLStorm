-- {"query": "53087.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 816} 

WITH QuestionTags AS (
    SELECT 
        p.Id AS QuestionId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= '2010-01-01'
        AND p.Score > 0
),
PopularTags AS (
    SELECT 
        Tag,
        COUNT(DISTINCT QuestionId) AS QuestionCount
    FROM QuestionTags
    GROUP BY Tag
    HAVING COUNT(DISTINCT QuestionId) > 1000
),
UserAnswers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerDate,
        qt.Tag
    FROM Users u
    JOIN Posts a ON u.Id = a.OwnerUserId
    JOIN QuestionTags qt ON a.ParentId = qt.QuestionId
    JOIN PopularTags pt ON qt.Tag = pt.Tag
    WHERE a.PostTypeId = 2
        AND u.Reputation > 1000
        AND a.Score > 0
),
AggregatedAnswers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        COUNT(DISTINCT AnswerId) AS TotalAnswers,
        SUM(AnswerScore) AS TotalScore,
        AVG(AnswerScore) AS AvgScore,
        COUNT(DISTINCT Tag) AS UniqueTagsAnswered,
        MAX(AnswerDate) AS LatestAnswerDate
    FROM UserAnswers
    GROUP BY UserId, DisplayName, Reputation
),
UserBadges AS (
    SELECT 
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
UserVotes AS (
    SELECT 
        v.UserId,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotesGiven
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.CreationDate >= '2010-01-01'
    GROUP BY v.UserId
),
RankedUsers AS (
    SELECT 
        aa.UserId,
        aa.DisplayName,
        aa.Reputation,
        aa.TotalAnswers,
        aa.TotalScore,
        aa.AvgScore,
        aa.UniqueTagsAnswered,
        aa.LatestAnswerDate,
        COALESCE(ub.GoldBadges, 0) AS GoldBadges,
        COALESCE(ub.SilverBadges, 0) AS SilverBadges,
        COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(uv.UpVotesGiven, 0) AS UpVotesGiven,
        COALESCE(uv.DownVotesGiven, 0) AS DownVotesGiven,
        RANK() OVER (ORDER BY aa.TotalScore DESC) AS ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY aa.UniqueTagsAnswered ORDER BY aa.TotalAnswers DESC) AS VersatilityRank
    FROM AggregatedAnswers aa
    LEFT JOIN UserBadges ub ON aa.UserId = ub.UserId
    LEFT JOIN UserVotes uv ON aa.UserId = uv.UserId
    WHERE aa.TotalAnswers > 10
        AND aa.UniqueTagsAnswered > 5
)
SELECT *
FROM RankedUsers
WHERE ScoreRank <= 100
ORDER BY ScoreRank, VersatilityRank;
