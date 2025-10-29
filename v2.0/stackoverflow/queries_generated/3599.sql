-- {"query": "3599.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1805} 

/*  Elaborate performance‑benchmarking query on the StackOverflow schema  */
WITH
    /* All answers (PostTypeId = 2) per user, preserving users without answers */
    UserAnswers AS (
        SELECT
            u.Id                         AS UserId,
            u.DisplayName,
            u.Reputation,
            p.Id                         AS AnswerId,
            p.CreationDate,
            p.Score                      AS AnswerScore,
            p.Tags,
            p.ParentId                   AS QuestionId,
            p.LastActivityDate
        FROM Users u
        LEFT JOIN Posts p
            ON p.OwnerUserId = u.Id
           AND p.PostTypeId = 2
    ),

    /* Extract individual tags from the <tag1><tag2> style string */
    AnswerTagStats AS (
        SELECT
            ua.UserId,
            LOWER(TRIM(t))                         AS Tag,
            COUNT(*)                               AS TagAnswerCount,
            AVG(ua.AnswerScore)                    AS AvgTagScore
        FROM UserAnswers ua
        CROSS JOIN LATERAL
            (SELECT UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM ua.Tags), '><')) AS t) AS taglist
        WHERE ua.Tags IS NOT NULL
        GROUP BY ua.UserId, LOWER(TRIM(t))
    ),

    /* Rank tags per user – keep top 3 */
    TopTagsPerUser AS (
        SELECT
            ats.UserId,
            ats.Tag,
            ats.TagAnswerCount,
            ats.AvgTagScore,
            ROW_NUMBER() OVER (PARTITION BY ats.UserId
                               ORDER BY ats.TagAnswerCount DESC, ats.AvgTagScore DESC) AS rn
        FROM AnswerTagStats ats
    ),

    /* Aggregate per‑user statistics, using correlated subquery for avg up‑votes */
    UserAggregates AS (
        SELECT
            u.Id                                                AS UserId,
            u.DisplayName,
            u.Reputation,
            COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score END),0)   AS TotalAnswerScore,
            COALESCE(COUNT(p.Id),0)                                    AS AnswerCount,
            MAX(p.LastActivityDate)                                    AS LastActivity,
            COALESCE((
                SELECT AVG(v.Score)
                FROM Votes v
                JOIN Posts p2 ON v.PostId = p2.Id
                WHERE v.VoteTypeId = 2                -- UpMod
                  AND p2.OwnerUserId = u.Id
            ),0)                                                     AS AvgUpVotesPerPost
        FROM Users u
        LEFT JOIN Posts p
            ON p.OwnerUserId = u.Id
           AND p.PostTypeId = 2
        GROUP BY u.Id, u.DisplayName, u.Reputation
    )

/* Combine users with their top tags; also include a secondary set for low‑rep users with no answers */
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalAnswerScore,
    ua.AnswerCount,
    ua.LastActivity,
    ua.AvgUpVotesPerPost,
    tt.Tag,
    tt.TagAnswerCount,
    tt.AvgTagScore
FROM UserAggregates ua
LEFT JOIN TopTagsPerUser tt
    ON tt.UserId = ua.UserId
   AND tt.rn <= 3
WHERE (ua.Reputation > 10000 OR ua.AnswerCount = 0)                -- filter for high‑rep or no‑answer users
UNION ALL
SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    0            AS TotalAnswerScore,
    0            AS AnswerCount,
    NULL         AS LastActivity,
    0            AS AvgUpVotesPerPost,
    NULL         AS Tag,
    NULL         AS TagAnswerCount,
    NULL         AS AvgTagScore
FROM Users u
WHERE NOT EXISTS (
        SELECT 1
        FROM Posts p
        WHERE p.OwnerUserId = u.Id
          AND p.PostTypeId = 2
      )
  AND u.Reputation < 5000                                          -- low‑rep users without answers
ORDER BY
    Reputation DESC NULLS LAST,
    UserId,
    rn;
