WITH UserBadgeCounts AS (
    SELECT 
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldCount,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverCount,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeCount
    FROM Badges
    GROUP BY UserId
),
RecentQuestions AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
),
-- helper to split tags for a given post's Tags string into rows of tag names
SplitTags AS (
    SELECT
        p.Id AS PostId,
        trim(both ' ' FROM split_part(replaced, '|', n)) AS TagName
    FROM (
        SELECT
            Id,
            -- remove leading '<' and trailing '>' then replace '><' with '|' as delimiter
            CASE
              WHEN char_length(Tags) >= 2 THEN regexp_replace(substring(Tags FROM 2 FOR char_length(Tags)-2), '><', '|', 'g')
              ELSE ''
            END AS replaced,
            Tags
        FROM Posts
        WHERE PostTypeId = 1
    ) p,
    LATERAL (
        SELECT generate_series(1, greatest(1, 1 + length(p.replaced) - length(replace(p.replaced, '|', '')))) AS n
    ) nums
    WHERE p.replaced <> ''
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        ub.GoldCount,
        ub.SilverCount,
        ub.BronzeCount,
        rq.Id AS RecentQuestionId,
        rq.Score AS RecentScore,
        (
            SELECT tt.TagName
            FROM (
                SELECT st.TagName
                FROM SplitTags st
                JOIN Posts p2 ON p2.Id = st.PostId
                WHERE p2.OwnerUserId = u.Id
                GROUP BY st.TagName
                ORDER BY COUNT(*) DESC
                LIMIT 1
            ) best
            JOIN Tags tt ON tt.TagName = best.TagName
            LIMIT 1
        ) AS MostUsedTag
    FROM Users u
    LEFT JOIN UserBadgeCounts ub ON u.Id = ub.UserId
    LEFT JOIN RecentQuestions rq ON u.Id = rq.OwnerUserId AND rq.rn = 1
),
CommentAgg AS (
    SELECT 
        p.OwnerUserId,
        COUNT(*) AS CommentCount
    FROM Comments c
    JOIN Posts p ON c.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
VoteAgg AS (
    SELECT 
        p.OwnerUserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
Combined AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        COALESCE(us.GoldCount, 0) AS GoldBadges,
        COALESCE(us.SilverCount, 0) AS SilverBadges,
        COALESCE(us.BronzeCount, 0) AS BronzeBadges,
        us.RecentQuestionId,
        us.RecentScore,
        us.MostUsedTag,
        COALESCE(ca.CommentCount, 0) AS TotalCommentsOnQuestions,
        COALESCE(va.UpVotes, 0) AS TotalUpVotes,
        COALESCE(va.DownVotes, 0) AS TotalDownVotes,
        (us.Reputation * (COALESCE(us.GoldCount, 0) + 0.5 * COALESCE(us.SilverCount, 0))) AS WeightedScore
    FROM UserStats us
    LEFT JOIN CommentAgg ca ON us.UserId = ca.OwnerUserId
    LEFT JOIN VoteAgg va ON us.UserId = va.OwnerUserId
),
Ranked AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        RecentQuestionId,
        RecentScore,
        MostUsedTag,
        TotalCommentsOnQuestions,
        TotalUpVotes,
        TotalDownVotes,
        WeightedScore,
        ROW_NUMBER() OVER (ORDER BY WeightedScore DESC) AS Rank
    FROM Combined
    WHERE Reputation > 1000
)
SELECT 
    Rank,
    UserId,
    DisplayName,
    Reputation,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    RecentQuestionId,
    RecentScore,
    MostUsedTag,
    TotalCommentsOnQuestions,
    TotalUpVotes,
    TotalDownVotes,
    WeightedScore
FROM Ranked
WHERE Rank <= 100

UNION ALL

SELECT 
    CAST(NULL AS INTEGER) AS Rank,
    CAST(NULL AS INTEGER) AS UserId,
    CAST('---' AS VARCHAR) AS DisplayName,
    CAST(NULL AS INTEGER) AS Reputation,
    CAST(NULL AS INTEGER) AS GoldBadges,
    CAST(NULL AS INTEGER) AS SilverBadges,
    CAST(NULL AS INTEGER) AS BronzeBadges,
    CAST(NULL AS INTEGER) AS RecentQuestionId,
    CAST(NULL AS INTEGER) AS RecentScore,
    CAST(NULL AS VARCHAR) AS MostUsedTag,
    CAST(NULL AS INTEGER) AS TotalCommentsOnQuestions,
    CAST(NULL AS INTEGER) AS TotalUpVotes,
    CAST(NULL AS INTEGER) AS TotalDownVotes,
    CAST(NULL AS NUMERIC) AS WeightedScore

ORDER BY 
    Rank ASC NULLS FIRST;