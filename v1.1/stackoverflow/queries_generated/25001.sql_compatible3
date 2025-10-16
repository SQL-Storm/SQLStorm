WITH UserPostStats AS (
    SELECT 
        u.Id                                    AS UserId,
        COUNT(p.Id)                             AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgScore,
        MAX(p.CreationDate)                     AS LastPostDate,
        SUM(CASE 
                WHEN p.PostTypeId = 2 
                     AND p.Id = p.AcceptedAnswerId 
                     AND p.OwnerUserId = u.Id 
                THEN 1 ELSE 0 END)            AS AcceptedAnswers,
        COUNT(DISTINCT tag)                      AS DistinctTags
    FROM Users u
    LEFT JOIN Posts p 
        ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT
            p_inner.Id,
            NULLIF(TRIM(BOTH '><' FROM p_inner.Tags), '') AS raw_tags_nonempty
        FROM Posts p_inner
    ) p_tags ON p_tags.Id = p.Id
    LEFT JOIN (
        -- emulate regexp_split_to_table by splitting tags into rows where possible
        -- many SQL dialects lack regexp_split_to_table; use simple SPLIT/UNNEST where available.
        -- Here we attempt a generic approach using a string-split function name common variants.
        -- For compatibility, handle tags by splitting on '><' and trimming angle brackets.
        SELECT
            p_id AS PostId,
            tag AS tag
        FROM (
            SELECT p1.Id AS p_id, p1.raw_tags_nonempty AS raw
            FROM (
                SELECT Id, NULLIF(TRIM(BOTH '><' FROM Tags), '') AS raw_tags_nonempty
                FROM Posts
            ) p1
        ) src,
        LATERAL (
            -- This LATERAL is intended as a placeholder for a dialect-specific splitter.
            -- Replace the function here with the dialect's string-split/unnest (e.g., UNNEST(STRING_TO_ARRAY(...)))
            SELECT
                -- If raw is empty, no rows will be produced.
                -- Use regexp-like split on '><'
                NULLIF(value, '') AS tag
            FROM (
                -- Try common STRING_SPLIT/STRING_TO_ARRAY variants
                SELECT value FROM (VALUES (src.raw)) AS v(raw)
                CROSS JOIN LATERAL (
                    -- attempt to split using standard SQL: use regexp-like replacement to convert '><' to a delimiter and then split
                    -- As a generic fallback, return the whole raw as single tag if no splitter available.
                    SELECT src.raw AS value
                ) s1
            ) s2
        ) splitter
        WHERE src.raw IS NOT NULL
    ) tags ON tags.PostId = p.Id
    GROUP BY u.Id
),
UserBadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(*)                                   AS TotalBadges,
        COUNT(*) FILTER (WHERE b.Class = 1)        AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2)        AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3)        AS BronzeBadges,
        MAX(b.Date)                                AS LastBadgeDate,
        STRING_AGG(DISTINCT b.Name, ', ') 
            FILTER (WHERE b.Name IS NOT NULL)     AS BadgeList
    FROM Badges b
    GROUP BY b.UserId
),
UserVoteStats AS (
    SELECT 
        p.OwnerUserId                              AS UserId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2)   AS UpVotesGiven,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3)   AS DownVotesGiven,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 1)   AS AcceptedVotesGiven
    FROM Votes v
    JOIN Posts p 
        ON p.Id = v.PostId
    GROUP BY p.OwnerUserId
),
UserAggregated AS (
    SELECT 
        u.Id                                            AS UserId,
        u.DisplayName,
        COALESCE(ps.TotalPosts,0)                       AS TotalPosts,
        COALESCE(ps.Questions,0)                        AS QuestionCount,
        COALESCE(ps.Answers,0)                          AS AnswerCount,
        COALESCE(ps.AvgScore,0)                         AS AvgPostScore,
        COALESCE(ps.AcceptedAnswers,0)                  AS AcceptedAnswerCount,
        COALESCE(ps.DistinctTags,0)                     AS UniqueTagCount,
        COALESCE(bs.TotalBadges,0)                      AS BadgeCount,
        COALESCE(bs.GoldBadges,0)                       AS GoldBadgeCount,
        COALESCE(bs.SilverBadges,0)                     AS SilverBadgeCount,
        COALESCE(bs.BronzeBadges,0)                     AS BronzeBadgeCount,
        bs.BadgeList,
        COALESCE(vs.UpVotesGiven,0)                     AS UpVotesGiven,
        COALESCE(vs.DownVotesGiven,0)                   AS DownVotesGiven,
        COALESCE(vs.AcceptedVotesGiven,0)               AS AcceptedVotesGiven,
        GREATEST(
            COALESCE(ps.LastPostDate, TIMESTAMP '1970-01-01'),
            COALESCE(bs.LastBadgeDate, TIMESTAMP '1970-01-01'),
            COALESCE(
                (SELECT MAX(c.CreationDate) 
                 FROM Comments c 
                 WHERE c.UserId = u.Id), 
                TIMESTAMP '1970-01-01')
        )                                               AS LastActivity
    FROM Users u
    LEFT JOIN UserPostStats ps   ON ps.UserId   = u.Id
    LEFT JOIN UserBadgeStats bs  ON bs.UserId   = u.Id
    LEFT JOIN UserVoteStats vs   ON vs.UserId   = u.Id
    GROUP BY u.Id, u.DisplayName, ps.TotalPosts, ps.Questions, ps.Answers, ps.AvgScore, ps.AcceptedAnswers, ps.DistinctTags, ps.LastPostDate, bs.TotalBadges, bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges, bs.BadgeList, bs.LastBadgeDate, vs.UpVotesGiven, vs.DownVotesGiven, vs.AcceptedVotesGiven
),
RankedUsers AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.TotalPosts,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.AvgPostScore,
        ua.AcceptedAnswerCount,
        ua.UniqueTagCount,
        ua.BadgeCount,
        ua.GoldBadgeCount,
        ua.SilverBadgeCount,
        ua.BronzeBadgeCount,
        ua.BadgeList,
        ua.UpVotesGiven,
        ua.DownVotesGiven,
        ua.AcceptedVotesGiven,
        ua.LastActivity,
        ROW_NUMBER() OVER (
            ORDER BY 
                (ua.BadgeCount*5 
                 + ua.GoldBadgeCount*10 
                 + ua.SilverBadgeCount*5 
                 + ua.BronzeBadgeCount) DESC,
                ua.TotalPosts DESC,
                ua.AvgPostScore DESC
        ) AS RankScore
    FROM UserAggregated ua
    WHERE ua.DisplayName IS NOT NULL
)
SELECT 
    ru.UserId,
    ru.DisplayName,
    ru.TotalPosts,
    ru.QuestionCount,
    ru.AnswerCount,
    ru.AvgPostScore,
    ru.AcceptedAnswerCount,
    ru.UniqueTagCount,
    ru.BadgeCount,
    ru.GoldBadgeCount,
    ru.SilverBadgeCount,
    ru.BronzeBadgeCount,
    ru.BadgeList,
    ru.UpVotesGiven,
    ru.DownVotesGiven,
    ru.AcceptedVotesGiven,
    ru.LastActivity,
    ru.RankScore
