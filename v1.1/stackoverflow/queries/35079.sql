WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COALESCE(SUM(p.Score),0) AS TotalPostScore,
        COALESCE(SUM(c.Score),0) AS TotalCommentScore,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0) AS UpVotesGiven,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END),0) AS DownVotesGiven,
        MAX(u.LastAccessDate) AS LastAccessDate,
        u.CreationDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.LastAccessDate, u.CreationDate
),
TopTags AS (
    -- split tag string like "<tag1><tag2>" into rows using a standard SQL approach
    SELECT
        pt.OwnerUserId AS UserId,
        lower(TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM tag))) AS TagName,
        COUNT(*) AS TagUseCount
    FROM Posts pt
    CROSS JOIN LATERAL (
        SELECT
            regexp_split_to_table(
                -- remove leading and trailing angle brackets if present, then split on '><'
                CASE
                    WHEN pt.Tags LIKE '<%>' THEN substring(pt.Tags FROM 2 FOR (length(pt.Tags) - 2))
                    ELSE pt.Tags
                END,
                '><'
            ) AS tag
    ) AS s
    WHERE pt.PostTypeId = 1
    AND pt.OwnerUserId IS NOT NULL
    GROUP BY pt.OwnerUserId, lower(TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM tag)))
),
UserTopTags AS (
    SELECT
        UserId,
        TagName,
        TagUseCount,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagUseCount DESC, TagName) AS TagRank
    FROM TopTags
),
UserBadges AS (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.PostCount,
    ua.CommentCount,
    ua.VoteCount,
    ua.TotalPostScore,
    ua.TotalCommentScore,
    ua.UpVotesGiven,
    ua.DownVotesGiven,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.TotalBadges,
    array_agg(utt.TagName ORDER BY utt.TagRank) FILTER (WHERE utt.TagRank <= 5) AS Top5Tags,
    ua.LastAccessDate,
    ua.CreationDate
FROM UserActivity ua
LEFT JOIN UserBadges ub ON ua.UserId = ub.UserId
LEFT JOIN UserTopTags utt ON ua.UserId = utt.UserId AND utt.TagRank <= 5
GROUP BY
    ua.UserId,
    ua.DisplayName,
    ua.PostCount,
    ua.CommentCount,
    ua.VoteCount,
    ua.TotalPostScore,
    ua.TotalCommentScore,
    ua.UpVotesGiven,
    ua.DownVotesGiven,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.TotalBadges,
    ua.LastAccessDate,
    ua.CreationDate
ORDER BY
    (COALESCE(ua.TotalPostScore,0) + COALESCE(ua.TotalCommentScore,0)) DESC,
    ub.GoldBadges DESC,
    ua.PostCount DESC,
    ua.CommentCount DESC
LIMIT 100;