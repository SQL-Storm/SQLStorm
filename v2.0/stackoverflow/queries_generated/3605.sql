-- {"query": "3605.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2251} 

/*  Complex benchmark query using CTEs, window functions, outer joins, 
    correlated subqueries, set operators and advanced expressions   */
WITH RecentPosts AS (
    SELECT  p.Id,
            p.PostTypeId,
            p.OwnerUserId,
            p.CreationDate,
            p.Score,
            p.Title,
            COALESCE(p.Tags,'')               AS Tags,
            ROW_NUMBER() OVER (
                PARTITION BY p.OwnerUserId
                ORDER BY p.CreationDate DESC
            )                                 AS rn
    FROM    Posts p
    WHERE   p.CreationDate >= CURRENT_DATE - INTERVAL '30 day'
),
UserStats AS (
    SELECT  u.Id                                      AS UserId,
            u.DisplayName,
            u.Reputation,
            COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
            COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
            AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
            AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
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
    WHERE   p.PostTypeId = 1          -- only questions
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
    WHERE   a.PostTypeId = 2                -- answers only
),
BadgeCounts AS (
    SELECT  b.UserId,
            COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
            COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
            COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
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
        STRING_AGG(DISTINCT pt.TagName, ', ') FILTER (WHERE pt.TagName IS NOT NULL) 
                                    AS TopTags
FROM    UserStats us
LEFT JOIN BadgeCounts bc
       ON bc.UserId = us.UserId
LEFT JOIN LATERAL (
        SELECT  t_elem.tag
        FROM    UNNEST(string_to_array(rp.Tags, '><')) AS t_elem(tag)
        JOIN    Tags pt
               ON pt.TagName = t_elem.tag
        WHERE   rp.rn = 1
        ORDER BY pt.Count DESC
        LIMIT 5
) pt ON TRUE
LEFT JOIN RecentPosts rp
       ON rp.OwnerUserId = us.UserId AND rp.rn = 1
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
        STRING_AGG(t.TagName || ':' || t.PostsWithTag, '; ' ORDER BY t.PostsWithTag DESC)
                                    AS TopTags
FROM    TagAgg t
WHERE   t.PostsWithTag > 100

ORDER BY Reputation DESC NULLS LAST, UserId;
