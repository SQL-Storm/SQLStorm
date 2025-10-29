-- {"query": "3733.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2198}
WITH
UserBadges AS (
    SELECT
        u.Id                                     AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id)                              AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date)                              AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserPosts AS (
    SELECT
        p.OwnerUserId                                 AS UserId,
        COUNT(*)                                      AS QuestionCount,
        AVG(p.Score)                                  AS AvgQuestionScore,
        SUM(p.ViewCount)                              AS TotalViews,
        MAX(p.CreationDate)                           AS LatestQuestionDate,
        STRING_AGG(
            COALESCE(NULLIF(p.Tags, ''), '<no-tags>'),
            ';'
        )                                             AS AllTagsConcat
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
UserVotes AS (
    SELECT
        v.UserId                                      AS UserId,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END)    AS UpVotesCast,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END)  AS DownVotesCast,
        SUM(CASE WHEN vt.Name = 'Favorite' THEN 1 ELSE 0 END) AS FavoritesCast
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.UserId
),
UserRanked AS (
    SELECT
        ub.UserId,
        ub.DisplayName,
        ub.Reputation,
        ub.TotalBadges,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        up.QuestionCount,
        up.AvgQuestionScore,
        up.TotalViews,
        uv.UpVotesCast,
        uv.DownVotesCast,
        uv.FavoritesCast,
        ROW_NUMBER() OVER (
            ORDER BY ub.Reputation DESC, ub.TotalBadges DESC
        )                                            AS RepBadgeRank
    FROM UserBadges ub
    LEFT JOIN UserPosts up   ON up.UserId   = ub.UserId
    LEFT JOIN UserVotes uv   ON uv.UserId   = ub.UserId
),
LatestQuestion AS (
    SELECT
        ur.UserId,
        lq.Title,
        lq.CreationDate,
        -- split tags like '<tag1><tag2>' into array ['tag1','tag2']; adjust function per dialect if needed
        CASE
          WHEN COALESCE(NULLIF(lq.Tags, ''), '<no-tags>') = '<no-tags>' THEN ARRAY['<no-tags>']
          ELSE (
            SELECT ARRAY_AGG(trim(BOTH '<>' FROM part))
            FROM (
              SELECT regexp_substr(COALESCE(NULLIF(lq.Tags, ''), '<no-tags>'), '<[^>]+>', 1, generate_series) AS part
              FROM (SELECT 1 AS generate_series) gs -- placeholder; some dialects need different approaches
            ) s
          )
        END                                            AS TagArray
    FROM UserRanked ur
    LEFT JOIN LATERAL (
        SELECT
            p.Title,
            p.CreationDate,
            p.Tags
        FROM Posts p
        WHERE p.OwnerUserId = ur.UserId
          AND p.PostTypeId = 1
        ORDER BY p.CreationDate DESC
        LIMIT 1
    ) lq ON TRUE
)
SELECT
    ur.UserId,
    ur.DisplayName,
    ur.Reputation,
    ur.RepBadgeRank,
    ur.TotalBadges,
    ur.GoldBadges,
    ur.SilverBadges,
    ur.BronzeBadges,
    COALESCE(ur.QuestionCount,0)      AS QuestionCount,
    COALESCE(ROUND(CAST(ur.AvgQuestionScore AS NUMERIC),2),0) AS AvgQuestionScore,
    COALESCE(ur.TotalViews,0)         AS TotalViews,
    COALESCE(ur.UpVotesCast,0)        AS UpVotesCast,
    COALESCE(ur.DownVotesCast,0)      AS DownVotesCast,
    COALESCE(ur.FavoritesCast,0)      AS FavoritesCast,
    lq.Title                          AS LatestQuestionTitle,
    lq.CreationDate                   AS LatestQuestionDate,
    COALESCE(lq.TagArray, ARRAY['<none>']) AS LatestQuestionTags
FROM UserRanked ur
LEFT JOIN LatestQuestion lq
    ON lq.UserId = ur.UserId
WHERE ur.RepBadgeRank <= 100

UNION ALL

SELECT
    NULL               AS UserId,
    'Overall Summary'  AS DisplayName,
    NULL               AS Reputation,
    NULL               AS RepBadgeRank,
    SUM(TotalBadges)   AS TotalBadges,
    SUM(GoldBadges)    AS GoldBadges,
    SUM(SilverBadges)  AS SilverBadges,
    SUM(BronzeBadges)  AS BronzeBadges,
    SUM(QuestionCount) AS QuestionCount,
    ROUND(AVG(CAST(AvgQuestionScore AS NUMERIC)),2) AS AvgQuestionScore,
    SUM(TotalViews)    AS TotalViews,
    SUM(UpVotesCast)   AS UpVotesCast,
    SUM(DownVotesCast) AS DownVotesCast,
    SUM(FavoritesCast) AS FavoritesCast,
    NULL               AS LatestQuestionTitle,
    NULL               AS LatestQuestionDate,
    NULL               AS LatestQuestionTags
FROM UserRanked;