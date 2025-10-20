-- {"query": "50043.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1021} 

WITH TagStats AS (
    SELECT
        t.TagName,
        t.Count AS TagCount,
        AVG(q.Score) AS AvgQuestionScore,
        AVG(q.AnswerCount) AS AvgAnswerCount,
        AVG(q.ViewCount) AS AvgViewCount,
        t.Id AS TagId
    FROM Tags t
    JOIN Posts q ON t.WikiPostId = q.Id OR t.ExcerptPostId = q.Id
    WHERE q.PostTypeId = 1 AND t.Count > 1000
    GROUP BY t.Id, t.TagName, t.Count
    ORDER BY t.Count DESC
    LIMIT 50
),
UserContributions AS (
    SELECT
        p.OwnerUserId,
        SUBSTRING(p.Tags FROM '<([^>]+)>') AS PrimaryTag,
        COUNT(p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        SUM(p.FavoriteCount) AS TotalFavorites,
        SUM(CASE WHEN p.PostTypeId = 2 AND p.Id IN (SELECT AcceptedAnswerId FROM Posts WHERE AcceptedAnswerId IS NOT NULL) THEN 1 ELSE 0 END) AS AcceptedAnswers
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.CreationDate > (NOW() - INTERVAL '5 year')
    GROUP BY p.OwnerUserId, PrimaryTag
),
UserRanking AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        b.GoldBadges,
        b.SilverBadges,
        b.BronzeBadges,
        uc.PrimaryTag,
        uc.PostCount,
        uc.QuestionCount,
        uc.AnswerCount,
        uc.TotalScore,
        uc.TotalFavorites,
        uc.AcceptedAnswers,
        RANK() OVER(PARTITION BY uc.PrimaryTag ORDER BY uc.TotalScore DESC, u.Reputation DESC) AS RankInTag
    FROM Users u
    JOIN UserContributions uc ON u.Id = uc.OwnerUserId
    JOIN (
        SELECT
            UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
        FROM Badges
        GROUP BY UserId
    ) b ON u.Id = b.UserId
    WHERE u.Reputation > 10000 AND b.GoldBadges > 0
)
SELECT
    ts.TagName,
    ts.TagCount,
    ts.AvgQuestionScore,
    ts.AvgViewCount,
    ur.DisplayName AS TopUser,
    ur.Reputation AS TopUserReputation,
    ur.PostCount AS TopUserPostCountInTag,
    ur.TotalScore AS TopUserScoreInTag,
    (ur.AcceptedAnswers * 100.0 / NULLIF(ur.AnswerCount, 0)) AS TopUserAcceptedAnswerRate,
    (
        SELECT COUNT(*)
        FROM Comments c
        JOIN Posts p_comment ON c.PostId = p_comment.Id
        WHERE c.UserId = ur.UserId AND SUBSTRING(p_comment.Tags FROM '<([^>]+)>') = ts.TagName
    ) AS CommentsInTagByTopUser,
    (
        SELECT STRING_AGG(ph_edit.UserDisplayName, ', ')
        FROM PostHistory ph_edit
        JOIN Posts p_edit ON ph_edit.PostId = p_edit.Id
        WHERE ph_edit.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, Tags
          AND p_edit.OwnerUserId = ur.UserId
          AND ph_edit.UserId != ur.UserId
          AND SUBSTRING(p_edit.Tags FROM '<([^>]+)>') = ts.TagName
        LIMIT 5
    ) AS RecentEditorsOfTopUserPosts
FROM TagStats ts
JOIN UserRanking ur ON ts.TagName = ur.PrimaryTag
WHERE ur.RankInTag <= 5
ORDER BY ts.TagCount DESC, ur.RankInTag ASC;
