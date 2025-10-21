-- {"query": "5025.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1130} 
WITH RecentUsers AS (
    SELECT u.Id AS UserId, u.DisplayName, u.Reputation, u.CreationDate
    FROM Users u
    WHERE u.CreationDate > CURRENT_DATE - INTERVAL '90 days'
),
BadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
TopQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.CreationDate,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
),
UserActivity AS (
    SELECT
        r.UserId,
        COUNT(DISTINCT q.Id) AS QuestionsAsked,
        COUNT(DISTINCT a.Id) AS AnswersGiven,
        AVG(q.Score) AS AvgQuestionScore,
        AVG(a.Score) AS AvgAnswerScore
    FROM RecentUsers r
    LEFT JOIN Posts q ON q.PostTypeId = 1 AND q.OwnerUserId = r.UserId
    LEFT JOIN Posts a ON a.PostTypeId = 2 AND a.OwnerUserId = r.UserId
    GROUP BY r.UserId
),
UserVotes AS (
    SELECT
        v.UserId,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotesCast,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotesCast,
        COUNT(*) AS TotalVotesCast
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
BestTag AS (
    SELECT
        p.OwnerUserId AS UserId,
        TRIM(BOTH '>' FROM SPLIT_PART(SPLIT_PART(p.Tags, '<', 2), '>', 1)) AS FirstTag,
        COUNT(*) AS TagCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC) AS rn
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, TRIM(BOTH '>' FROM SPLIT_PART(SPLIT_PART(p.Tags, '<', 2), '>', 1))
)
SELECT
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.CreationDate,
    COALESCE(bs.TotalBadges, 0) AS TotalBadges,
    COALESCE(bs.GoldBadges, 0) AS GoldBadges,
    COALESCE(bs.SilverBadges, 0) AS SilverBadges,
    COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ROUND(COALESCE(ua.AvgQuestionScore, 0),2) AS AvgQuestionScore,
    ROUND(COALESCE(ua.AvgAnswerScore, 0),2) AS AvgAnswerScore,
    uv.UpVotesCast,
    uv.DownVotesCast,
    uv.TotalVotesCast,
    tq.QuestionId AS TopQuestionId,
    tq.Title AS TopQuestionTitle,
    tq.Score AS TopQuestionScore,
    tq.CreationDate AS TopQuestionDate,
    COALESCE(btag.FirstTag, 'none') AS BestFirstTag,
    btag.TagCount AS BestFirstTagCount,
    CASE 
        WHEN tq.Score > 100 THEN 'Superstar'
        WHEN tq.Score BETWEEN 50 AND 100 THEN 'Rising Star'
        ELSE 'Active'
    END AS UserCategory,
    CASE WHEN COALESCE(bs.GoldBadges, 0) > COALESCE(bs.SilverBadges, 0) + COALESCE(bs.BronzeBadges, 0) THEN TRUE ELSE FALSE END AS GoldDominant
FROM RecentUsers ru
LEFT JOIN BadgeSummary bs ON bs.UserId = ru.UserId
LEFT JOIN UserActivity ua ON ua.UserId = ru.UserId
LEFT JOIN UserVotes uv ON uv.UserId = ru.UserId
LEFT JOIN (
    SELECT * FROM TopQuestions WHERE rn = 1
) tq ON tq.OwnerUserId = ru.UserId
LEFT JOIN (
    SELECT UserId, FirstTag, TagCount FROM BestTag WHERE rn = 1
) btag ON btag.UserId = ru.UserId
WHERE
    (ua.QuestionsAsked > 2 OR ua.AnswersGiven > 2)
    AND (ru.Reputation > 500 OR bs.TotalBadges > 5)
    AND (
        tq.Title ILIKE '%SQL%' OR
        btag.FirstTag = 'sql'
    )
ORDER BY
    ru.Reputation DESC NULLS LAST,
    bs.TotalBadges DESC NULLS LAST,
    ua.QuestionsAsked DESC NULLS LAST
LIMIT 50;