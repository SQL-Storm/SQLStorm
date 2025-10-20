WITH YearlyActivity AS (
    SELECT 
        EXTRACT(YEAR FROM p.CreationDate) AS Year,
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
        SUM(p.Score) AS TotalScore,
        AVG(p.ViewCount) AS AvgViewCount,
        SUM(p.FavoriteCount) AS TotalFavorites,
        COUNT(DISTINCT ph.Id) AS EditCount
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    WHERE p.CreationDate >= DATE '2010-01-01' AND p.PostTypeId IN (1,2)
    GROUP BY EXTRACT(YEAR FROM p.CreationDate), u.Id, u.DisplayName, u.Reputation
),
UserBadges AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserVotes AS (
    SELECT 
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesCast,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesCast
    FROM Votes v
    WHERE v.VoteTypeId IN (2,3)
    GROUP BY v.UserId
),
TagPopularity AS (
    WITH RECURSIVE TagSplit AS (
        SELECT
            EXTRACT(YEAR FROM p.CreationDate) AS Year,
            p.Id AS PostId,
            TRIM(BOTH '<>' FROM p.Tags) AS TagsRemaining,
            CAST(NULL AS VARCHAR) AS Tag,
            0 AS lvl
        FROM Posts p
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL

        UNION ALL

        SELECT
            Year,
            PostId,
            CASE
                WHEN POSITION('><' IN TagsRemaining) > 0 THEN SUBSTR(TagsRemaining, POSITION('><' IN TagsRemaining) + 2)
                ELSE ''
            END AS TagsRemaining,
            CASE
                WHEN POSITION('><' IN TagsRemaining) > 0 THEN SUBSTR(TagsRemaining, 1, POSITION('><' IN TagsRemaining) - 1)
                ELSE TagsRemaining
            END AS Tag,
            lvl + 1
        FROM TagSplit
        WHERE TagsRemaining <> ''
    )
    SELECT
        Year,
        Tag,
        COUNT(PostId) AS TagCount,
        SUM(p.ViewCount) AS TotalViews
    FROM TagSplit ts
    JOIN Posts p ON p.Id = ts.PostId
    WHERE Tag IS NOT NULL AND Tag <> ''
    GROUP BY Year, Tag
),
TopYearlyTags AS (
    SELECT 
        Year,
        Tag,
        TagCount,
        TotalViews,
        ROW_NUMBER() OVER (PARTITION BY Year ORDER BY TagCount DESC, TotalViews DESC) AS TagRank
    FROM TagPopularity
),
UserTagContributions AS (
    WITH RECURSIVE TagSplit2 AS (
        SELECT
            p.Id AS PostId,
            p.OwnerUserId AS OwnerUserId,
            EXTRACT(YEAR FROM p.CreationDate) AS Year,
            TRIM(BOTH '<>' FROM p.Tags) AS TagsRemaining,
            CAST(NULL AS VARCHAR) AS Tag,
            0 AS lvl
        FROM Posts p
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL

        UNION ALL

        SELECT
            PostId,
            OwnerUserId,
            Year,
            CASE
                WHEN POSITION('><' IN TagsRemaining) > 0 THEN SUBSTR(TagsRemaining, POSITION('><' IN TagsRemaining) + 2)
                ELSE ''
            END AS TagsRemaining,
            CASE
                WHEN POSITION('><' IN TagsRemaining) > 0 THEN SUBSTR(TagsRemaining, 1, POSITION('><' IN TagsRemaining) - 1)
                ELSE TagsRemaining
            END AS Tag,
            lvl + 1
        FROM TagSplit2
        WHERE TagsRemaining <> ''
    )
    SELECT 
        ts.Year,
        ts.OwnerUserId AS UserId,
        ts.Tag,
        COUNT(ts.PostId) AS Contributions
    FROM TagSplit2 ts
    WHERE ts.Tag IS NOT NULL AND ts.Tag <> ''
    GROUP BY ts.Year, ts.OwnerUserId, ts.Tag
),
RankedUsers AS (
    SELECT 
        ya.Year,
        ya.UserId,
        ya.DisplayName,
        ya.Reputation,
        ya.QuestionsAsked,
        ya.AnswersGiven,
        ya.TotalScore,
        ya.AvgViewCount,
        ya.TotalFavorites,
        ya.EditCount,
        COALESCE(ub.GoldBadges, 0) AS GoldBadges,
        COALESCE(ub.SilverBadges, 0) AS SilverBadges,
        COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(uv.UpVotesCast, 0) AS UpVotesCast,
        COALESCE(uv.DownVotesCast, 0) AS DownVotesCast,
        tty.Tag AS TopTag,
        utc.Contributions AS TopTagContributions,
        ROW_NUMBER() OVER (PARTITION BY ya.Year ORDER BY ya.TotalScore DESC, (ya.QuestionsAsked + ya.AnswersGiven) DESC) AS ActivityRank
    FROM YearlyActivity ya
    LEFT JOIN UserBadges ub ON ya.UserId = ub.UserId
    LEFT JOIN UserVotes uv ON ya.UserId = uv.UserId
    LEFT JOIN TopYearlyTags tty ON ya.Year = tty.Year AND tty.TagRank = 1
    LEFT JOIN UserTagContributions utc ON ya.Year = utc.Year AND ya.UserId = utc.UserId AND utc.Tag = tty.Tag
)
SELECT 
    Year,
    UserId,
    DisplayName,
    Reputation,
    QuestionsAsked,
    AnswersGiven,
    TotalScore,
    AvgViewCount,
    TotalFavorites,
    EditCount,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    UpVotesCast,
    DownVotesCast,
    TopTag,
    TopTagContributions,
    ActivityRank
FROM RankedUsers
WHERE ActivityRank <= 5
ORDER BY Year DESC, ActivityRank ASC;