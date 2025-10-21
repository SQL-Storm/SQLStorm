-- {"query": "50060.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 982} 
WITH PopularTags AS (
    SELECT TagName
    FROM Tags
    WHERE Count > 15000 AND IsRequired = false AND IsModeratorOnly = false
),
UserActivityInTags AS (
    SELECT
        p.OwnerUserId,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        MIN(p.CreationDate) AS FirstPostDate,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(p.CommentCount) AS AvgPostCommentCount
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
      AND p.PostTypeId IN (1, 2)
      AND EXISTS (
          SELECT 1
          FROM PopularTags pt
          WHERE p.Tags LIKE '%' || '<' || pt.TagName || '>' || '%'
      )
    GROUP BY p.OwnerUserId
    HAVING COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 10
),
UserBadgesAndVotes AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS TotalFavoritesGiven
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Reputation > 5000
    GROUP BY u.Id
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Age,
    act.TotalQuestionScore,
    act.TotalAnswerScore,
    (act.TotalQuestionScore + act.TotalAnswerScore) AS TotalScoreInPopularTags,
    act.QuestionCount,
    act.AnswerCount,
    CASE
        WHEN act.QuestionCount > 0 THEN CAST(act.AnswerCount AS DECIMAL(10, 4)) / act.QuestionCount
        ELSE 0
    END AS AnswerToQuestionRatio,
    bv.TotalBadges,
    bv.GoldBadges,
    bv.SilverBadges,
    bv.BronzeBadges,
    bv.TotalUpVotesGiven,
    bv.TotalDownVotesGiven,
    (act.LastPostDate - act.FirstPostDate) AS ActivityDurationInTags,
    DENSE_RANK() OVER (PARTITION BY (u.Reputation / 10000) ORDER BY (act.TotalQuestionScore + act.TotalAnswerScore) DESC) AS RankWithinReputationBracket,
    (SELECT AVG(Score) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 2) AS UserAverageAnswerScore
FROM (
    SELECT Id, DisplayName, Reputation, (cast('2024-10-01' as date) - CAST(CreationDate AS DATE)) AS Age
    FROM Users
    WHERE LastAccessDate > (cast('2024-10-01' as date) - INTERVAL '1 year')
) u
JOIN UserActivityInTags act ON u.Id = act.OwnerUserId
JOIN UserBadgesAndVotes bv ON u.Id = bv.UserId
WHERE
    act.AnswerCount > act.QuestionCount
    AND act.AvgPostCommentCount > 2.5
    AND bv.GoldBadges > 0
ORDER BY
    u.Reputation DESC,
    TotalScoreInPopularTags DESC
LIMIT 250;