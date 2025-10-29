-- {"query": "3045.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2650} 

/*  Complex benchmark query that touches most tables, uses CTEs, window functions,
    outer joins, correlated sub‑queries, set operators, string handling and NULL logic */
WITH UserPostStats AS (
    SELECT
        u.Id                     AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)                         AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)                         AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2))                   AS AvgScore,
        MAX(p.CreationDate)                                                AS LastPostDate,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END)
                                                                              AS QuestionsWithAccepted
    FROM Users u
    LEFT JOIN Posts p
           ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(*)                                                     AS BadgeCount,
        COUNT(*) FILTER (WHERE b.Class = 1)                         AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2)                         AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3)                         AS BronzeBadges,
        MAX(b.Date)                                                 AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),

UserTagInfo AS (
    SELECT
        u.Id                                            AS UserId,
        STRING_AGG(DISTINCT t.TagName, ',')             AS UsedTags,
        COUNT(DISTINCT t.Id)                            AS DistinctTagCount
    FROM Users u
    LEFT JOIN Posts p
           ON p.OwnerUserId = u.Id
          AND p.PostTypeId = 1          -- only questions have tags
    LEFT JOIN LATERAL (
        SELECT regexp_split_to_table(p.Tags, '<>') AS RawTag
    ) AS split ON true
    LEFT JOIN Tags t
           ON t.TagName = split.RawTag
    GROUP BY u.Id
),

RecentVotes AS (
    SELECT
        v.UserId,
        COUNT(*) FILTER (WHERE vt.Name = 'UpMod')   AS UpVotesGiven,
        COUNT(*) FILTER (WHERE vt.Name = 'DownMod') AS DownVotesGiven,
        MAX(v.CreationDate)                         AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.UserId
),

Combined AS (
    SELECT
        ups.UserId,
        ups.DisplayName,
        ups.Reputation,
        ups.QuestionCount,
        ups.AnswerCount,
        ups.AvgScore,
        ups.LastPostDate,
        ups.QuestionsWithAccepted,
        COALESCE(ubs.BadgeCount,0)      AS BadgeCount,
        COALESCE(ubs.GoldBadges,0)      AS GoldBadges,
        COALESCE(ubs.SilverBadges,0)    AS SilverBadges,
        COALESCE(ubs.BronzeBadges,0)    AS BronzeBadges,
        ubs.LastBadgeDate,
        uti.UsedTags,
        uti.DistinctTagCount,
        COALESCE(rv.UpVotesGiven,0)     AS UpVotesGiven,
        COALESCE(rv.DownVotesGiven,0)   AS DownVotesGiven,
        rv.LastVoteDate,
        /* correlated sub‑query – latest comment text per user */
        (SELECT c.Text
         FROM Comments c
         WHERE c.UserId = ups.UserId
         ORDER BY c.CreationDate DESC
         LIMIT 1)                         AS LatestCommentText,
        ROW_NUMBER() OVER (
            ORDER BY (ups.QuestionCount + ups.AnswerCount) DESC,
                     ups.Reputation DESC
        )                                 AS ActivityRank
    FROM UserPostStats ups
    LEFT JOIN UserBadgeStats ubs ON ubs.UserId = ups.UserId
    LEFT JOIN UserTagInfo   uti ON uti.UserId = ups.UserId
    LEFT JOIN RecentVotes   rv  ON rv.UserId = ups.UserId
)

SELECT
    UserId,
    DisplayName,
    Reputation,
    QuestionCount,
    AnswerCount,
    AvgScore,
    LastPostDate,
    QuestionsWithAccepted,
    BadgeCount,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    LastBadgeDate,
    UsedTags,
    DistinctTagCount,
    UpVotesGiven,
    DownVotesGiven,
    LastVoteDate,
    LatestCommentText,
    ActivityRank
FROM Combined
WHERE ActivityRank <= 100
ORDER BY ActivityRank

UNION ALL

/*  Summary row – demonstrates set operator usage  */
SELECT
    NULL                         AS UserId,
    'TOTAL'                      AS DisplayName,
    SUM(Reputation)              AS Reputation,
    SUM(QuestionCount)           AS QuestionCount,
    SUM(AnswerCount)             AS AnswerCount,
    AVG(AvgScore)                AS AvgScore,
    MAX(LastPostDate)            AS LastPostDate,
    SUM(QuestionsWithAccepted)   AS QuestionsWithAccepted,
    SUM(BadgeCount)              AS BadgeCount,
    SUM(GoldBadges)              AS GoldBadges,
    SUM(SilverBadges)            AS SilverBadges,
    SUM(BronzeBadges)            AS BronzeBadges,
    MAX(LastBadgeDate)           AS LastBadgeDate,
    NULL                         AS UsedTags,
    NULL                         AS DistinctTagCount,
    SUM(UpVotesGiven)            AS UpVotesGiven,
    SUM(DownVotesGiven)          AS DownVotesGiven,
    MAX(LastVoteDate)            AS LastVoteDate,
    NULL                         AS LatestCommentText,
    NULL                         AS ActivityRank
FROM Combined
WHERE ActivityRank IS NOT NULL;
