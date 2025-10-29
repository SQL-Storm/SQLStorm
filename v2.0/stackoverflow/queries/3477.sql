WITH
    user_basic AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            u.CreationDate,
            COALESCE(u.Location, 'Unknown') AS Location,
            LENGTH(u.DisplayName) AS NameLen,
            CASE WHEN u.WebsiteUrl IS NULL THEN 0 ELSE 1 END AS HasWebsite
        FROM Users u
    ),
    post_counts AS (
        SELECT
            p.OwnerUserId AS UserId,
            COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
            COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
            SUM(p.Score) AS TotalScore,
            MAX(p.ViewCount) AS MaxViews,
            MAX(p.CreationDate) AS LastPostDate
        FROM Posts p
        GROUP BY p.OwnerUserId
    ),
    badge_agg AS (
        SELECT
            b.UserId,
            COUNT(*) AS TotalBadges,
            COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
            COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
            COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
            COUNT(*) FILTER (WHERE b.TagBased = TRUE) AS TagBadges
        FROM Badges b
        GROUP BY b.UserId
    ),
    recent_votes AS (
        SELECT
            v.UserId,
            COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesGiven,
            COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesGiven,
            MAX(v.CreationDate) AS LastVoteDate
        FROM Votes v
        GROUP BY v.UserId
    ),
    top_user_tags AS (
        SELECT
            p.OwnerUserId AS UserId,
            t.TagName,
            COUNT(*) AS TagUseCount,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC) AS rn
        FROM Posts p
        JOIN LATERAL (
            SELECT UNNEST(string_to_array(REGEXP_REPLACE(p.Tags, '[<>]', '', 'g'), ';')) AS TagName
        ) AS taglist ON true
        JOIN Tags t ON t.TagName = taglist.TagName
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
        GROUP BY p.OwnerUserId, t.TagName
    ),
    tag_summary AS (
        SELECT
            UserId,
            TagName,
            TagUseCount
        FROM top_user_tags
        WHERE rn = 1
    ),
    combined AS (
        SELECT
            ub.Id AS UserId,
            ub.DisplayName,
            ub.Reputation,
            ub.CreationDate,
            ub.Location,
            ub.NameLen,
            ub.HasWebsite,
            COALESCE(pc.QuestionCount,0) AS QuestionCount,
            COALESCE(pc.AnswerCount,0) AS AnswerCount,
            COALESCE(pc.TotalScore,0) AS TotalScore,
            COALESCE(pc.MaxViews,0) AS MaxViews,
            pc.LastPostDate,
            COALESCE(bg.TotalBadges,0) AS TotalBadges,
            COALESCE(bg.GoldBadges,0) AS GoldBadges,
            COALESCE(bg.SilverBadges,0) AS SilverBadges,
            COALESCE(bg.BronzeBadges,0) AS BronzeBadges,
            COALESCE(bg.TagBadges,0) AS TagBadges,
            COALESCE(rv.UpVotesGiven,0) AS UpVotesGiven,
            COALESCE(rv.DownVotesGiven,0) AS DownVotesGiven,
            rv.LastVoteDate,
            ts.TagName,
            ts.TagUseCount,
            DATE_PART('day', CAST('2024-10-01 12:34:56' AS timestamp) - ub.CreationDate) AS DaysSinceJoin,
            CASE
                WHEN ub.Reputation > 20000 THEN 'Legendary'
                WHEN ub.Reputation > 10000 THEN 'Expert'
                WHEN ub.Reputation > 5000 THEN 'Advanced'
                ELSE 'Novice'
            END AS ReputationTier,
            RANK() OVER (ORDER BY ub.Reputation DESC) AS ReputationRank,
            ROW_NUMBER() OVER (PARTITION BY ub.Location ORDER BY ub.Reputation DESC) AS LocationRank
        FROM user_basic ub
        LEFT JOIN post_counts pc ON pc.UserId = ub.Id
        LEFT JOIN badge_agg bg ON bg.UserId = ub.Id
        LEFT JOIN recent_votes rv ON rv.UserId = ub.Id
        LEFT JOIN tag_summary ts ON ts.UserId = ub.Id
    ),
    users_without_posts AS (
        SELECT
            ub.Id AS UserId,
            ub.DisplayName,
            ub.Reputation,
            ub.CreationDate,
            ub.Location,
            ub.NameLen,
            ub.HasWebsite,
            CAST(NULL AS integer) AS QuestionCount,
            CAST(NULL AS integer) AS AnswerCount,
            CAST(NULL AS numeric) AS TotalScore,
            CAST(NULL AS integer) AS MaxViews,
            CAST(NULL AS timestamp) AS LastPostDate,
            CAST(NULL AS integer) AS TotalBadges,
            CAST(NULL AS integer) AS GoldBadges,
            CAST(NULL AS integer) AS SilverBadges,
            CAST(NULL AS integer) AS BronzeBadges,
            CAST(NULL AS integer) AS TagBadges,
            CAST(NULL AS integer) AS UpVotesGiven,
            CAST(NULL AS integer) AS DownVotesGiven,
            CAST(NULL AS timestamp) AS LastVoteDate,
            'NoPosts' AS TagName,
            CAST(NULL AS integer) AS TagUseCount,
            DATE_PART('day', CAST('2024-10-01 12:34:56' AS timestamp) - ub.CreationDate) AS DaysSinceJoin,
            CASE
                WHEN ub.Reputation > 20000 THEN 'Legendary'
                WHEN ub.Reputation > 10000 THEN 'Expert'
                WHEN ub.Reputation > 5000 THEN 'Advanced'
                ELSE 'Novice'
            END AS ReputationTier,
            CAST(NULL AS integer) AS ReputationRank,
            ROW_NUMBER() OVER (PARTITION BY ub.Location ORDER BY ub.Reputation DESC) AS LocationRank
        FROM user_basic ub
        WHERE NOT EXISTS (
            SELECT 1 FROM Posts p WHERE p.OwnerUserId = ub.Id
        )
    ),
    combined_nonull_tag AS (
        SELECT *
        FROM combined
        WHERE TagName IS NOT NULL
    )
