-- {"query": "3939.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2249} 

WITH
    q_user AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)               AS NetVotes,
            COUNT(b.Id)        FILTER (WHERE b.Class = 1)                AS GoldBadges,
            COUNT(b.Id)        FILTER (WHERE b.Class = 2)                AS SilverBadges,
            COUNT(b.Id)        FILTER (WHERE b.Class = 3)                AS BronzeBadges,
            SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END)               AS TagBasedBadges
        FROM Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
    ),
    q_post AS (
        SELECT
            p.OwnerUserId                                                   AS UserId,
            COUNT(*)               FILTER (WHERE p.PostTypeId = 1)         AS QuestionCount,
            COUNT(*)               FILTER (WHERE p.PostTypeId = 2)         AS AnswerCount,
            AVG(p.Score)           FILTER (WHERE p.PostTypeId = 1)         AS AvgQuestionScore,
            AVG(p.Score)           FILTER (WHERE p.PostTypeId = 2)         AS AvgAnswerScore,
            MAX(p.CreationDate)                                            AS LastPostDate,
            STRING_AGG(
                DISTINCT TRIM(BOTH '<>' FROM UNNEST(string_to_array(p.Tags,'><'))),
                ','
            ) FILTER (WHERE p.Tags IS NOT NULL)                            AS AllTags
        FROM Posts p
        GROUP BY p.OwnerUserId
    ),
    q_vote AS (
        SELECT
            v.PostId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)               AS UpVotes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)               AS DownVotes,
            COUNT(*) FILTER (WHERE v.VoteTypeId = 5)                        AS FavoriteCount
        FROM Votes v
        GROUP BY v.PostId
    ),
    q_top_tags AS (
        SELECT
            t.TagName,
            t.Count,
            ROW_NUMBER() OVER (ORDER BY t.Count DESC)                      AS rn
        FROM Tags t
        WHERE t.IsModeratorOnly = 0
    )
SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.NetVotes,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    u.TagBasedBadges,
    COALESCE(p.QuestionCount,0)                                          AS Questions,
    COALESCE(p.AnswerCount,0)                                            AS Answers,
    ROUND(COALESCE(p.AvgQuestionScore,0),2)                              AS AvgQScore,
    ROUND(COALESCE(p.AvgAnswerScore,0),2)                                AS AvgAScore,
    p.LastPostDate,
    p.AllTags,
    CASE
        WHEN COALESCE(p.AnswerCount,0) = 0 THEN NULL
        ELSE ROUND(
                COALESCE(p.AnswerCount,0)::numeric /
                NULLIF(COALESCE(p.QuestionCount,0),0),2)
    END                                                                 AS AnswerToQuestionRatio,
    EXISTS (
        SELECT 1
        FROM Posts q
        WHERE q.OwnerUserId = u.Id
          AND q.PostTypeId = 1
          AND q.Score < 0
        LIMIT 1
    )                                                                   AS HasNegativeScoreQuestion,
    (
        SELECT STRING_AGG(tag, ';')
        FROM (
            SELECT tag
            FROM UNNEST(string_to_array(p.AllTags,',')) AS tag
            ORDER BY tag
            LIMIT 5
        ) sub
    )                                                                   AS Top5Tags
FROM q_user u
LEFT JOIN q_post p ON p.UserId = u.Id
WHERE u.Reputation > 1000
  AND (u.GoldBadges + u.SilverBadges + u.BronzeBadges) >= 10
  AND (u.NetVotes > 0 OR u.TagBasedBadges > 0)

UNION ALL

SELECT
    NULL                                           AS Id,
    'Top Tags'                                     AS DisplayName,
    NULL                                           AS Reputation,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    STRING_AGG(t.TagName, ', ')                    AS TopTags
FROM q_top_tags t
WHERE t.rn <= 10

ORDER BY Reputation DESC NULLS LAST, GoldBadges DESC, Id;
