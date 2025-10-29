-- {"query": "3933.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2299}
WITH RecentQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.OwnerUserId,
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVoteCount
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '180' DAY
),

ExplodedTags AS (
    SELECT
        q.Id,
        q.Title,
        q.OwnerUserId,
        TRIM(BOTH '<>' FROM UNNEST(string_to_array(SUBSTRING(q.Tags,2, LENGTH(q.Tags)-2), '><'))) AS Tag,
        q.UpVoteCount,
        q.CreationDate
    FROM RecentQuestions q
    WHERE q.Tags IS NOT NULL
),

UserTagStats AS (
    SELECT
        e.Tag,
        u.Id                               AS UserId,
        COALESCE(u.DisplayName, 'Anonymous') AS DisplayName,
        u.Reputation,
        COUNT(DISTINCT e.Id)               AS QuestionCount,
        SUM(e.UpVoteCount)                 AS TotalUpVotes,
        MAX(e.CreationDate)                AS LatestQuestionDate,
        ROW_NUMBER() OVER (PARTITION BY e.Tag 
                           ORDER BY u.Reputation DESC, COUNT(DISTINCT e.Id) DESC) AS TagRank
    FROM ExplodedTags e
    JOIN Users u                     ON u.Id = e.OwnerUserId
    LEFT OUTER JOIN Badges b         ON b.UserId = u.Id AND b.Class = 1
    GROUP BY e.Tag, u.Id, u.DisplayName, u.Reputation
),

TopTagContributors AS (
    SELECT
        Tag,
        UserId,
        DisplayName,
        Reputation,
        QuestionCount,
        TotalUpVotes,
        LatestQuestionDate
    FROM UserTagStats
    WHERE TagRank <= 3
),

OverallStats AS (
    SELECT
        u.Id                                                    AS UserId,
        COALESCE(u.DisplayName, 'Anonymous')                    AS DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)             AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)             AS AnswerCount,
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.UserId = u.Id AND v.VoteTypeId = 2)           AS TotalUpVotesGiven,
        SUM(CASE WHEN b.Class = 1 THEN 3
                 WHEN b.Class = 2 THEN 2
                 ELSE 1 END)                                   AS BadgeScore
    FROM Users u
    LEFT OUTER JOIN Posts p   ON p.OwnerUserId = u.Id 
                               AND p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '180' DAY
    LEFT OUTER JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING u.Reputation > 15000 OR SUM(CASE WHEN b.Class = 1 THEN 3 WHEN b.Class = 2 THEN 2 ELSE 1 END) >= 10
)

SELECT
    'Tag'      AS Scope,
    t.Tag,
    t.UserId,
    t.DisplayName,
    t.Reputation,
    t.QuestionCount,
    t.TotalUpVotes,
    CAST(t.LatestQuestionDate AS DATE) AS RecentDate
FROM TopTagContributors t

UNION ALL

SELECT
    'Overall'  AS Scope,
    NULL       AS Tag,
    o.UserId,
    o.DisplayName,
    o.Reputation,
    o.QuestionCount,
    o.TotalUpVotesGiven,
    NULL       AS RecentDate
FROM OverallStats o

ORDER BY Scope,
         Reputation DESC,
         QuestionCount DESC;