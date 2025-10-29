WITH 
UserPostStats AS (
    SELECT 
        u.Id                       AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COALESCE(SUM(p.Score),0)   AS TotalScore,
        MAX(p.CreationDate)        AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        ups.UserId,
        ups.DisplayName,
        ups.Reputation,
        ups.QuestionCount,
        ups.AnswerCount,
        ups.TotalScore,
        ups.LastPostDate,
        ROW_NUMBER() OVER (ORDER BY ups.Reputation DESC) AS RepRank
    FROM UserPostStats ups
    WHERE ups.Reputation > 1000
),
UserBadgeCounts AS (
    SELECT 
        b.UserId,
        COUNT(*)                                   AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
LatestPostPerUser AS (
    SELECT 
        p.OwnerUserId,
        p.Id               AS PostId,
        p.Title,
        p.Tags,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
),
PostVotesAgg AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(CASE WHEN v.VoteTypeId IN (4,12) THEN 1 END)    AS NegativeFlags
    FROM Votes v
    GROUP BY v.PostId
),
TagStats AS (
    SELECT 
        t.TagName,
        t.Count               AS TagUseCount,
        COALESCE(e.AnswerCount,0) AS ExcerptAnswerCount,
        COALESCE(w.FavoriteCount,0) AS WikiFavorites
    FROM Tags t
    LEFT JOIN Posts e ON e.Id = t.ExcerptPostId
    LEFT JOIN Posts w ON w.Id = t.WikiPostId
),
Combined AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.RepRank,
        tu.QuestionCount,
        tu.AnswerCount,
        tu.TotalScore,
        COALESCE(ub.BadgeCount,0)     AS BadgeCount,
        COALESCE(ub.GoldBadges,0)     AS GoldBadges,
        COALESCE(ub.SilverBadges,0)   AS SilverBadges,
        COALESCE(ub.BronzeBadges,0)   AS BronzeBadges,
        lp.Title                     AS LatestPostTitle,
        lp.CreationDate              AS LatestPostDate,
        CASE 
            WHEN lp.Title IS NOT NULL AND LOWER(lp.Title) LIKE '%sql%'         THEN 'SQL'
            WHEN lp.Title IS NOT NULL AND LOWER(lp.Title) LIKE '%performance%' THEN 'Performance'
            ELSE 'Other'
        END                           AS LatestPostCategory,
        COALESCE(pv.UpVotes,0) - COALESCE(pv.DownVotes,0) AS NetVotesOnLatest,
        CASE WHEN COALESCE(pv.NegativeFlags,0) > 0 THEN 'Flagged' ELSE 'Clean' END AS LatestPostFlagStatus,
        ts.TagName,
        ts.TagUseCount,
        ts.ExcerptAnswerCount,
        ts.WikiFavorites
    FROM TopUsers tu
    LEFT JOIN UserBadgeCounts ub ON ub.UserId = tu.UserId
    LEFT JOIN LatestPostPerUser lp ON lp.OwnerUserId = tu.UserId AND lp.rn = 1
    LEFT JOIN PostVotesAgg pv      ON pv.PostId = lp.PostId
    LEFT JOIN (
        SELECT lp2.OwnerUserId, TRIM(BOTH '<>' FROM tkn) AS tag_raw
        FROM LatestPostPerUser lp2,
             LATERAL (
                 SELECT unnest(string_to_array(COALESCE(lp2.Tags,''), '><')) AS tkn
             ) s
    ) tags_raw ON tags_raw.OwnerUserId = tu.UserId
    LEFT JOIN TagStats ts ON ts.TagName = tags_raw.tag_raw
    WHERE tu.RepRank <= 50
),
FinalResult AS (
    SELECT 
        c.UserId,
        c.DisplayName,
        c.Reputation,
        c.RepRank,
        c.QuestionCount,
        c.AnswerCount,
        c.TotalScore,
        c.BadgeCount,
        c.GoldBadges,
        c.SilverBadges,
        c.BronzeBadges,
        c.LatestPostTitle,
        c.LatestPostDate,
        c.LatestPostCategory,
        c.NetVotesOnLatest,
        c.LatestPostFlagStatus,
        c.TagName,
        c.TagUseCount,
        c.ExcerptAnswerCount,
        c.WikiFavorites,
        ROW_NUMBER() OVER (PARTITION BY c.UserId ORDER BY c.NetVotesOnLatest DESC) AS PostVoteRank,
        PERCENT_RANK() OVER (ORDER BY c.Reputation DESC) AS RepPercentile
    FROM Combined c
),
FilteredMain AS (
    SELECT *
    FROM FinalResult fr
    WHERE (fr.TagUseCount IS NOT NULL AND fr.TagUseCount > 1000)
       OR (fr.NetVotesOnLatest IS NOT NULL AND fr.NetVotesOnLatest > 10)
    ORDER BY fr.RepRank, fr.NetVotesOnLatest DESC
    LIMIT 200
),
AggregateSummary AS (
    SELECT 
        CAST(NULL AS BIGINT) AS UserId,
        'Aggregate Summary' AS DisplayName,
        CAST(NULL AS INTEGER) AS Reputation,
        CAST(NULL AS INTEGER) AS RepRank,
        CAST(NULL AS DOUBLE PRECISION) AS RepPercentile,
        SUM(fr2.QuestionCount)    AS QuestionCount,
        SUM(fr2.AnswerCount)      AS AnswerCount,
        SUM(fr2.TotalScore)       AS TotalScore,
        SUM(fr2.BadgeCount)       AS BadgeCount,
        SUM(fr2.GoldBadges)       AS GoldBadges,
        SUM(fr2.SilverBadges)     AS SilverBadges,
        SUM(fr2.BronzeBadges)     AS BronzeBadges,
        CAST(NULL AS VARCHAR) AS LatestPostTitle,
        CAST(NULL AS TIMESTAMP) AS LatestPostDate,
        CAST(NULL AS VARCHAR) AS LatestPostCategory,
        SUM(fr2.NetVotesOnLatest) AS NetVotesOnLatest,
        CAST(NULL AS VARCHAR) AS LatestPostFlagStatus,
        CAST(NULL AS VARCHAR) AS TagName,
        SUM(fr2.TagUseCount)      AS TagUseCount,
        CAST(NULL AS INTEGER) AS ExcerptAnswerCount,
        CAST(NULL AS INTEGER) AS WikiFavorites,
        CAST(NULL AS INTEGER) AS PostVoteRank
    FROM FinalResult fr2
    WHERE fr2.RepRank = 1
    LIMIT 1
)