SELECT
    UserId,
    DisplayName,
    Reputation,
    CreationDate,
    Location,
    NameLen,
    HasWebsite,
    QuestionCount,
    AnswerCount,
    TotalScore,
    MaxViews,
    LastPostDate,
    TotalBadges,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    TagBadges,
    UpVotesGiven,
    DownVotesGiven,
    LastVoteDate,
    TagName,
    TagUseCount,
    DaysSinceJoin,
    ReputationTier,
    ReputationRank,
    LocationRank
FROM combined
WHERE ReputationRank <= 100

UNION ALL

SELECT
    UserId,
    DisplayName,
    Reputation,
    CreationDate,
    Location,
    NameLen,
    HasWebsite,
    QuestionCount,
    AnswerCount,
    TotalScore,
    MaxViews,
    LastPostDate,
    TotalBadges,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    TagBadges,
    UpVotesGiven,
    DownVotesGiven,
    LastVoteDate,
    TagName,
    TagUseCount,
    DaysSinceJoin,
    ReputationTier,
    ReputationRank,
    LocationRank
FROM users_without_posts
WHERE Reputation >= 5000

EXCEPT

SELECT
    UserId,
    DisplayName,
    Reputation,
    CreationDate,
    Location,
    NameLen,
    HasWebsite,
    QuestionCount,
    AnswerCount,
    TotalScore,
    MaxViews,
    LastPostDate,
    TotalBadges,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    TagBadges,
    UpVotesGiven,
    DownVotesGiven,
    LastVoteDate,
    TagName,
    TagUseCount,
    DaysSinceJoin,
    ReputationTier,
    ReputationRank,
    LocationRank
FROM combined_nonull_tag

ORDER BY Reputation DESC NULLS LAST
LIMIT 200;