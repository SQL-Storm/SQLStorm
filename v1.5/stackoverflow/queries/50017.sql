-- {"query": "50017.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 803} 
WITH TagStats AS (
    -- Find popular tags and their associated questions
    SELECT
        t.Id AS TagId,
        t.TagName,
        p.Id AS QuestionId
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    WHERE t.Count > 10000 AND p.PostTypeId = 1 AND p.AnswerCount > 5
),
UserContributions AS (
    -- Correlate users with their answers to the popular questions, including votes on those answers
    SELECT
        a.OwnerUserId,
        ts.TagName,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerDate,
        v.VoteTypeId
    FROM TagStats ts
    JOIN Posts a ON ts.QuestionId = a.ParentId
    LEFT JOIN Votes v ON a.Id = v.PostId
    WHERE a.PostTypeId = 2 AND a.OwnerUserId IS NOT NULL
),
AggregatedUserStats AS (
    -- Aggregate user stats per tag, calculating various metrics
    SELECT
        uc.OwnerUserId,
        uc.TagName,
        COUNT(DISTINCT uc.AnswerId) AS NumAnswers,
        AVG(uc.AnswerScore) AS AvgAnswerScore,
        SUM(CASE WHEN uc.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN uc.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        MAX(uc.AnswerDate) AS LastAnswerDate
    FROM UserContributions uc
    GROUP BY uc.OwnerUserId, uc.TagName
),
UserRanking AS (
    -- Rank users within each tag based on a composite score
    SELECT
        aus.OwnerUserId,
        u.DisplayName,
        u.Reputation,
        aus.TagName,
        aus.NumAnswers,
        aus.AvgAnswerScore,
        (aus.AvgAnswerScore * LOG(aus.NumAnswers + 1) + (aus.UpVotesReceived - aus.DownVotesReceived) / 10.0) AS WeightedScore,
        RANK() OVER(PARTITION BY aus.TagName ORDER BY (aus.AvgAnswerScore * LOG(aus.NumAnswers + 1) + (aus.UpVotesReceived - aus.DownVotesReceived) / 10.0) DESC) as RankInTag
    FROM AggregatedUserStats aus
    JOIN Users u ON aus.OwnerUserId = u.Id
    WHERE aus.NumAnswers > 5 AND u.Reputation > 5000
)
-- Final selection: Retrieve the top 3 experts for each popular tag,
-- along with their badge counts and a summary of their activity.
SELECT
    ur.TagName,
    ur.RankInTag,
    ur.DisplayName,
    ur.Reputation,
    ur.NumAnswers AS AnswersInTag,
    ur.AvgAnswerScore AS AvgScoreInTag,
    ur.WeightedScore,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ur.OwnerUserId AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ur.OwnerUserId AND b.Class = 2) AS SilverBadges,
    (SELECT MAX(c.CreationDate) FROM Comments c WHERE c.UserId = ur.OwnerUserId) AS LastCommentDate
FROM UserRanking ur
WHERE ur.RankInTag <= 3
ORDER BY ur.TagName, ur.RankInTag;