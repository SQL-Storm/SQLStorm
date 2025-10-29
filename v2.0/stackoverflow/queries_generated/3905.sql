-- {"query": "3905.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2597} 

WITH
    RecentActivity AS (
        SELECT
            p.OwnerUserId AS UserId,
            MAX(p.LastActivityDate) AS LastActivity,
            COUNT(*) FILTER (WHERE p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL) AS AcceptedAnswers,
            COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
            COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),
    BadgeSummary AS (
        SELECT
            b.UserId,
            SUM(CASE WHEN b.Class = 1 THEN 3 WHEN b.Class = 2 THEN 2 ELSE 1 END) AS BadgePoints,
            STRING_AGG(DISTINCT b.Name, ', ') AS BadgeList
        FROM Badges b
        GROUP BY b.UserId
    ),
    VoteImpact AS (
        SELECT
            v.PostId,
            SUM(CASE
                    WHEN vt.Name = 'UpMod'               THEN 1
                    WHEN vt.Name = 'DownMod'             THEN -1
                    WHEN vt.Name = 'AcceptedByOriginator' THEN 15
                    ELSE 0
                END) AS VoteScore
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY v.PostId
    ),
    TagExtraction AS (
        SELECT
            p.Id AS PostId,
            UNNEST(
                CASE
                    WHEN p.Tags IS NULL THEN ARRAY[]::text[]
                    ELSE regexp_split_to_array(trim(both '<>' FROM p.Tags), '><')
                END
            ) AS Tag
        FROM Posts p
        WHERE p.PostTypeId = 1
    ),
    TagPopularity AS (
        SELECT
            t.Tag,
            COUNT(*) AS TagUseCount,
            SUM(COALESCE(vi.VoteScore, 0)) AS TagVoteScore
        FROM TagExtraction t
        LEFT JOIN VoteImpact vi ON vi.PostId = t.PostId
        GROUP BY t.Tag
    ),
    UserPostScore AS (
        SELECT
            p.OwnerUserId AS UserId,
            SUM(p.Score) AS QuestionScore,
            SUM(COALESCE(vi.VoteScore, 0)) AS AnswerVoteScore
        FROM Posts p
        LEFT JOIN VoteImpact vi ON vi.PostId = p.Id
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),
    Combined AS (
        SELECT
            u.Id AS UserId,
            u.DisplayName,
            u.Reputation,
            COALESCE(ra.LastActivity, u.CreationDate) AS LastActivityDate,
            COALESCE(bs.BadgePoints, 0) AS BadgePoints,
            bs.BadgeList,
            COALESCE(ups.QuestionScore, 0) AS QuestionScore,
            COALESCE(ups.AnswerVoteScore, 0) AS AnswerVoteScore,
            COALESCE(ra.AcceptedAnswers, 0) AS AcceptedAnswers,
            COALESCE(ra.AnswersPosted, 0) AS AnswersPosted,
            COALESCE(ra.QuestionsPosted, 0) AS QuestionsPosted,
            (COALESCE(ups.QuestionScore, 0) * 2
             + COALESCE(ups.AnswerVoteScore, 0)
             + u.Reputation / 1000
             + COALESCE(bs.BadgePoints, 0)
             + COALESCE(ra.AcceptedAnswers, 0) * 5) AS CompositeScore
        FROM Users u
        LEFT JOIN RecentActivity ra   ON ra.UserId = u.Id
        LEFT JOIN BadgeSummary bs     ON bs.UserId = u.Id
        LEFT JOIN UserPostScore ups   ON ups.UserId = u.Id
    ),
    RankedUsers AS (
        SELECT
            *,
            RANK() OVER (ORDER BY CompositeScore DESC) AS RankByScore,
            ROW_NUMBER() OVER (PARTITION BY COALESCE(NULLIF(u.Location, ''), 'Unknown')
                               ORDER BY CompositeScore DESC) AS RowInLocation
        FROM Combined u
    )
SELECT
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.CompositeScore,
    ru.RankByScore,
    ru.RowInLocation,
    ru.BadgeList,
    CASE
        WHEN ru.BadgePoints > 20 THEN 'Master'
        WHEN ru.BadgePoints BETWEEN 10 AND 20 THEN 'Expert'
        ELSE 'Contributor'
    END AS BadgeTier,
    COALESCE(tp.TagUseCount, 0) AS TopTagUseCount,
    COALESCE(tp.TagVoteScore, 0) AS TopTagVoteScore,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM Posts p2
            WHERE p2.OwnerUserId = ru.UserId
              AND p2.CreationDate > ru.LastActivityDate - INTERVAL '30 days'
              AND p2.PostTypeId = 1
        ) THEN TRUE
        ELSE FALSE
    END AS HasRecentQuestion
FROM RankedUsers ru
LEFT JOIN LATERAL (
    SELECT
        tp.Tag,
        tp.TagUseCount,
        tp.TagVoteScore
    FROM TagPopularity tp
    ORDER BY tp.TagVoteScore DESC
    LIMIT 1
) tp ON TRUE
WHERE ru.RankByScore <= 1000
ORDER BY ru.RankByScore;
