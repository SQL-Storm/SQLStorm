WITH user_posts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END)               AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END)               AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END)   AS QuestionScoreSum,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END)   AS AnswerScoreSum,
        SUM(p.Score)                                               AS TotalScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
user_votes AS (
    SELECT 
        u.Id AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
        COUNT(v.Id)                                        AS TotalVotesGiven
    FROM Users u
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id
),
user_badges AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(b.Id)                                   AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
user_tags AS (
    SELECT 
        p.OwnerUserId AS UserId,
        UNNEST(string_to_array(TRIM(BOTH '><' FROM p.Tags), '><')) AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1 
      AND p.Tags IS NOT NULL
),
user_top_tag AS (
    SELECT 
        ut.UserId,
        ut.Tag,
        COUNT(*)                                           AS TagUseCount,
        ROW_NUMBER() OVER (PARTITION BY ut.UserId ORDER BY COUNT(*) DESC) AS rn
    FROM user_tags ut
    GROUP BY ut.UserId, ut.Tag
)
SELECT 
    up.UserId,
    up.DisplayName,
    up.Reputation,
    up.QuestionCount,
    up.AnswerCount,
    up.TotalScore,
    ROUND(CASE WHEN up.QuestionCount = 0 THEN NULL 
               ELSE up.QuestionScoreSum / up.QuestionCount END, 2) AS AvgQuestionScore,
    ROUND(CASE WHEN up.AnswerCount = 0 THEN NULL 
               ELSE up.AnswerScoreSum / up.AnswerCount END, 2)   AS AvgAnswerScore,
    uv.UpVotesGiven,
    uv.DownVotesGiven,
    uv.TotalVotesGiven,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.TotalBadges,
    utt.Tag          AS TopTag,
    utt.TagUseCount AS TopTagUseCount
FROM user_posts up
LEFT JOIN user_votes   uv ON uv.UserId = up.UserId
LEFT JOIN user_badges  ub ON ub.UserId = up.UserId
LEFT JOIN (
    SELECT UserId, Tag, TagUseCount
    FROM user_top_tag
    WHERE rn = 1
) utt ON utt.UserId = up.UserId
WHERE up.Reputation > 1000
ORDER BY up.Reputation DESC, up.TotalScore DESC
LIMIT 20;