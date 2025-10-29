-- {"query": "3502.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2297} 
WITH
    /* Extract questions that contain each tag */
    TagQuestions AS (
        SELECT
            t.Id                AS TagId,
            t.TagName,
            p.Id                AS QuestionId,
            p.OwnerUserId       AS QuestionOwnerId,
            p.Score             AS QuestionScore,
            p.CreationDate     AS QuestionCreated,
            p.Tags
        FROM Tags t
        JOIN Posts p
          ON p.PostTypeId = 1                /* only questions */
         AND p.Tags LIKE '%<'||t.TagName||'>%'
    ),
    /* Aggregate answers per user per tag */
    AnswerStats AS (
        SELECT
            tq.TagId,
            tq.TagName,
            a.OwnerUserId      AS AnswererId,
            COUNT(*)           AS AnswerCount,
            SUM(a.Score)       AS AnswerScoreSum,
            MAX(a.CreationDate) AS LastAnswerDate
        FROM TagQuestions tq
        JOIN Posts a
          ON a.PostTypeId = 2                /* only answers */
         AND a.ParentId = tq.QuestionId
        GROUP BY tq.TagId, tq.TagName, a.OwnerUserId
    ),
    /* Badge totals per user */
    UserBadges AS (
        SELECT
            b.UserId,
            COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
            COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
            COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
        FROM Badges b
        GROUP BY b.UserId
    ),
    /* Vote totals per post */
    PostVotes AS (
        SELECT
            v.PostId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes v
        GROUP BY v.PostId
    ),
    /* Sum vote totals per answerer */
    UserVoteAgg AS (
        SELECT
            a.OwnerUserId               AS UserId,
            COALESCE(SUM(pv.UpVotes),0)   AS TotalUpVotes,
            COALESCE(SUM(pv.DownVotes),0) AS TotalDownVotes
        FROM Posts a
        LEFT JOIN PostVotes pv ON pv.PostId = a.Id
        WHERE a.PostTypeId = 2
        GROUP BY a.OwnerUserId
    ),
    /* Rank users within each tag */
    RankedAnswers AS (
        SELECT
            asr.*,
            ROW_NUMBER() OVER (
                PARTITION BY asr.TagId
                ORDER BY asr.AnswerScoreSum DESC, asr.AnswerCount DESC
            ) AS RankInTag
        FROM AnswerStats asr
    )
SELECT
    ra.TagName,
    ra.RankInTag,
    u.Id                                 AS UserId,
    COALESCE(u.DisplayName, 'Deleted')   AS DisplayName,
    ra.AnswerCount,
    ra.AnswerScoreSum,
    ra.LastAnswerDate,
    COALESCE(ub.GoldBadges,   0)          AS GoldBadges,
    COALESCE(ub.SilverBadges, 0)          AS SilverBadges,
    COALESCE(ub.BronzeBadges, 0)          AS BronzeBadges,
    COALESCE(uv.TotalUpVotes,   0)        AS TotalUpVotesOnAnswers,
    COALESCE(uv.TotalDownVotes, 0)        AS TotalDownVotesOnAnswers,
    CASE
        WHEN u.Reputation >= 20000 THEN 'Legendary'
        WHEN u.Reputation >= 10000 THEN 'Expert'
        WHEN u.Reputation >= 5000  THEN 'Seasoned'
        ELSE 'Novice'
    END                                   AS ReputationTier,
    EXISTS (
        SELECT 1
        FROM Comments c
        WHERE c.UserId = u.Id
          AND c.CreationDate > cast('2024-10-01' as date) - INTERVAL '30 days'
          AND c.Text ILIKE '%'||ra.TagName||'%'
    )                                      AS RecentTagComment
FROM RankedAnswers ra
LEFT JOIN Users u          ON u.Id = ra.AnswererId
LEFT JOIN UserBadges ub    ON ub.UserId = u.Id
LEFT JOIN UserVoteAgg uv   ON uv.UserId = u.Id
WHERE ra.RankInTag <= 5

UNION ALL

/* Tags without any answers (to keep result set wide) */
SELECT
    t.TagName,
    NULL                               AS RankInTag,
    NULL                               AS UserId,
    NULL                               AS DisplayName,
    0                                  AS AnswerCount,
    0                                  AS AnswerScoreSum,
    NULL                               AS LastAnswerDate,
    0                                  AS GoldBadges,
    0                                  AS SilverBadges,
    0                                  AS BronzeBadges,
    0                                  AS TotalUpVotesOnAnswers,
    0                                  AS TotalDownVotesOnAnswers,
    'NoAnswer'                         AS ReputationTier,
    FALSE                              AS RecentTagComment
FROM Tags t
WHERE NOT EXISTS (
    SELECT 1
    FROM AnswerStats a
    WHERE a.TagId = t.Id
)

ORDER BY TagName, RankInTag;