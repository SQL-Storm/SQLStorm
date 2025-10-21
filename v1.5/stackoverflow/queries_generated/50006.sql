-- {"query": "50006.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 920} 

WITH HotTags AS (
    SELECT TagName
    FROM Tags
    WHERE Count > 5000 AND IsModeratorOnly = false
), QuestionTags AS (
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId AS QuestionOwnerId,
        p.ViewCount,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
      AND p.AnswerCount > 2
      AND p.ClosedDate IS NULL
), TaggedAnswers AS (
    SELECT
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswererId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        qt.QuestionId,
        qt.TagName,
        qt.ViewCount AS QuestionViewCount
    FROM Posts a
    INNER JOIN QuestionTags qt ON a.ParentId = qt.QuestionId
    INNER JOIN HotTags ht ON qt.TagName = ht.TagName
    WHERE a.PostTypeId = 2
      AND a.OwnerUserId IS NOT NULL
), UserTagPerformance AS (
    SELECT
        AnswererId,
        TagName,
        SUM(AnswerScore) AS TotalTagScore,
        COUNT(AnswerId) AS TotalTagAnswers,
        SUM(QuestionViewCount) AS TotalQuestionViews,
        AVG(AnswerScore) AS AvgTagScore,
        MIN(AnswerCreationDate) as FirstAnswerDate,
        MAX(AnswerCreationDate) as LastAnswerDate
    FROM TaggedAnswers
    GROUP BY AnswererId, TagName
), UserBadgeCounts AS (
    SELECT
        UserId,
        COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
), RankedUserPerformance AS (
    SELECT
        utp.*,
        u.DisplayName,
        u.Reputation,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        RANK() OVER (PARTITION BY utp.TagName ORDER BY utp.TotalTagScore DESC, utp.TotalTagAnswers DESC) AS TagRank,
        NTILE(100) OVER (ORDER BY u.Reputation DESC) AS ReputationPercentile
    FROM UserTagPerformance utp
    INNER JOIN Users u ON utp.AnswererId = u.Id
    LEFT JOIN UserBadgeCounts ubc ON utp.AnswererId = ubc.UserId
    WHERE u.UpVotes > u.DownVotes * 2 AND u.Reputation > 1000
)
SELECT
    rup.DisplayName,
    rup.Reputation,
    rup.TagName,
    rup.TotalTagScore,
    rup.TotalTagAnswers,
    rup.TagRank,
    rup.TotalQuestionViews / NULLIF(rup.TotalTagAnswers, 0) AS AvgViewsPerAnswer,
    rup.GoldBadges,
    rup.SilverBadges,
    rup.BronzeBadges,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = rup.AnswererId AND c.Score > 5) AS HighScoreComments,
    (SELECT p.Title FROM Posts p WHERE p.Id = (
        SELECT ta.QuestionId
        FROM TaggedAnswers ta
        WHERE ta.AnswererId = rup.AnswererId AND ta.TagName = rup.TagName
        ORDER BY ta.AnswerScore DESC, ta.AnswerCreationDate DESC
        LIMIT 1
    )) AS TopAnswerQuestionTitle
FROM RankedUserPerformance rup
WHERE rup.TagRank <= 10
  AND rup.ReputationPercentile <= 5
ORDER BY
    rup.TagName ASC,
    rup.TagRank ASC,
    rup.Reputation DESC
LIMIT 500;
