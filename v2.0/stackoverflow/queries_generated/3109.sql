-- {"query": "3109.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2958} 
WITH 
    UserStats AS (
        SELECT 
            u.Id,
            u.DisplayName,
            u.Reputation,
            COALESCE(u.LastAccessDate, u.CreationDate) AS LastActive,
            COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
            COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
            COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
            SUM(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AnswerScoreSum,
            MAX(p.CreationDate) FILTER (WHERE p.PostTypeId = 1) AS LastQuestionDate
        FROM Users u
        LEFT JOIN Badges b        ON b.UserId = u.Id
        LEFT JOIN Posts p        ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation, u.LastAccessDate, u.CreationDate
    ),
    RecentVotes AS (
        SELECT 
            v.UserId,
            COUNT(*)                                            AS VoteCount,
            SUM(CASE WHEN vt.Name = 'UpMod'   THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
        GROUP BY v.UserId
    ),
    TagPopularity AS (
        SELECT 
            t.TagName,
            t.Count,
            ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS Rank
        FROM Tags t
        WHERE t.IsModeratorOnly = 0
    ),
    TopTagQuestions AS (
        SELECT 
            p.Id,
            p.Title,
            p.Tags,
            p.Score,
            ROW_NUMBER() OVER (
                PARTITION BY tag
                ORDER BY p.Score DESC
            ) AS TagRank
        FROM Posts p
        CROSS JOIN LATERAL (
            SELECT UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
        ) AS tags
        WHERE p.PostTypeId = 1
          AND p.Tags IS NOT NULL
    ),
    UserTagAffinity AS (
        SELECT 
            us.Id         AS UserId,
            tg.TagName,
            COUNT(*)                                            AS QuestionsAnswered,
            SUM(p.Score)                                        AS AnswerScoreSum
        FROM UserStats us
        JOIN Posts a      ON a.OwnerUserId = us.Id AND a.PostTypeId = 2
        JOIN LATERAL (
            SELECT UNNEST(string_to_array(substring(a.Tags, 2, length(a.Tags)-2), '><')) AS tag
        ) AS atag ON TRUE
        JOIN Tags tg      ON tg.TagName = atag.tag
        GROUP BY us.Id, tg.TagName
    ),
    RankedUsers AS (
        SELECT 
            us.Id,
            us.DisplayName,
            us.Reputation,
            us.GoldBadges,
            us.SilverBadges,
            us.BronzeBadges,
            us.QuestionCount,
            us.AnswerCount,
            us.AnswerScoreSum,
            COALESCE(rv.VoteCount,0)                               AS RecentVoteCount,
            ROW_NUMBER() OVER (
                ORDER BY 
                    (us.Reputation * 0.5) +
                    (us.AnswerScoreSum * 0.3) +
                    (us.GoldBadges * 100) +
                    (us.SilverBadges * 50) +
                    (us.BronzeBadges * 20) +
                    (COALESCE(rv.VoteCount,0) * 2)
                DESC
            )                                                    AS OverallRank
        FROM UserStats us
        LEFT JOIN RecentVotes rv ON rv.UserId = us.Id
    )
SELECT 
    ru.Id,
    ru.DisplayName,
    ru.Reputation,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ru.QuestionCount,
    ru.AnswerCount,
    ru.AnswerScoreSum,
    ru.RecentVoteCount,
    ru.OverallRank,
    COALESCE(ut.TagName,'None')               AS TopTag,
    COALESCE(uta.QuestionsAnswered,0)         AS AnswersInTopTag,
    COALESCE(uta.AnswerScoreSum,0)            AS ScoreInTopTag
FROM RankedUsers ru
LEFT JOIN LATERAL (
    SELECT t.TagName
    FROM TagPopularity t
    WHERE t.Rank <= 5
    ORDER BY t.Rank
    LIMIT 1
) ut ON TRUE
LEFT JOIN UserTagAffinity uta 
    ON uta.UserId = ru.Id 
   AND uta.TagName = ut.TagName
WHERE ru.OverallRank <= 100

UNION ALL

SELECT 
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
WHERE NOT EXISTS (SELECT 1 FROM RankedUsers WHERE OverallRank <= 100)

EXCEPT

SELECT 
    Id,
    DisplayName,
    Reputation,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    QuestionCount,
    AnswerCount,
    AnswerScoreSum,
    RecentVoteCount,
    OverallRank,
    TopTag,
    AnswersInTopTag,
    ScoreInTopTag
FROM (
    SELECT 
        ru.Id,
        ru.DisplayName,
        ru.Reputation,
        ru.GoldBadges,
        ru.SilverBadges,
        ru.BronzeBadges,
        ru.QuestionCount,
        ru.AnswerCount,
        ru.AnswerScoreSum,
        ru.RecentVoteCount,
        ru.OverallRank,
        ut.TagName                              AS TopTag,
        COALESCE(uta.QuestionsAnswered,0)      AS AnswersInTopTag,
        COALESCE(uta.AnswerScoreSum,0)         AS ScoreInTopTag
    FROM RankedUsers ru
    LEFT JOIN LATERAL (
        SELECT t.TagName
        FROM TagPopularity t
        WHERE t.Rank <= 5
        ORDER BY t.Rank
        LIMIT 1
    ) ut ON TRUE
    LEFT JOIN UserTagAffinity uta 
        ON uta.UserId = ru.Id 
       AND uta.TagName = ut.TagName
    WHERE ru.OverallRank <= 100
) sub
ORDER BY OverallRank
LIMIT 100;