WITH RecentPosts AS (
    SELECT  p.Id,
            p.PostTypeId,
            p.OwnerUserId,
            p.CreationDate,
            p.Score,
            p.Title,
            COALESCE(p.Tags,'') AS Tags,
            ROW_NUMBER() OVER (
                PARTITION BY p.OwnerUserId
                ORDER BY p.CreationDate DESC
            ) AS rn
    FROM    Posts p
    WHERE   p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30' DAY
),
UserStats AS (
    SELECT  u.Id                                      AS UserId,
            u.DisplayName,
            u.Reputation,
            COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
            COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
            AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
            AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
            SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAccepted,
            MAX(p.CreationDate)                     AS LastPostDate
    FROM    Users u
    LEFT JOIN Posts p
           ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagAgg AS (
    SELECT  t.TagName,
            COUNT(DISTINCT p.Id)                      AS PostsWithTag,
            SUM(p.Score)                              AS TotalScore,
            MAX(p.CreationDate)                       AS LatestPost
    FROM    Tags t
    JOIN    Posts p
           ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE   p.PostTypeId = 1
    GROUP BY t.TagName
),
TopAnswers AS (
    SELECT  a.Id                               AS AnswerId,
            a.ParentId                         AS QuestionId,
            a.OwnerUserId,
            a.Score,
            ROW_NUMBER() OVER (
                PARTITION BY a.ParentId
                ORDER BY a.Score DESC, a.CreationDate ASC
            )                                 AS rank_in_question
    FROM    Posts a
    WHERE   a.PostTypeId = 2
),
BadgeCounts AS (
    SELECT  b.UserId,
            COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
            COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
            COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM    Badges b
    GROUP BY b.UserId
)

SELECT  us.UserId,
        us.DisplayName,
        us.Reputation,
        us.QuestionCount,
        us.AnswerCount,
        us.AvgQuestionScore,
        us.AvgAnswerScore,
        us.QuestionsWithAccepted,
        COALESCE(bc.GoldBadges,0)   AS GoldBadges,
        COALESCE(bc.SilverBadges,0) AS SilverBadges,
        COALESCE(bc.BronzeBadges,0) AS BronzeBadges,
        CASE
            WHEN us.QuestionCount = 0 THEN NULL
            ELSE ROUND(100.0 * us.QuestionsWithAccepted / us.QuestionCount,2)
        END                         AS AcceptanceRatePct,
        STRING_AGG(DISTINCT pt.TagName, ', ') 
                                    AS TopTags
FROM    UserStats us
LEFT JOIN BadgeCounts bc
       ON bc.UserId = us.UserId
LEFT JOIN RecentPosts rp
       ON rp.OwnerUserId = us.UserId AND rp.rn = 1
LEFT JOIN LATERAL (
        SELECT  pt.TagName
        FROM (
            SELECT TRIM(BOTH '<>' FROM regexp_split_to_table(rp.Tags, '><')) AS tag
        ) AS t_elem
        JOIN Tags pt
          ON pt.TagName = t_elem.tag
        ORDER BY pt.count DESC
        LIMIT 5
) pt ON TRUE
GROUP BY us.UserId, us.DisplayName, us.Reputation,
         us.QuestionCount, us.AnswerCount,
         us.AvgQuestionScore, us.AvgAnswerScore,
         us.QuestionsWithAccepted,
         bc.GoldBadges, bc.SilverBadges, bc.BronzeBadges
HAVING us.Reputation > 1000

UNION ALL

SELECT  NULL                         AS UserId,
        '--- Tag Summary ---'        AS DisplayName,
        NULL                         AS Reputation,
        NULL                         AS QuestionCount,
        NULL                         AS AnswerCount,
        NULL                         AS AvgQuestionScore,
        NULL                         AS AvgAnswerScore,
        NULL                         AS QuestionsWithAccepted,
        NULL                         AS GoldBadges,
        NULL                         AS SilverBadges,
        NULL                         AS BronzeBadges,
        NULL                         AS AcceptanceRatePct,
        STRING_AGG(t.TagName || ':' || CAST(t.PostsWithTag AS varchar), '; ' ORDER BY t.PostsWithTag DESC)
                                    AS TopTags
FROM    TagAgg t
WHERE   t.PostsWithTag > 100

ORDER BY Reputation DESC NULLS LAST, UserId;