-- {"query": "25051.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2725} 

WITH
    u AS (
        SELECT
            u.Id,
            COALESCE(u.DisplayName, 'Anonymous') AS DisplayName,
            u.Reputation,
            u.CreationDate,
            u.LastAccessDate,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
            COUNT(b.Id) AS TotalBadges
        FROM Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
    ),
    p AS (
        SELECT
            p.OwnerUserId AS UserId,
            COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
            COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
            AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
            AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
            SUM(p.ViewCount) AS TotalViews,
            MIN(p.CreationDate) AS FirstPostDate,
            MAX(p.LastActivityDate) AS LastPostActivity
        FROM Posts p
        GROUP BY p.OwnerUserId
    ),
    recent AS (
        SELECT
            p.OwnerUserId AS UserId,
            p.Title AS RecentQuestionTitle,
            p.CreationDate AS RecentQuestionDate
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.OwnerUserId IS NOT NULL
          AND p.CreationDate = (
                SELECT MAX(p2.CreationDate)
                FROM Posts p2
                WHERE p2.OwnerUserId = p.OwnerUserId
                  AND p2.PostTypeId = 1
          )
    ),
    top_tag AS (
        SELECT
            tags_exp.OwnerUserId AS UserId,
            tags_exp.tag,
            COUNT(*) AS cnt,
            ROW_NUMBER() OVER (PARTITION BY tags_exp.OwnerUserId ORDER BY COUNT(*) DESC) AS rn
        FROM (
            SELECT
                p.OwnerUserId,
                unnest(string_to_array(
                    regexp_replace(p.Tags, '^<|>$', '', 'g'), '><'
                )) AS tag
            FROM Posts p
            WHERE p.PostTypeId = 1
              AND p.Tags IS NOT NULL
        ) AS tags_exp
        GROUP BY tags_exp.OwnerUserId, tags_exp.tag
    ),
    user_tags AS (
        SELECT
            UserId,
            tag AS TopTag
        FROM top_tag
        WHERE rn = 1
    ),
    ranked AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            u.GoldBadges,
            u.SilverBadges,
            u.BronzeBadges,
            COALESCE(p.QuestionCount,0) AS QuestionCount,
            COALESCE(p.AnswerCount,0) AS AnswerCount,
            COALESCE(p.AvgQuestionScore,0) AS AvgQuestionScore,
            COALESCE(p.AvgAnswerScore,0) AS AvgAnswerScore,
            COALESCE(p.TotalViews,0) AS TotalViews,
            COALESCE(r.RecentQuestionTitle, '(none)') AS RecentQuestionTitle,
            COALESCE(ut.TopTag, '(none)') AS TopTag,
            ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COALESCE(p.TotalViews,0) DESC) AS ReputationRank
        FROM u
        LEFT JOIN p ON p.UserId = u.Id
        LEFT JOIN recent r ON r.UserId = u.Id
        LEFT JOIN user_tags ut ON ut.UserId = u.Id
        WHERE u.Reputation > 1000
           OR (u.TotalBadges > 10 AND COALESCE(p.TotalViews,0) > 5000)
    )
SELECT
    Id,
    DisplayName,
    Reputation,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    QuestionCount,
    AnswerCount,
    ROUND(AvgQuestionScore,2) AS AvgQuestionScore,
    ROUND(AvgAnswerScore,2) AS AvgAnswerScore,
    TotalViews,
    RecentQuestionTitle,
    TopTag,
    ReputationRank
FROM ranked
WHERE ReputationRank <= 100

UNION ALL

SELECT
    u.Id,
    COALESCE(u.DisplayName, 'Ghost') AS DisplayName,
    u.Reputation,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    0 AS QuestionCount,
    0 AS AnswerCount,
    0 AS AvgQuestionScore,
    0 AS AvgAnswerScore,
    0 AS TotalViews,
    '(no posts)' AS RecentQuestionTitle,
    '(no tags)' AS TopTag,
    NULL AS ReputationRank
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
  AND u.Reputation < 500
ORDER BY Reputation DESC NULLS LAST, Id;
