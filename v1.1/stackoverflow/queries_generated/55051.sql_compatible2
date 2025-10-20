WITH 
QuestionTags AS (
    SELECT 
        p.Id                                   AS QuestionId,
        p.OwnerUserId                           AS OwnerUserId,
        p.Score                                 AS QuestionScore,
        p.CreationDate                          AS QuestionDate,
        UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1
),
Answers AS (
    SELECT 
        a.Id           AS AnswerId,
        a.ParentId     AS QuestionId,
        a.OwnerUserId  AS OwnerUserId,
        a.Score        AS AnswerScore,
        a.CreationDate AS AnswerDate
    FROM Posts a
    WHERE a.PostTypeId = 2
),
TagAnswers AS (
    SELECT 
        qt.TagName,
        ans.OwnerUserId,
        ans.AnswerScore,
        ans.AnswerDate,
        ans.AnswerId,
        ans.QuestionId
    FROM QuestionTags qt
    JOIN Answers ans ON ans.QuestionId = qt.QuestionId
),
UserTagStats AS (
    SELECT 
        ta.TagName,
        u.Id                              AS UserId,
        u.DisplayName                     AS DisplayName,
        u.Reputation                      AS Reputation,
        COUNT(*)                          AS AnswerCount,
        AVG(ta.AnswerScore)               AS AvgAnswerScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM TagAnswers ta
    JOIN Users u ON u.Id = ta.OwnerUserId
    LEFT JOIN Votes v ON v.PostId = ta.AnswerId AND v.VoteTypeId IN (2,3)
    GROUP BY ta.TagName, u.Id, u.DisplayName, u.Reputation
),
UserBadgeCounts AS (
    SELECT 
        b.UserId,
        COUNT(*)                         AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserTagStatsWithBadges AS (
    SELECT 
        uts.TagName,
        uts.UserId,
        uts.DisplayName,
        uts.Reputation,
        uts.AnswerCount,
        uts.AvgAnswerScore,
        uts.UpVoteCount,
        uts.DownVoteCount,
        COALESCE(ubc.TotalBadges,0)   AS TotalBadges,
        COALESCE(ubc.GoldBadges,0)    AS GoldBadges,
        COALESCE(ubc.SilverBadges,0)  AS SilverBadges,
        COALESCE(ubc.BronzeBadges,0)  AS BronzeBadges
    FROM UserTagStats uts
    LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = uts.UserId
),
RankedUsers AS (
    SELECT 
        uts.TagName,
        uts.UserId,
        uts.DisplayName,
        uts.Reputation,
        uts.AnswerCount,
        uts.AvgAnswerScore,
        uts.UpVoteCount,
        uts.DownVoteCount,
        uts.TotalBadges,
        uts.GoldBadges,
        uts.SilverBadges,
        uts.BronzeBadges,
        ROW_NUMBER() OVER (
            PARTITION BY uts.TagName
            ORDER BY 
                uts.AnswerCount DESC,
                uts.AvgAnswerScore DESC,
                uts.Reputation DESC,
                uts.TotalBadges DESC
        ) AS RankInTag
    FROM UserTagStatsWithBadges uts
)
SELECT 
    r.TagName,
    r.RankInTag,
    r.UserId,
    r.DisplayName,
    r.Reputation,
    r.AnswerCount,
    ROUND(CAST(r.AvgAnswerScore AS DECIMAL),2)   AS AvgAnswerScore,
    r.UpVoteCount,
    r.DownVoteCount,
    r.TotalBadges,
    r.GoldBadges,
    r.SilverBadges,
    r.BronzeBadges
FROM RankedUsers r
WHERE r.RankInTag <= 5
ORDER BY r.TagName, r.RankInTag;