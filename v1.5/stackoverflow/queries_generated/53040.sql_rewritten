-- {"query": "53040.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 945} 
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
    WHERE p.CreationDate >= '2010-01-01' AND p.PostTypeId IN (1,2)
    GROUP BY Year, u.Id, u.DisplayName, u.Reputation
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
    SELECT 
        EXTRACT(YEAR FROM p.CreationDate) AS Year,
        UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag,
        COUNT(p.Id) AS TagCount,
        SUM(p.ViewCount) AS TotalViews
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
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
    SELECT 
        ya.Year,
        ya.UserId,
        t.Tag,
        COUNT(p.Id) AS Contributions
    FROM YearlyActivity ya
    JOIN Posts p ON ya.UserId = p.OwnerUserId AND EXTRACT(YEAR FROM p.CreationDate) = ya.Year
    CROSS JOIN LATERAL UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(Tag)
    WHERE p.PostTypeId = 1
    GROUP BY ya.Year, ya.UserId, t.Tag
),
RankedUsers AS (
    SELECT 
        ya.*,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        uv.UpVotesCast,
        uv.DownVotesCast,
        tty.Tag AS TopTag,
        utc.Contributions AS TopTagContributions,
        ROW_NUMBER() OVER (PARTITION BY ya.Year ORDER BY ya.TotalScore DESC, ya.QuestionsAsked + ya.AnswersGiven DESC) AS ActivityRank
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