SELECT *
FROM (
    SELECT 
        fm.UserId,
        fm.DisplayName,
        fm.Reputation,
        fm.RepRank,
        fm.RepPercentile,
        fm.QuestionCount,
        fm.AnswerCount,
        fm.TotalScore,
        fm.BadgeCount,
        fm.GoldBadges,
        fm.SilverBadges,
        fm.BronzeBadges,
        fm.LatestPostTitle,
        fm.LatestPostDate,
        fm.LatestPostCategory,
        fm.NetVotesOnLatest,
        fm.LatestPostFlagStatus,
        fm.TagName,
        fm.TagUseCount,
        fm.ExcerptAnswerCount,
        fm.WikiFavorites,
        fm.PostVoteRank
    FROM FilteredMain fm

    UNION ALL

    SELECT 
        a.UserId,
        a.DisplayName,
        a.Reputation,
        a.RepRank,
        a.RepPercentile,
        a.QuestionCount,
        a.AnswerCount,
        a.TotalScore,
        a.BadgeCount,
        a.GoldBadges,
        a.SilverBadges,
        a.BronzeBadges,
        a.LatestPostTitle,
        a.LatestPostDate,
        a.LatestPostCategory,
        a.NetVotesOnLatest,
        a.LatestPostFlagStatus,
        a.TagName,
        a.TagUseCount,
        a.ExcerptAnswerCount,
        a.WikiFavorites,
        a.PostVoteRank
    FROM AggregateSummary a
) final_out;