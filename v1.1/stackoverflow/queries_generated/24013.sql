-- {"query": "24013.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3209} 

WITH
-- Extract tags from each question
question_tags AS (
    SELECT
        q.Id                                   AS QuestionId,
        unnest(string_to_array(substr(q.Tags, 2, length(q.Tags)-2), '><')) AS TagName,
        q.AcceptedAnswerId,
        q.CreationDate                         AS QCreation,
        q.Score                                 AS QScore,
        q.ViewCount,
        q.Score + (q.ViewCount/100.0)           AS QWeight
    FROM Posts q
    WHERE q.PostTypeId = 1
),

-- Answers belonging to those questions
answers AS (
    SELECT
        a.Id                    AS AnswerId,
        a.ParentId              AS QuestionId,
        a.OwnerUserId           AS AnswerUserId,
        a.Score                 AS AScore,
        a.CreationDate          AS ACreation
    FROM Posts a
    WHERE a.PostTypeId = 2
),

-- Upvote / Downvote counts per answer
answer_votes AS (
    SELECT
        a.AnswerId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM answers a
    LEFT JOIN Votes v ON v.PostId = a.AnswerId
    GROUP BY a.AnswerId
),

-- Longest answer length per question (correlated logic embedded later)
longest_answer AS (
    SELECT
        qt.QuestionId,
        MAX(char_length(a.Body)) AS MaxBodyLength
    FROM question_tags qt
    JOIN Posts a ON a.ParentId = qt.QuestionId AND a.PostTypeId = 2
    GROUP BY qt.QuestionId
),

-- User metadata
users_meta AS (
    SELECT
        u.Id           AS UserId,
        u.Reputation,
        u.CreationDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId
    FROM Users u
),

-- Combined tag‑answer statistics
tag_answer_stats AS (
    SELECT
        qt.TagName,
        a.AnswerUserId,
        COUNT(*)                                 AS AnsCount,
        SUM(a.AScore)                            AS TotalScore,
        SUM(av.UpVotes)                          AS TotalUp,
        SUM(av.DownVotes)                        AS TotalDown
    FROM question_tags qt
    JOIN answers a ON a.QuestionId = qt.QuestionId
    LEFT JOIN answer_votes av ON av.AnswerId = a.AnswerId
    GROUP BY qt.TagName, a.AnswerUserId
),

-- Ranking of users per tag
tag_user_rank AS (
    SELECT
        tas.TagName,
        tas.AnswerUserId,
        tas.AnsCount,
        tas.TotalScore,
        tas.TotalUp,
        tas.TotalDown,
        ROW_NUMBER() OVER (PARTITION BY tas.TagName ORDER BY tas.AnsCount DESC, tas.TotalScore DESC) AS TagRank
    FROM tag_answer_stats tas
),

-- Variant scores using a UNION ALL set operator
score_variants AS (
    SELECT UserId, Reputation + 1000 AS PreferScore FROM Users
    UNION ALL
    SELECT UserId, Reputation - 200   AS PreferScore FROM Users
),

-- Final aggregation combining all pieces
final AS (
    SELECT
        u.UserId,
        u.Reputation,
        u.Views,
        tqr.TagName,
        tqr.TagRank,
        tqr.AnsCount,
        tqr.TotalScore,
        tqr.TotalUp,
        tqr.TotalDown,
        (u.Reputation + tqr.TotalScore + (tqr.TotalUp * 10) - (tqr.TotalDown * 5))               AS FameScore,
        CASE WHEN u.Reputation > 10000 THEN 'Veteran' ELSE 'Newcomer' END                         AS Title,
        MAX(sv.PreferScore)                                                                      AS VariantScore
    FROM users_meta u
    LEFT JOIN tag_user_rank tqr ON tqr.AnswerUserId = u.UserId
    LEFT JOIN score_variants sv ON sv.UserId = u.UserId
    WHERE tqr.TagRank IS NOT NULL
    GROUP BY
        u.UserId,
        u.Reputation,
        u.Views,
        tqr.TagName,
        tqr.TagRank,
        tqr.AnsCount,
        tqr.TotalScore,
        tqr.TotalUp,
        tqr.TotalDown
)

SELECT *
FROM final
WHERE FameScore > 0
  AND (Title = 'Veteran' OR TotalUp > 50)
ORDER BY FameScore DESC
LIMIT 500;
