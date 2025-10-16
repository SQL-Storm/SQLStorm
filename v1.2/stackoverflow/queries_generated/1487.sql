-- {"query": "1487.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1689} 

WITH UserStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
        SUM(p.Score) FILTER (WHERE p.PostTypeId IN (1, 2)) AS TotalPostScore,
        COALESCE(AVG(answer_scores.avg_answer_score), 0) AS AvgAnswerScore,
        MAX(p.Score) FILTER (WHERE p.PostTypeId = 2) AS MaxAnswerScore,
        SUM(b.Class = 1)::int AS GoldBadges,
        SUM(b.Class = 2)::int AS SilverBadges,
        SUM(b.Class = 3)::int AS BronzeBadges,
        -- Calculate days elapsed since account creation ignoring NULLs by ab, Unix epoch fallback
        GREATEST(EXTRACT(epoch FROM now() - u.CreationDate)/86400, 1) AS DaysActive,
        -- UpVotes minus DownVotes, coercing NULL to 0
        (COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0)) AS VoteNet,
        -- Expression involving reputation sqrt and votes adjusted log(1 + Cast score)
        LOG(1 + GREATEST(SQRT(u.Reputation), 0) * (1 + COALESCE(SUM(p.Score), 0))) AS ReputationScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN LATERAL (
        SELECT AVG(answer.Score) AS avg_answer_score
        FROM Posts answer
        WHERE answer.PostTypeId = 2 AND answer.OwnerUserId = u.Id
    ) AS answer_scores ON TRUE
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.CreationDate, u.UpVotes, u.DownVotes, u.Reputation
), TopUsersByActivity AS (
    SELECT
        UserId,
        DisplayName,
        QuestionsPosted,
        AnswersPosted,
        TotalPostScore,
        AvgAnswerScore,
        MaxAnswerScore,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        DaysActive,
        VoteNet,
        ReputationScore,
        -- Rolling average over last 3 users in alpha display name order (could be analyzed by rows frame)
        AVG(AnswersPosted) OVER (ORDER BY DisplayName ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) FILTER (WHERE AnswersPosted IS NOT NULL) AS Rolling3UserAvgAnswers
    FROM UserStats
), UserAskAnsSummary AS (
    SELECT
        p.PostTypeId,
        p.OwnerUserId,
        SUM(1) AS PostCount,
        AVG(COALESCE(p.Score,0)) AS AvgScore,
        AVG(COALESCE(p.ViewCount,0)) AS AvgViews,
        STRING_AGG(DISTINCT COALESCE(NULLIF(TRIM(T.tag), ''), '')) FILTER(WHERE T.tag IS NOT NULL OR PostTypeId=1) AS TagListConcat
    FROM Posts p
    LEFT JOIN LATERAL (
        SELECT
            unnest(string_to_array(substring(COALESCE(p.Tags, ''), 2, char_length(p.Tags)-2), '><')) AS tag
    ) T ON TRUE
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY p.PostTypeId, p.OwnerUserId
), UserTagScoreDiffs AS (
    SELECT 
        ua.OwnerUserId,
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostCountForTag,
        AVG(p.Score) AS AvgScoreForTag,
        -- Compute Lag comparing this tags avg score with previous tag per user to illustrate Window function + NULL logic opposed top-order tag name
        AVG(p.Score) - LAG(AVG(p.Score)) OVER (PARTITION BY ua.OwnerUserId ORDER BY t.TagName) AS ScoreDiffFromPrevTag
    FROM Posts p
    JOIN Users ua ON ua.Id = p.OwnerUserId
    JOIN LATERAL unnest(string_to_array(substring(COALESCE(p.Tags, ''), 2, char_length(p.Tags)-2), '><')) AS t[tag] ON TRUE
    JOIN Tags t
        ON LOWER(t.TagName) = LOWER(t.tag)
    WHERE p.PostTypeId = 1 -- Consider only questions
    GROUP BY ua.OwnerUserId, t.TagName
), CombinedActivityRank AS (
    SELECT
        us.UserId,
        us.DisplayName,
        us.QuestionsPosted,
        us.AnswersPosted,
        MAX(us.ReputationScore) AS MaxReputationScore,
        COALESCE(uts.PostCount, 0) AS TotalQuestionPosts,
        tops.Rolling3UserAvgAnswers,
        ROW_NUMBER() OVER (ORDER BY us.ReputationScore DESC, us.VoteNet DESC) AS UserRanking
    FROM UserStats us
    LEFT JOIN (
        SELECT OwnerUserId, SUM(PostCount) AS PostCount
        FROM UserAskAnsSummary
        WHERE PostTypeId = 1
        GROUP BY OwnerUserId
    ) uts ON uts.OwnerUserId = us.UserId
    LEFT JOIN TopUsersByActivity tops ON tops.UserId = us.UserId
    WHERE us.VoteNet > 0
)
SELECT
    car.UserId,
    car.DisplayName,
    car.UserRanking,
    car.QuestionsPosted,
    car.AnswersPosted,
    car.TotalQuestionPosts,
    car.MaxReputationScore,
    car.Rolling3UserAvgAnswers,
    tagavg.TagName,
    tagavg.PostCountForTag,
    COALESCE(tagavg.AvgScoreForTag, 0) AS AverageScoreForTag,
    COALESCE(tagavg.ScoreDiffFromPrevTag, 0) AS ScoreDifferenceFromPreviousTag
FROM CombinedActivityRank car
-- Correlated subquery to find most active tag in the past month per user respecting NULL threshold date filters
LEFT JOIN LATERAL (
    SELECT utst.TagName, utst.PostCountForTag, utst.AvgScoreForTag, utst.ScoreDiffFromPrevTag
    FROM UserTagScoreDiffs utst
    WHERE utst.OwnerUserId = car.UserId
    ORDER BY utst.PostCountForTag DESC NULLS LAST, utst.AvgScoreForTag DESC NULLS LAST, utst.TagName ASC NULLS LAST
    LIMIT 1
) tagavg ON TRUE
-- Critical complicated expression predicate (see combined OR, NULL aware checks)
WHERE (
    car.QuestionsPosted > 10 
    OR car.AnswersPosted > 20 
    OR car.TotalQuestionPosts > 15
    OR car.Rolling3UserAvgAnswers > COALESCE(NULLIF(car.AnswersPosted,0), 1) * 0.5
)
UNION
-- Complement set: fetch user posts flagged with votes and complicated breakout subscribers below threshold and distinct search EXCEPT to broaden results by badge golden users not in the active set sequence yet
SELECT
    b.UserId,
    u.DisplayName,
    99999 AS UserRanking,
    0 AS QuestionsPosted,
    0 AS AnswersPosted,
    0 AS TotalQuestionPosts,
    0 AS MaxReputationScore,
    0 AS Rolling3UserAvgAnswers,
    NULL AS TagName,
    0 AS PostCountForTag,
    0 AS AverageScoreForTag,
    0 AS ScoreDifferenceFromPreviousTag
FROM Badges b
LEFT JOIN Users u ON u.Id = b.UserId
WHERE b.Class = 1
-- Exclude users already covered by combined rank set by NOT EXISTS correlated subquery
AND NOT EXISTS (
    SELECT 1 
    FROM CombinedActivityRank car 
    WHERE car.UserId = b.UserId
)
ORDER BY
    UserRanking,
    PostCountForTag DESC NULLS LAST,
    AverageScoreForTag DESC NULLS LAST;
