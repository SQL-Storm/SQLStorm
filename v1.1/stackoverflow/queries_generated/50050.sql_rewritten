-- {"query": "50050.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1161} 
WITH PopularTags AS (
    SELECT TagName
    FROM Tags
    WHERE Count > 10000 AND IsModeratorOnly IS NOT TRUE
),
UserTagActivity AS (
    SELECT
        u.Id AS UserId,
        pt.TagName,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        SUM(CASE WHEN q.AcceptedAnswerId = p.Id THEN 1 ELSE 0 END) AS AcceptedAnswers,
        MAX(p.LastActivityDate) AS LastActivityInTag
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN PopularTags pt ON p.Tags LIKE CONCAT('%<', pt.TagName, '>%')
    LEFT JOIN Posts q ON p.ParentId = q.Id AND p.PostTypeId = 2
    WHERE
        p.PostTypeId IN (1, 2)
        AND p.CreationDate > (cast('2024-10-01 12:34:56' as timestamp) - interval '5 year')
        AND u.Reputation > 5000
    GROUP BY u.Id, pt.TagName
    HAVING SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) > 20
),
UserTagBadges AS (
    SELECT
        b.UserId,
        b.Name AS TagName,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldTagBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverTagBadges
    FROM Badges b
    WHERE b.TagBased = TRUE AND b.Name IN (SELECT TagName FROM PopularTags)
    GROUP BY b.UserId, b.Name
),
BestAnswerInTag AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        pt.TagName,
        p.Score,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId, pt.TagName ORDER BY p.Score DESC, p.CreationDate DESC) as rn
    FROM Posts p
    JOIN PopularTags pt ON p.Tags LIKE CONCAT('%<', pt.TagName, '>%')
    WHERE p.PostTypeId = 2 AND p.OwnerUserId IN (SELECT UserId FROM UserTagActivity)
),
UserRanking AS (
    SELECT
        uta.UserId,
        uta.TagName,
        uta.AnswerCount,
        uta.TotalAnswerScore,
        uta.AcceptedAnswers,
        COALESCE(utb.GoldTagBadges, 0) AS GoldTagBadges,
        COALESCE(utb.SilverTagBadges, 0) AS SilverTagBadges,
        (uta.TotalAnswerScore * 0.4) + (uta.AcceptedAnswers * 10) + (COALESCE(utb.GoldTagBadges, 0) * 100) + (COALESCE(utb.SilverTagBadges, 0) * 25) AS PowerScore,
        DENSE_RANK() OVER(PARTITION BY uta.TagName ORDER BY
            (uta.TotalAnswerScore * 0.4) + (uta.AcceptedAnswers * 10) + (COALESCE(utb.GoldTagBadges, 0) * 100) + (COALESCE(utb.SilverTagBadges, 0) * 25) DESC
        ) as Rank
    FROM UserTagActivity uta
    LEFT JOIN UserTagBadges utb ON uta.UserId = utb.UserId AND uta.TagName = utb.TagName
)
SELECT
    ur.TagName,
    ur.Rank,
    u.DisplayName,
    u.Reputation,
    ur.PowerScore,
    ur.AnswerCount,
    ur.TotalAnswerScore,
    ur.AcceptedAnswers,
    ur.GoldTagBadges,
    ur.SilverTagBadges,
    CAST(ur.AcceptedAnswers AS decimal(10, 4)) / ur.AnswerCount AS AcceptanceRate,
    bai.Score as BestAnswerScore,
    q_post.Title as BestAnswerQuestionTitle,
    CONCAT('https://stackoverflow.com/q/', CAST(q_post.Id AS varchar(20))) AS QuestionLink,
    CONCAT('https://stackoverflow.com/a/', CAST(bai.PostId AS varchar(20))) AS BestAnswerLink
FROM UserRanking ur
JOIN Users u ON ur.UserId = u.Id
LEFT JOIN BestAnswerInTag bai ON ur.UserId = bai.OwnerUserId AND ur.TagName = bai.TagName AND bai.rn = 1
LEFT JOIN Posts a_post ON bai.PostId = a_post.Id
LEFT JOIN Posts q_post ON a_post.ParentId = q_post.Id
WHERE ur.Rank <= 5
ORDER BY ur.TagName, ur.Rank;