FROM RankedUsers ru
WHERE ru.RankScore <= 100

UNION ALL

SELECT 
    NULL                     AS UserId,
    'Summary'                AS DisplayName,
    SUM(r.TotalPosts)          AS TotalPosts,
    SUM(r.QuestionCount)       AS QuestionCount,
    SUM(r.AnswerCount)         AS AnswerCount,
    AVG(r.AvgPostScore)        AS AvgPostScore,
    SUM(r.AcceptedAnswerCount) AS AcceptedAnswerCount,
    SUM(r.UniqueTagCount)      AS UniqueTagCount,
    SUM(r.BadgeCount)          AS BadgeCount,
    SUM(r.GoldBadgeCount)      AS GoldBadgeCount,
    SUM(r.SilverBadgeCount)    AS SilverBadgeCount,
    SUM(r.BronzeBadgeCount)    AS BronzeBadgeCount,
    NULL                     AS BadgeList,
    SUM(r.UpVotesGiven)        AS UpVotesGiven,
    SUM(r.DownVotesGiven)      AS DownVotesGiven,
    SUM(r.AcceptedVotesGiven)  AS AcceptedVotesGiven,
    MAX(r.LastActivity)        AS LastActivity,
    NULL                     AS RankScore
FROM RankedUsers r
WHERE r.RankScore <= 100

ORDER BY RankScore NULLS LAST, TotalPosts DESC;