WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS NetVotes,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS AvgQuestionScore,
        (SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score)
         FROM Posts p
         WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS MedianAnswerScore
    FROM Users u
),

TagPopularity AS (
    SELECT
        t.TagName,
        t.Count AS TotalTagUse,
        COALESCE(SUM(p.ViewCount), 0) AS TotalTagViews,
        COUNT(DISTINCT p.OwnerUserId) AS DistinctAuthors
    FROM Tags t
    LEFT JOIN PostLinks pl
        ON pl.PostId = t.ExcerptPostId OR pl.PostId = t.WikiPostId
    LEFT JOIN Posts p
        ON p.Id = pl.PostId AND p.PostTypeId = 1
    GROUP BY t.TagName, t.Count
),

UserTagActivity AS (
    SELECT
        us.Id      AS UserId,
        t.TagName,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionsWithTag,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswersWithTag,
        SUM(p.Score) AS TagScoreSum
    FROM UserStats us
    JOIN Posts p
        ON p.OwnerUserId = us.Id
    JOIN LATERAL (VALUES (split_part(p.Tags, '><', 1))) AS pt(tag) ON TRUE
    JOIN Tags t
        ON t.TagName = pt.tag
    GROUP BY us.Id, t.TagName
),

RankedUsers AS (
    SELECT
        us.*,
        ROW_NUMBER() OVER (ORDER BY (us.Reputation * 1.5 + us.NetVotes) DESC) AS ReputationRank,
        RANK()      OVER (ORDER BY us.MedianAnswerScore DESC NULLS LAST) AS MedianAnswerRank
    FROM UserStats us
)

SELECT
    ru.Id,
    ru.DisplayName,
    ru.Reputation,
    ru.NetVotes,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ru.QuestionCount,
    ru.AnswerCount,
    CAST(ROUND(CAST(ru.AvgQuestionScore AS NUMERIC), 2) AS DOUBLE PRECISION) AS AvgQuestionScore,
    CAST(ROUND(CAST(ru.MedianAnswerScore AS NUMERIC), 2) AS DOUBLE PRECISION) AS MedianAnswerScore,
    ru.ReputationRank,
    ru.MedianAnswerRank,
    COALESCE(uta.QuestionsWithTag, 0) AS QuestionsWithTopTag,
    COALESCE(uta.AnswersWithTag,   0) AS AnswersWithTopTag,
    COALESCE(uta.TagScoreSum,      0) AS TagScoreSum,
    tp.TotalTagUse,
    tp.TotalTagViews,
    tp.DistinctAuthors
FROM RankedUsers ru
LEFT JOIN (
    SELECT
        uta.UserId,
        uta.TagName,
        uta.QuestionsWithTag,
        uta.AnswersWithTag,
        uta.TagScoreSum
    FROM UserTagActivity uta
    ORDER BY uta.TagScoreSum DESC
    LIMIT 1
) uta
    ON uta.UserId = ru.Id
LEFT JOIN TagPopularity tp
    ON tp.TagName = uta.TagName
WHERE ru.ReputationRank <= 10
ORDER BY ru.ReputationRank;